import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:xpense/models/transaction.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'finance_tracker.db');
    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    // Transactions table (parsed transactions)
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        amount REAL,
        merchant TEXT,
        date TEXT,
        category TEXT,
        type TEXT,
        body TEXT,
        bankName TEXT,
        is_ignored INTEGER DEFAULT 0,
        is_investment INTEGER DEFAULT 0,
        manual_category TEXT
      )
    ''');
    
    // Raw SMS table (bank SMS only)
    await db.execute('''
      CREATE TABLE raw_sms (
        id TEXT PRIMARY KEY,
        sender TEXT,
        body TEXT,
        date TEXT,
        bank_name TEXT
      )
    ''');
    
    // Sync info table (key-value store for sync metadata)
    await db.execute('''
      CREATE TABLE sync_info (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    
    // Indexes for faster queries
    await db.execute('CREATE INDEX idx_transactions_date ON transactions (date)');
    await db.execute('CREATE INDEX idx_raw_sms_date ON raw_sms (date)');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration to version 4: Add raw_sms and sync_info tables
    if (oldVersion < 4) {
      // Drop and recreate all tables for clean slate
      await db.execute('DROP TABLE IF EXISTS transactions');
      await db.execute('DROP TABLE IF EXISTS raw_sms');
      await db.execute('DROP TABLE IF EXISTS sync_info');
      await _onCreate(db, newVersion);
      debugPrint('DATABASE: Migrated to version 4 - added raw_sms and sync_info tables');
    }
    
    // Migration to version 5: Add ignore/investment/manual flags
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN is_ignored INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE transactions ADD COLUMN is_investment INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE transactions ADD COLUMN manual_category TEXT');
        debugPrint('DATABASE: Migrated to version 5 - added manual override columns');
      } catch (e) {
        debugPrint('DATABASE: Error during migration to v5: $e');
        // Fallback: recreate table if alter fails
        await db.execute('DROP TABLE IF EXISTS transactions');
        await _onCreate(db, newVersion);
      }
    }
  }

  // ============================================================================
  // SYNC INFO METHODS
  // ============================================================================

  /// Check if initial sync has been completed
  Future<bool> isInitialSyncCompleted() async {
    final db = await database;
    final result = await db.query(
      'sync_info',
      where: 'key = ?',
      whereArgs: ['initial_sync_completed'],
    );
    return result.isNotEmpty && result.first['value'] == 'true';
  }

  /// Mark initial sync as completed
  Future<void> setInitialSyncCompleted() async {
    final db = await database;
    await db.insert(
      'sync_info',
      {'key': 'initial_sync_completed', 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTimestamp() async {
    final db = await database;
    final result = await db.query(
      'sync_info',
      where: 'key = ?',
      whereArgs: ['last_sync_timestamp'],
    );
    if (result.isEmpty) return null;
    return DateTime.parse(result.first['value'] as String);
  }

  /// Set last sync timestamp
  Future<void> setLastSyncTimestamp(DateTime timestamp) async {
    final db = await database;
    await db.insert(
      'sync_info',
      {'key': 'last_sync_timestamp', 'value': timestamp.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ============================================================================
  // RAW SMS METHODS
  // ============================================================================

  /// Insert raw bank SMS in batch
  Future<int> insertRawSmsBatch(List<Map<String, dynamic>> messages) async {
    final db = await database;
    final batch = db.batch();
    
    for (var msg in messages) {
      batch.insert(
        'raw_sms',
        msg,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    
    await batch.commit(noResult: true);
    return messages.length;
  }

  /// Get count of raw SMS
  Future<int> getRawSmsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM raw_sms');
    return result.first['count'] as int;
  }

  /// Get all raw SMS (for parsing)
  Future<List<Map<String, dynamic>>> getAllRawSms() async {
    final db = await database;
    return await db.query('raw_sms', orderBy: 'date DESC');
  }

  /// Get raw SMS in date range (for delta sync parsing)
  Future<List<Map<String, dynamic>>> getRawSmsInRange(DateTime start, DateTime end) async {
    final db = await database;
    return await db.query(
      'raw_sms',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
  }

  /// Get latest raw SMS date
  Future<DateTime?> getLatestRawSmsDate() async {
    final db = await database;
    final result = await db.query(
      'raw_sms',
      columns: ['date'],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    final dateStr = result.first['date'] as String?;
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.parse(dateStr);
  }

  /// Check if raw SMS exists
  Future<bool> rawSmsExists(String smsId) async {
    final db = await database;
    final result = await db.query(
      'raw_sms',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [smsId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ============================================================================
  // TRANSACTION METHODS
  // ============================================================================

  Future<void> insertTransactions(List<Transaction> transactions) async {
    final db = await database;
    final batch = db.batch();
    for (var tx in transactions) {
      batch.insert(
        'transactions',
        tx.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore, // Don't overwrite existing
      );
    }
    await batch.commit(noResult: true);
  }

  /// Insert or update a transaction immediately (for incremental saving and AI refinements)
  /// Uses replace to allow updating existing transactions (e.g., when AI refines merchant name or manual overrides)
  Future<void> insertTransaction(Transaction transaction) async {
    final db = await database;
    await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // Replace existing to allow AI refinements or manual overrides to update
    );
  }

  /// Update only manual override fields for a transaction
  Future<void> updateTransactionManualOverrides(String id, {bool? isIgnored, bool? isInvestment, String? manualCategory}) async {
    final db = await database;
    final Map<String, dynamic> updates = {};
    if (isIgnored != null) updates['is_ignored'] = isIgnored ? 1 : 0;
    if (isInvestment != null) updates['is_investment'] = isInvestment ? 1 : 0;
    if (manualCategory != null) updates['manual_category'] = manualCategory;
    
    if (updates.isNotEmpty) {
      await db.update(
        'transactions',
        updates,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// Check if a transaction ID already exists in the database
  Future<bool> transactionExists(String transactionId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<Transaction>> getTransactionsInRange(DateTime start, DateTime end) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );

    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  Future<DateTime?> getLatestTransactionDate() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      columns: ['date'],
      orderBy: 'date DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return DateTime.parse(maps[0]['date']);
  }
  
  /// Clear all data and reset sync state (for "Clear Cache" feature)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('raw_sms');
    await db.delete('sync_info'); // Resets initial_sync_completed flag
    debugPrint('DATABASE: Cleared all tables (transactions, raw_sms, sync_info)');
  }

  /// DEBUG: Get all transactions in database (no date filter)
  Future<List<Transaction>> getAllTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'date DESC',
    );

    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  /// DEBUG: Get database statistics
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final db = await database;
    
    // Total count
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM transactions');
    final totalCount = countResult.first['count'] as int;
    
    // Date range
    final dateRangeResult = await db.rawQuery('''
      SELECT 
        MIN(date) as earliest,
        MAX(date) as latest
      FROM transactions
    ''');
    
    DateTime? earliestDate;
    DateTime? latestDate;
    if (dateRangeResult.first['earliest'] != null) {
      earliestDate = DateTime.parse(dateRangeResult.first['earliest'] as String);
    }
    if (dateRangeResult.first['latest'] != null) {
      latestDate = DateTime.parse(dateRangeResult.first['latest'] as String);
    }
    
    // Database path
    final path = join(await getDatabasesPath(), 'finance_tracker.db');
    
    return {
      'totalCount': totalCount,
      'earliestDate': earliestDate,
      'latestDate': latestDate,
      'databasePath': path,
    };
  }

  /// DEBUG: Print all transactions to console
  Future<void> debugPrintAllTransactions() async {
    final transactions = await getAllTransactions();
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('DATABASE DEBUG: Total transactions: ${transactions.length}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    if (transactions.isEmpty) {
      debugPrint('Database is empty.');
      return;
    }
    
    // Group by date
    final Map<String, List<Transaction>> byDate = {};
    for (var tx in transactions) {
      final dateKey = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}-${tx.date.day.toString().padLeft(2, '0')}';
      byDate.putIfAbsent(dateKey, () => []).add(tx);
    }
    
    // Print summary
    debugPrint('\n📊 SUMMARY BY DATE:');
    final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    for (var dateKey in sortedDates) {
      final txs = byDate[dateKey]!;
      final date = DateTime.parse('$dateKey 00:00:00');
      debugPrint('  ${date.toString().substring(0, 10)}: ${txs.length} transactions');
    }
    
    debugPrint('\n📋 ALL TRANSACTIONS (first 20):');
    for (var i = 0; i < transactions.length && i < 20; i++) {
      final tx = transactions[i];
      debugPrint('  ${i + 1}. [${tx.date.toString().substring(0, 10)}] ${tx.type.name.toUpperCase()} ₹${tx.amount.toStringAsFixed(2)} - ${tx.merchant} (${tx.bankName})');
    }
    
    if (transactions.length > 20) {
      debugPrint('  ... and ${transactions.length - 20} more');
    }
    
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
}
