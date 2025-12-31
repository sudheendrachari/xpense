import 'package:xpense/utils/currency_formatter.dart';
import 'package:intl/intl.dart';

enum TransactionType { debit, credit }

class Transaction {
  final String id;
  final double amount;
  final String merchant;
  final DateTime date;
  final String category;
  final TransactionType type;
  final String body;
  final String bankName;
  final bool isIgnored;
  final bool isInvestment;
  final String? manualCategory;

  Transaction({
    required this.id,
    required this.amount,
    required this.merchant,
    required this.date,
    required this.category,
    required this.type,
    required this.body,
    required this.bankName,
    this.isIgnored = false,
    this.isInvestment = false,
    this.manualCategory,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'merchant': merchant,
      'date': date.toIso8601String(),
      'category': category,
      'type': type.name,
      'body': body,
      'bankName': bankName,
      'is_ignored': isIgnored ? 1 : 0,
      'is_investment': isInvestment ? 1 : 0,
      'manual_category': manualCategory,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      amount: (map['amount'] as num).toDouble(),
      merchant: map['merchant'],
      date: DateTime.parse(map['date']),
      category: map['category'],
      type: TransactionType.values.firstWhere((e) => e.name == map['type']),
      body: map['body'],
      bankName: map['bankName'],
      isIgnored: (map['is_ignored'] ?? 0) == 1,
      isInvestment: (map['is_investment'] ?? 0) == 1,
      manualCategory: map['manual_category'],
    );
  }

  /// Helper to create a copy of transaction with some fields updated
  Transaction copyWith({
    bool? isIgnored,
    bool? isInvestment,
    String? manualCategory,
  }) {
    return Transaction(
      id: id,
      amount: amount,
      merchant: merchant,
      date: date,
      category: category,
      type: type,
      body: body,
      bankName: bankName,
      isIgnored: isIgnored ?? this.isIgnored,
      isInvestment: isInvestment ?? this.isInvestment,
      manualCategory: manualCategory ?? this.manualCategory,
    );
  }

  /// Get the effective category (manual if set, else automatic)
  String get effectiveCategory => manualCategory ?? category;

  /// Format amount in Indian numbering: ₹1,23,456
  String get formattedAmount {
    return IndianCurrencyFormatter.format(amount);
  }

  String get formattedDate {
    return DateFormat('MMM d, h:mm a').format(date);
  }
}
