import 'package:intl/intl.dart';

/// Indian currency formatter using intl package with hi_IN locale
class IndianCurrencyFormatter {
  static final _formatter = NumberFormat.currency(
    locale: 'hi_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  
  static final _formatterWithDecimals = NumberFormat.currency(
    locale: 'hi_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// Format amount in Indian numbering system: ₹1,23,456
  static String format(double amount, {int decimalDigits = 0}) {
    return decimalDigits > 0 
        ? _formatterWithDecimals.format(amount)
        : _formatter.format(amount);
  }
}
