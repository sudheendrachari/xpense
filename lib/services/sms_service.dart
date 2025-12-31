import 'package:xpense/models/transaction.dart';
import 'package:xpense/services/database_service.dart';
import 'package:xpense/utils/merchant_aliases.dart';
import 'package:xpense/utils/sms_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

/// SMS Service - New Architecture
/// 
/// Flow:
/// 1. Initial Sync (one-time): Fetch ALL SMS → filter bank SMS → store in raw_sms → parse → transactions
/// 2. Delta Sync (on app open): Fetch recent SMS → filter new bank SMS → store in raw_sms → parse → transactions
/// 3. UI reads from transactions table (instant)
class SmsService {
  final DatabaseService _db = DatabaseService();

  // ============================================================================
  // BANK SMS DETECTION
  // ============================================================================

  /// Check if sender is a bank SMS using generic pattern
  /// Validated patterns: BK, BN, INB, BANK
  static bool isBankSms(String sender) {
    final s = sender.toUpperCase();
    return s.contains('BK') || 
           s.contains('BN') || 
           s.contains('INB') || 
           s.contains('BANK');
  }

  /// Get bank name from sender
  static String getBankName(String sender) {
    final s = sender.toUpperCase();
    if (s.contains('HDFC')) return 'HDFC';
    if (s.contains('AXIS')) return 'AXIS';
    if (s.contains('SBI')) return 'SBI';
    if (s.contains('ICICI')) return 'ICICI';
    if (s.contains('KOTAK')) return 'KOTAK';
    if (s.contains('PNB')) return 'PNB';
    // Default: extract from sender
    return sender.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
  }

  // ============================================================================
  // INITIAL SYNC (One-time on first launch)
  // ============================================================================

  /// Perform initial sync - fetch ALL SMS from device, filter bank SMS, store and parse
  /// This is called only once when the app is first opened
  Future<void> performInitialSync({
    Function(int current, int total, String status)? onProgress,
  }) async {
    debugPrint('SMS_SERVICE: Starting initial sync...');
    
    final status = await Permission.sms.request();
    if (!status.isGranted) {
      throw Exception('SMS Permission denied');
    }

    onProgress?.call(0, 100, 'Fetching SMS from device...');

    // Capture token for isolate
    final RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;

    // Step 1: Fetch all SMS and filter bank SMS in background isolate
    final List<Map<String, dynamic>> bankSmsData = await compute(
      _fetchAndFilterBankSmsInIsolate,
      rootIsolateToken,
    );

    debugPrint('SMS_SERVICE: Fetched ${bankSmsData.length} bank SMS from device');
    onProgress?.call(30, 100, 'Found ${bankSmsData.length} bank SMS...');

    // Step 2: Store bank SMS in raw_sms table
    onProgress?.call(40, 100, 'Storing SMS in database...');
    await _db.insertRawSmsBatch(bankSmsData);
    debugPrint('SMS_SERVICE: Stored ${bankSmsData.length} bank SMS in raw_sms');

    // Step 3: Parse all raw SMS into transactions
    onProgress?.call(50, 100, 'Parsing transactions...');
    await _parseAndStoreTransactionsFromRawSms(onProgress: (current, total, status) {
      // Map parsing progress to 50-90%
      final overallProgress = 50 + ((current / total) * 40).round();
      onProgress?.call(overallProgress, 100, status);
    });

    // Step 4: Mark initial sync as complete
    await _db.setInitialSyncCompleted();
    await _db.setLastSyncTimestamp(DateTime.now());

    onProgress?.call(100, 100, 'Initial sync complete!');
    debugPrint('SMS_SERVICE: Initial sync complete');
  }

  // ============================================================================
  // DELTA SYNC (On subsequent app opens)
  // ============================================================================

