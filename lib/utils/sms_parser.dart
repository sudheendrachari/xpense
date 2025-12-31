import 'package:xpense/models/transaction.dart';
import 'package:xpense/utils/bank_patterns.dart';
import 'package:xpense/utils/merchant_categories.dart';

/// SMS Parser utility - extracts transaction data from bank SMS
/// Enhanced with patterns from Mezo app analysis
class SmsParser {
  /// Parse SMS body and extract transaction details
  static ParsedSms parse(String body, {String sender = ''}) {
    // Step 1: Check if this is a financial SMS worth parsing
    if (!_isFinancialSms(body, sender)) {
      return ParsedSms.empty();
    }

    // Step 2: Skip non-transaction SMS (OTP, promotional, reminders)
    if (shouldSkipSms(body)) {
      return ParsedSms.empty();
    }

    // Step 3: Extract all data
    final isOtp = _isOtpMessage(body);
    final amount = extractAmount(body);
    
    if (amount == 0.0) {
      return ParsedSms.empty();
    }

    final type = _determineType(body);
    final merchant = extractMerchant(body, isOtp: isOtp);
    final bank = BankPatterns.identifyBank(sender);
    final accountNumber = AccountPatterns.extractAccountNumber(body);
    final cardNumber = AccountPatterns.extractCardNumber(body);
    final balance = BalancePatterns.extractBalance(body);
    final upiRef = ReferencePatterns.extractUpiReference(body);
    final txnId = ReferencePatterns.extractTransactionId(body);
    final date = DatePatterns.extractDate(body);

    return ParsedSms(
      amount: amount,
      merchant: merchant,
      type: type,
      isOtp: isOtp,
      parseSuccess: true,
      bank: bank,
      accountNumber: accountNumber,
      cardNumber: cardNumber,
      balance: balance,
      referenceId: upiRef ?? txnId,
      transactionDate: date,
    );
  }

  /// Check if sender is from a financial institution
  static bool _isFinancialSms(String body, String sender) {
    // If sender matches known bank pattern
    if (sender.isNotEmpty && BankPatterns.isFinancialSender(sender)) {
      return true;
    }
    
    // Fallback: Check if body contains financial keywords
    final bodyLower = body.toLowerCase();
    final financialKeywords = [
      'debited', 'credited', 'withdrawn', 'deposited',
      'a/c', 'account', 'balance', 'txn', 'upi', 'neft', 'imps',
      'rs.', 'inr', 'rs ', 'rupees',
    ];
    
    return financialKeywords.any((kw) => bodyLower.contains(kw));
  }

  /// Check if this is an OTP message
  static bool _isOtpMessage(String body) {
    final bodyLower = body.toLowerCase();
    return TransactionKeywords.otpKeywords.any((kw) => bodyLower.contains(kw));
  }

  /// Check if SMS should be skipped (not a transaction)
  static bool shouldSkipSms(String body) {
    final bodyLower = body.toLowerCase();
    
    // Skip if contains promotional/reminder keywords
    for (var keyword in TransactionKeywords.skipKeywords) {
      if (bodyLower.contains(keyword)) {
        return true;
      }
    }
    
    // NOTE: We do NOT skip OTP messages anymore!
    // OTP messages often contain merchant names (e.g., "OTP for Rs 299 at Swiggy")
    // which are needed for the OTP-transaction merging logic in sms_service.dart
    
    return false;
  }

  /// Extract amount from SMS body
  static double extractAmount(String body) {
    return AmountPatterns.extract(body) ?? 0.0;
  }