  /// Perform delta sync - fetch only new SMS since last sync
  /// This is called on app open after initial sync is complete
  Future<int> performDeltaSync({
    Function(int current, int total, String status)? onProgress,
  }) async {
    debugPrint('SMS_SERVICE: Starting delta sync...');

    final lastSync = await _db.getLastSyncTimestamp();
    final latestRawSms = await _db.getLatestRawSmsDate();
    
    // Calculate sync start: use whichever is more recent (with 5 min buffer)
    DateTime syncFrom;
    if (lastSync == null && latestRawSms == null) {
      // Shouldn't happen if initial sync was done, but fallback to last 24h
      syncFrom = DateTime.now().subtract(const Duration(hours: 24));
    } else if (lastSync == null) {
      syncFrom = latestRawSms!.subtract(const Duration(minutes: 5));
    } else if (latestRawSms == null) {
      syncFrom = lastSync.subtract(const Duration(minutes: 5));
    } else {
      // Use the more recent one, minus 5 minutes buffer
      final moreRecent = lastSync.isAfter(latestRawSms) ? lastSync : latestRawSms;
      syncFrom = moreRecent.subtract(const Duration(minutes: 5));
    }

    debugPrint('SMS_SERVICE: Delta sync from: $syncFrom');

    final status = await Permission.sms.request();
    if (!status.isGranted) {
      debugPrint('SMS_SERVICE: SMS permission denied');
      return 0;
    }

    // Capture token for isolate
    final RootIsolateToken rootIsolateToken = RootIsolateToken.instance!;

    // Fetch new SMS in background
    final List<Map<String, dynamic>> newBankSms = await compute(
      _fetchAndFilterBankSmsInIsolate,
      rootIsolateToken,
    );

    // Filter to only SMS after syncFrom
    final filteredSms = newBankSms.where((sms) {
      final dateStr = sms['date'] as String?;
      if (dateStr == null || dateStr.isEmpty) return false;
      try {
        final date = DateTime.parse(dateStr);
        return date.isAfter(syncFrom);
      } catch (e) {
        return false;
      }
    }).toList();

    debugPrint('SMS_SERVICE: Found ${filteredSms.length} new bank SMS since $syncFrom');

    if (filteredSms.isEmpty) {
      await _db.setLastSyncTimestamp(DateTime.now());
      return 0;
    }

    // Filter out SMS that already exist in raw_sms
    List<Map<String, dynamic>> newSmsToStore = [];
    for (var sms in filteredSms) {
      final exists = await _db.rawSmsExists(sms['id'] as String);
      if (!exists) {
        newSmsToStore.add(sms);
      }
    }

    debugPrint('SMS_SERVICE: ${newSmsToStore.length} SMS are new (not in DB)');

    if (newSmsToStore.isEmpty) {
      await _db.setLastSyncTimestamp(DateTime.now());
      return 0;
    }

    // Store new SMS
    await _db.insertRawSmsBatch(newSmsToStore);

    // Parse new SMS into transactions
    final newTransactions = await _parseRawSmsToTransactions(newSmsToStore);
    
    // Store new transactions
    int savedCount = 0;
    for (var tx in newTransactions) {
      final exists = await _db.transactionExists(tx.id);
      if (!exists) {
        await _db.insertTransaction(tx);
        savedCount++;
      }
    }

    await _db.setLastSyncTimestamp(DateTime.now());
    debugPrint('SMS_SERVICE: Delta sync complete - saved $savedCount new transactions');

    return savedCount;
  }

  // ============================================================================
  // PARSING METHODS
  // ============================================================================

  /// Parse all raw SMS from database and store as transactions
  Future<void> _parseAndStoreTransactionsFromRawSms({
    Function(int current, int total, String status)? onProgress,
  }) async {
    final rawSmsData = await _db.getAllRawSms();
    debugPrint('SMS_SERVICE: Parsing ${rawSmsData.length} raw SMS from database');

    final transactions = await _parseRawSmsToTransactions(rawSmsData);
    debugPrint('SMS_SERVICE: Parsed ${transactions.length} transactions');

    // Store transactions (update UI every 50 to avoid excessive rebuilds)
    int count = 0;
    const progressInterval = 50;
    for (var tx in transactions) {
      count++;
      
      // Only update progress every 50 items or on last item
      if (count % progressInterval == 0 || count == transactions.length) {
        onProgress?.call(count, transactions.length, 'Saving transaction $count/${transactions.length}');
      }
      
      final exists = await _db.transactionExists(tx.id);
      if (!exists) {
        await _db.insertTransaction(tx);
      }
    }

    debugPrint('SMS_SERVICE: Stored ${transactions.length} transactions');
  }

  /// Parse raw SMS data (from DB) into transactions
  Future<List<Transaction>> _parseRawSmsToTransactions(List<Map<String, dynamic>> rawSmsData) async {
    List<_RawTx> rawTxs = [];

    for (var sms in rawSmsData) {
      final id = sms['id'] as String? ?? '';
      final sender = (sms['sender'] as String? ?? '').toUpperCase();
      final body = sms['body'] as String? ?? '';
      final dateStr = sms['date'] as String?;
      
      if (dateStr == null || dateStr.isEmpty) continue;
      
      DateTime date;
      try {
        date = DateTime.parse(dateStr);
      } catch (e) {
        continue;
      }

      final raw = _parseSmsBody(id, sender, body, date);
      if (raw != null) {
        rawTxs.add(raw);
      }
    }

    // Sort by date ascending for OTP merging
    rawTxs.sort((a, b) => a.date.compareTo(b.date));

    // Smart merge OTPs with transactions
    final merged = _mergeOtpsAndCreateTransactions(rawTxs);
    
    // Deduplicate transactions (e.g., PAYMENT ALERT + UPDATE for same transaction)
    return _deduplicateTransactions(merged);
  }

  /// Parse SMS body to extract transaction data
  _RawTx? _parseSmsBody(String id, String sender, String body, DateTime date) {
    final bankName = getBankName(sender);
    final parsed = SmsParser.parse(body, sender: sender);
    
    if (!parsed.parseSuccess) return null;

    return _RawTx(
      id, 
      parsed.amount, 
      parsed.merchant, 
      date, 
      parsed.type, 
      body, 
      bankName, 
      parsed.isOtp,
    );
  }

  /// Merge OTPs with their corresponding transactions
  List<Transaction> _mergeOtpsAndCreateTransactions(List<_RawTx> rawTxs) {
  List<Transaction> finalTransactions = [];
  List<_RawTx> pendingOtps = [];

  for (var tx in rawTxs) {
    if (tx.isOtp) {
      pendingOtps.add(tx);
      pendingOtps.removeWhere((otp) => tx.date.difference(otp.date).inMinutes > 10);
    } else {
      int matchIndex = -1;
      
      for (int i = pendingOtps.length - 1; i >= 0; i--) {
         final otp = pendingOtps[i];
         if (otp.bankName == tx.bankName && 
             (otp.amount - tx.amount).abs() < 0.01 && 
             tx.date.difference(otp.date).inMinutes < 10) {
           matchIndex = i;
           break;
         }
      }

      if (matchIndex != -1) {
        final otp = pendingOtps[matchIndex];
        String finalMerchant = MerchantAliases.normalize(tx.merchant);
        if (otp.merchant != 'Unknown' && otp.merchant.isNotEmpty) {
           finalMerchant = MerchantAliases.normalize(otp.merchant);
        }

        finalTransactions.add(Transaction(
          id: tx.msgId,
          amount: tx.amount,
          merchant: finalMerchant,
          date: tx.date,
          category: SmsParser.guessCategory(finalMerchant),
          type: tx.type,
          body: "${tx.body}\n---\nMerged with OTP: ${otp.body}", 
          bankName: tx.bankName,
        ));
        
        pendingOtps.removeAt(matchIndex);
      } else {
        finalTransactions.add(Transaction(
          id: tx.msgId,
          amount: tx.amount,
          merchant: MerchantAliases.normalize(tx.merchant),
          date: tx.date,
          category: SmsParser.guessCategory(MerchantAliases.normalize(tx.merchant)),
          type: tx.type,
          body: tx.body,
          bankName: tx.bankName,
        ));
      }
    }
  }
  
  return finalTransactions.reversed.toList();
}

  /// Deduplicate transactions that appear multiple times (e.g., PAYMENT ALERT + UPDATE)
  /// Keeps the first occurrence when same amount, type, bank within 6 hours
  List<Transaction> _deduplicateTransactions(List<Transaction> transactions) {
    if (transactions.length < 2) return transactions;
    
    List<Transaction> deduplicated = [];
    
    for (var tx in transactions) {
      // Check if this is a duplicate of an existing transaction (6 hour window)
      bool isDuplicate = deduplicated.any((existing) {
        // Must be same bank, amount, and within 6 hours
        if (existing.bankName != tx.bankName) return false;
        if ((existing.amount - tx.amount).abs() >= 0.01) return false;
        if (existing.date.difference(tx.date).inHours.abs() >= 6) return false;
        
        // Same type: standard duplicate (PAYMENT ALERT + UPDATE)
        if (existing.type == tx.type) {
          return existing.merchant == tx.merchant ||
                 existing.merchant == 'Unknown' ||
                 tx.merchant == 'Unknown';
        }
        
        // Different types: NEFT credit confirmation + debit notification
        // Both must contain "NEFT" in body
        if (existing.body.toUpperCase().contains('NEFT') && 
            tx.body.toUpperCase().contains('NEFT')) {
          return true;
        }
        
        return false;
      });
      
      if (!isDuplicate) {
        deduplicated.add(tx);
      } else {
        debugPrint('DEDUP: Skipping duplicate - ${tx.merchant} | ${tx.amount} | ${tx.date}');
      }
    }
    
    debugPrint('DEDUP: ${transactions.length} -> ${deduplicated.length} transactions');
    return deduplicated;
  }