  /// Extract merchant name from SMS body
  static String extractMerchant(String body, {bool isOtp = false}) {
    final bodyUpper = body.toUpperCase();
    
    // Special case: ATM withdrawal
    if (bodyUpper.contains('WITHDRAWN') || bodyUpper.contains('ATM')) {
      return 'ATM';
    }
    
    // Special case: IMPS transfer (debit)
    if (bodyUpper.contains('IMPS') && bodyUpper.contains('SENT') && !bodyUpper.contains('CR-')) {
      return 'IMPS Transfer';
    }
    
    // Special case: NEFT transfer
    if (bodyUpper.contains('NEFT') && !bodyUpper.contains('CR-')) {
      return 'NEFT Transfer';
    }
    
    // Special case: UPI transfer without merchant
    if (bodyUpper.contains('UPI') && (bodyUpper.contains('SENT') || bodyUpper.contains('PAID'))) {
      // Try to extract VPA
      final vpaMatch = RegExp(r'(?:to|vpa)[\s.:]*(\S+@\S+)', caseSensitive: false).firstMatch(body);
      if (vpaMatch != null) {
        return _cleanVpaMerchant(vpaMatch.group(1)!);
      }
    }

    final patterns = isOtp
        ? [
            // OTP patterns - merchant usually after "at"
            RegExp(r'at\s+([A-Za-z][A-Za-z0-9\s]+?)\s+on', caseSensitive: false),
            RegExp(r'for\s+txn\s+of\s+(?:Rs\.?|INR)\s*[\d,.]+\s+at\s+([^.]+)', caseSensitive: false),
            RegExp(r'transaction\s+at\s+([A-Za-z][A-Za-z0-9\s]+?)\s+(?:of|for)', caseSensitive: false),
          ]
        : [
            // UPI Mandate pattern: To Google Play, To Netflix etc
            RegExp(r'UPI\s+Mandate.*?To\s+([A-Za-z][A-Za-z0-9\s]+?)\s+\d', caseSensitive: false),
            // "towards COMPANY" pattern (insurance, clearing corp etc)
            RegExp(r'towards\s+([A-Za-z][A-Za-z\s]+?)(?:\s+UMRN|\s*$)', caseSensitive: false),
            // NEFT/IMPS credit pattern: NEFT Cr-BANKCODE-MERCHANT-RECIPIENT
            RegExp(r'NEFT\s+Cr-\w+-([^-]+)-', caseSensitive: false),
            RegExp(r'IMPS\s+Cr-\w+-([^-]+)-', caseSensitive: false),
            // ACH pattern: ACH D- MERCHANT-
            RegExp(r'ACH\s+D-\s*([^-]+)-', caseSensitive: false),
            // UPI VPA pattern: from/to VPA xxx@bank
            RegExp(r'(?:from|to)\s+VPA\s+(\S+@\S+)', caseSensitive: false),
            // UPI pattern: from/to NAME@bank
            RegExp(r'(?:from|to)\s+(\S+@\S+)', caseSensitive: false),
            // "At MERCHANT On" pattern (card transactions)
            RegExp(r'\bAt\s+([A-Za-z0-9][A-Za-z0-9\s&]+?)\s+On\s+\d', caseSensitive: false),
            // "paid to MERCHANT" or "sent to MERCHANT"
            RegExp(r'(?:paid|sent)\s+to\s+([A-Za-z][A-Za-z0-9\s]+?)(?:\s+on|\s+via|\s*\.)', caseSensitive: false),
            // "debited for MERCHANT"
            RegExp(r'debited\s+for\s+([A-Za-z][A-Za-z0-9\s]+?)(?:\s+on|\s*\.)', caseSensitive: false),
            // Regular transaction patterns
            RegExp(r'(?:at|to)\s+([^.]*?)\s+(?:on|for)', caseSensitive: false),
            // "for MERCHANT." pattern
            RegExp(r'for\s+([A-Za-z][^.]*?)\.', caseSensitive: false),
            // "Info: MERCHANT" pattern
            RegExp(r'Info:\s*([A-Za-z][A-Za-z0-9\s]+)', caseSensitive: false),
          ];

    for (var reg in patterns) {
      final match = reg.firstMatch(body);
      if (match != null) {
        var merchant = match.group(1)!.trim();
        merchant = _cleanMerchantName(merchant);
        if (merchant.isNotEmpty && merchant.length > 1) {
          return merchant;
        }
      }
    }
    return 'Unknown';
  }

  /// Clean up merchant name
  static String _cleanMerchantName(String merchant) {
    return merchant
        .replaceAll(RegExp(r'\s+L$', caseSensitive: false), '') // Remove trailing "L" from "LTD"
        .replaceAll(RegExp(r'\s+PVT$', caseSensitive: false), '') // Remove PVT
        .replaceAll(RegExp(r'\s+PRIVATE$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+LIMITED$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+LTD$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+INC$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\*\#]+'), '') // Remove special chars
        .trim();
  }

  /// Clean VPA to get merchant name
  static String _cleanVpaMerchant(String vpa) {
    // Extract name part before @
    final parts = vpa.split('@');
    if (parts.isEmpty) return vpa;
    
    var name = parts[0];
    // Remove common prefixes
    name = name.replaceAll(RegExp(r'^pay\.', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'^upi\.', caseSensitive: false), '');
    
    // Capitalize first letter
    if (name.isNotEmpty) {
      name = name[0].toUpperCase() + name.substring(1);
    }
    
    return name;
  }

  /// Determine if transaction is credit or debit
  static TransactionType _determineType(String body) {
    final bodyLower = body.toLowerCase();
    
    // Check credit keywords first
    for (var keyword in TransactionKeywords.creditKeywords) {
      if (bodyLower.contains(keyword)) {
        return TransactionType.credit;
      }
    }
    
    // Default to debit
    return TransactionType.debit;
  }

  /// Guess category from merchant name
  static String guessCategory(String merchant) {
    return MerchantCategories.getCategory(merchant);
  }
}

/// Result of parsing an SMS
class ParsedSms {
  final double amount;
  final String merchant;
  final TransactionType type;
  final bool isOtp;
  final bool parseSuccess;
  
  // Enhanced fields from Mezo analysis
  final String? bank;
  final String? accountNumber;
  final String? cardNumber;
  final double? balance;
  final String? referenceId;
  final String? transactionDate;

  ParsedSms({
    required this.amount,
    required this.merchant,
    required this.type,
    required this.isOtp,
    required this.parseSuccess,
    this.bank,
    this.accountNumber,
    this.cardNumber,
    this.balance,
    this.referenceId,
    this.transactionDate,
  });

  /// Empty/failed parse result
  factory ParsedSms.empty() {
    return ParsedSms(
      amount: 0,
      merchant: 'Unknown',
      type: TransactionType.debit,
      isOtp: false,
      parseSuccess: false,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('ParsedSms(');
    buffer.write('amount: $amount, merchant: $merchant, type: ${type.name}');
    if (bank != null) buffer.write(', bank: $bank');
    if (accountNumber != null) buffer.write(', account: $accountNumber');
    if (balance != null) buffer.write(', balance: $balance');
    if (referenceId != null) buffer.write(', ref: $referenceId');
    buffer.write(', success: $parseSuccess)');
    return buffer.toString();
  }
  
  /// Convert to map for debugging/logging
  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'merchant': merchant,
      'type': type.name,
      'isOtp': isOtp,
      'parseSuccess': parseSuccess,
      if (bank != null) 'bank': bank,
      if (accountNumber != null) 'accountNumber': accountNumber,
      if (cardNumber != null) 'cardNumber': cardNumber,
      if (balance != null) 'balance': balance,
      if (referenceId != null) 'referenceId': referenceId,
      if (transactionDate != null) 'transactionDate': transactionDate,
    };
  }
}