  // ============================================================================
  // LEGACY METHOD (for backward compatibility during transition)
  // ============================================================================

  /// Get transactions for a date range (reads from DB only - instant!)
  Future<List<Transaction>> getTransactionsInRange(DateTime start, DateTime end) async {
    return await _db.getTransactionsInRange(start, end);
  }

  // ============================================================================
  // REAL-TIME SMS PROCESSING (from BroadcastReceiver)
  // ============================================================================

  /// Process a single SMS received in real-time
  Future<bool> processSingleSms({
    required String sender,
    required String body,
    required int timestamp,
    required String id,
    Function(Transaction)? onTransactionSaved,
  }) async {
    try {
      debugPrint('SMS_SERVICE: Processing real-time SMS from $sender');
      
      // Check if it's a bank SMS
      if (!isBankSms(sender)) {
        debugPrint('SMS_SERVICE: Not a bank SMS, ignoring');
        return false;
      }

      // Check if already exists
      final smsExists = await _db.rawSmsExists(id);
      if (smsExists) {
        debugPrint('SMS_SERVICE: SMS $id already exists, skipping');
        return false;
      }

      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final bankName = getBankName(sender);

      // Store in raw_sms
      await _db.insertRawSmsBatch([{
        'id': id,
        'sender': sender,
        'body': body,
        'date': date.toIso8601String(),
        'bank_name': bankName,
      }]);

      // Parse SMS
      final rawTx = _parseSmsBody(id, sender, body, date);
      if (rawTx == null) {
        debugPrint('SMS_SERVICE: Failed to parse SMS, no transaction data');
        return false;
      }

      // Check if transaction exists
      final txExists = await _db.transactionExists(id);
      if (txExists) {
        debugPrint('SMS_SERVICE: Transaction $id already exists');
        return false;
      }

      // Create and save transaction
      final normalizedMerchant = MerchantAliases.normalize(rawTx.merchant);
      final transaction = Transaction(
        id: id,
        amount: rawTx.amount,
        merchant: normalizedMerchant,
        date: rawTx.date,
        category: SmsParser.guessCategory(normalizedMerchant),
        type: rawTx.type,
        body: rawTx.body,
        bankName: rawTx.bankName,
      );

      await _db.insertTransaction(transaction);
      debugPrint('SMS_SERVICE: Saved real-time transaction: ${transaction.merchant} - ${transaction.amount}');

      onTransactionSaved?.call(transaction);
      return true;
    } catch (e) {
      debugPrint('SMS_SERVICE: Error processing real-time SMS: $e');
      return false;
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  (DateTime, DateTime) getBillingCycleDates(DateTime currentDate) {
    final start = DateTime(currentDate.year, currentDate.month, 1);
    final end = DateTime(currentDate.year, currentDate.month + 1, 0);
    return (start, end);
  }
}

// ============================================================================
// ISOLATE FUNCTIONS (must be top-level)
// ============================================================================

/// Fetch all SMS from device and filter to bank SMS only
Future<List<Map<String, dynamic>>> _fetchAndFilterBankSmsInIsolate(RootIsolateToken token) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final SmsQuery query = SmsQuery();
  List<SmsMessage> messages = [];

  try {
    messages = await query.querySms(kinds: [SmsQueryKind.inbox]);
    debugPrint('ISOLATE: Fetched ${messages.length} total SMS from device');
  } catch (e) {
    debugPrint('ISOLATE: Error fetching SMS: $e');
    return [];
  }

  // Filter to bank SMS only and convert to maps
  int bankCount = 0;
  final List<Map<String, dynamic>> bankSmsData = [];

  for (var msg in messages) {
    final sender = msg.sender ?? '';
    if (!SmsService.isBankSms(sender)) continue;

    bankCount++;
    bankSmsData.add({
      'id': msg.id.toString(),
      'sender': sender,
      'body': msg.body ?? '',
      'date': msg.date?.toIso8601String() ?? '',
      'bank_name': SmsService.getBankName(sender),
    });
  }

  debugPrint('ISOLATE: Filtered to $bankCount bank SMS');
  return bankSmsData;
}


class _RawTx {
  final String msgId;
  final double amount;
  final String merchant;
  final DateTime date;
  final TransactionType type;
  final String body;
  final String bankName;
  final bool isOtp;

  _RawTx(this.msgId, this.amount, this.merchant, this.date, this.type, this.body, this.bankName, this.isOtp);
}
