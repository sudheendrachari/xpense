/// Bank sender patterns and identifiers for Indian banks
/// Extracted from Mezo app reverse engineering analysis
class BankPatterns {
  /// Map of bank names to their SMS sender ID patterns
  /// Indian SMS format: XX-BANKCODE (e.g., VK-HDFCBK)
  static const Map<String, List<String>> bankSenderCodes = {
    'HDFC Bank': ['HDFCBK', 'HDFC', 'HDFCBANK', 'HDFCCC'],
    'State Bank of India': ['SBIBNK', 'SBINB', 'SBIBANK', 'SBICRD', 'SBIINB'],
    'ICICI Bank': ['ICICIB', 'ICICI', 'ICICBK', 'ICICIC'],
    'Axis Bank': ['AXISBK', 'AXIS', 'AXISBNK', 'AXISCC'],
    'Kotak Bank': ['KOTAKB', 'KOTAK', 'KOTAKBK', 'KOTAKM'],
    'IDFC First': ['IDFCFB', 'IDFCBK', 'IDFCFIRST'],
    'Yes Bank': ['YESBK', 'YESBNK', 'YESBANK'],
    'IndusInd Bank': ['INDUSB', 'INDBNK', 'INDUSIND'],
    'Punjab National Bank': ['PNBSMS', 'PNBANK'],
    'Bank of Baroda': ['BOBRDA', 'BARODB', 'BOBSMS'],
    'Canara Bank': ['CANBNK', 'CANARA', 'CANARABNK'],
    'Federal Bank': ['FEDBK', 'FEDBNK', 'FEDERAL'],
    'IDBI Bank': ['IDBIBK', 'IDBIBNK'],
    'RBL Bank': ['RBLBNK', 'RATNAKAR'],
    'Standard Chartered': ['SCBANK', 'SCBNK', 'STCHART'],
    'Citibank': ['CITIBK', 'CITIBNK', 'CITBANK'],
    'American Express': ['AMEXIN', 'AMEXBK'],
    
    // Payment Apps
    'Paytm': ['PAYTMB', 'PAYTM', 'PYTMWL'],
    'Google Pay': ['GPAY', 'GOOGLEPAY', 'GPAYUPI'],
    'PhonePe': ['PHONEPE', 'PHNEPE', 'PHNPE'],
    'Amazon Pay': ['AMZNPAY', 'AMAZON'],
    'CRED': ['CRED', 'CREDCLUB'],
    'Slice': ['SLICE', 'SLICEIT'],
    'Fi Money': ['FIMONEY', 'FIBANK'],
    'Jupiter': ['JUPITER', 'JUPBNK'],
  };

  /// Identify bank from sender ID
  static String? identifyBank(String sender) {
    final senderUpper = sender.toUpperCase();
    
    // Remove common prefixes (XX-)
    final cleanSender = senderUpper.replaceFirst(RegExp(r'^[A-Z]{2}-'), '');
    
    for (var entry in bankSenderCodes.entries) {
      for (var code in entry.value) {
        if (cleanSender.contains(code)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Check if sender is from a financial institution
  static bool isFinancialSender(String sender) {
    final senderUpper = sender.toUpperCase();
    
    // Indian transactional SMS format: XX-XXXXXX (with hyphen)
    if (!senderUpper.contains('-')) {
      return false;
    }
    
    // Check if it matches any known bank pattern
    if (identifyBank(sender) != null) {
      return true;
    }
    
    // Common bank suffixes
    final bankSuffixes = ['BK', 'BNK', 'BANK', 'INB', 'CC'];
    final cleanSender = senderUpper.replaceFirst(RegExp(r'^[A-Z]{2}-'), '');
    
    for (var suffix in bankSuffixes) {
      if (cleanSender.endsWith(suffix)) {
        return true;
      }
    }
    
    return false;
  }
}

/// Common keywords for transaction type detection
class TransactionKeywords {
  /// Keywords indicating money was debited
  static const List<String> debitKeywords = [
    'debited',
    'debit',
    'spent',
    'paid',
    'withdrawn',
    'purchase',
    'payment',
    'transferred',
    'sent',
    'deducted',
    'used at',
    'txn of rs',
    'dr-',
    'debit alert',
  ];

  /// Keywords indicating money was credited
  static const List<String> creditKeywords = [
    'credited',
    'credit',
    'received',
    'deposited',
    'refund',
    'cashback',
    'reversed',
    'cr-',
    'credit alert',
    'added to',
  ];

  /// Keywords indicating OTP message (skip these)
  static const List<String> otpKeywords = [
    'otp',
    'one time password',
    'verification code',
    'security code',
    'pin is',
    'cvv',
  ];

  /// Keywords indicating promotional/reminder SMS (skip these)
  static const List<String> skipKeywords = [
    'statement',
    'due date',
    'min due',
    'minimum due',
    'e-mandate',
    'will be deducted',
    'emi reminder',
    'payment reminder',
    'bill generated',
    'reward points',
    'earn upto',
    'offer',
    'discount',
    'cashback offer',
    'apply now',
    'pre-approved',
    'limit increased',
  ];
}

/// Amount extraction patterns
class AmountPatterns {
  /// Primary amount patterns (Indian format)
  static final List<RegExp> patterns = [
    // Rs. 1,50,000.00 or INR 1,50,000.00 (Indian lakhs format with comma)
    RegExp(r'(?:Rs\.?|INR\.?)\s*(\d{1,2},\d{2},\d{3}(?:\.\d{1,2})?)', caseSensitive: false),
    // Rs. 10,000.00 or Rs. 1,500.00 (thousands/hundreds with comma)
    RegExp(r'(?:Rs\.?|INR\.?)\s*(\d{1,3},\d{3}(?:\.\d{1,2})?)', caseSensitive: false),
    // Rs. 1500.00 or INR 1500 (without comma)
    RegExp(r'(?:Rs\.?|INR\.?)\s*(\d+(?:\.\d{1,2})?)', caseSensitive: false),
    // "of Rs 1,500" or "of 1,500" pattern often seen in OTP
    RegExp(r'of\s+(?:Rs\.?\s*)?(\d[\d,]*(?:\.\d{1,2})?)', caseSensitive: false),
    // Amount followed by /- (Indian notation)
    RegExp(r'(\d[\d,]*(?:\.\d{1,2})?)\s*/-', caseSensitive: false),
  ];

  /// Extract amount from text - finds the FIRST occurrence by position
  static double? extract(String text) {
    int bestStart = -1;
    double? bestAmount;
    
    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final amountStr = match.group(1)!.replaceAll(',', '');
        final amount = double.tryParse(amountStr);
        if (amount != null && amount > 0) {
          // Return this match if it's the first one (earliest position)
          if (bestStart == -1 || match.start < bestStart) {
            bestStart = match.start;
            bestAmount = amount;
          }
        }
      }
    }
    return bestAmount;
  }
}

/// Account/Card number extraction patterns
class AccountPatterns {
  /// Extract masked account number (e.g., XX1234, ****5678)
  static String? extractAccountNumber(String text) {
    final patterns = [
      // A/c XX1234 or A/c ****5678
      RegExp(r'(?:a\/c|ac|account|acct)[\s.:]*(?:no\.?|number)?[\s.:]*([X*x\d]{4,})', caseSensitive: false),
      // Account ending with 1234
      RegExp(r'(?:ending|linked)\s*(?:with|in)?\s*(\d{4})', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Extract card last 4 digits
  static String? extractCardNumber(String text) {
    final patterns = [
      // Card XX1234 or card ending 1234
      RegExp(r'(?:card|cc)[\s.:]*(?:no\.?|ending|xx)?[\s.:]*(\d{4})', caseSensitive: false),
      // Credit/Debit Card ending 1234
      RegExp(r'(?:credit|debit)\s*card.*?(\d{4})', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
}

/// Balance extraction patterns
class BalancePatterns {
  /// Extract available balance
  static double? extractBalance(String text) {
    final patterns = [
      // Avl Bal: Rs 5,00,000.00 or Rs 10,000.00 (with comma - Indian format)
      RegExp(r'(?:avl?\.?\s*bal\.?|available\s*balance|bal\.?)[\s.:]*(?:rs\.?|inr\.?)?\s*(\d[\d,]*(?:\.\d{1,2})?)', caseSensitive: false),
      // Balance: Rs 5,000 (generic balance keyword)
      RegExp(r'balance[\s.:]*(?:rs\.?|inr\.?)?\s*(\d[\d,]*(?:\.\d{1,2})?)', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final balanceStr = match.group(1)!.replaceAll(',', '');
        return double.tryParse(balanceStr);
      }
    }
    return null;
  }
}

/// UPI/Transaction reference extraction
class ReferencePatterns {
  /// Extract UPI reference number (12 digits)
  static String? extractUpiReference(String text) {
    final pattern = RegExp(r'(?:upi\s*(?:ref|reference|txn|id)?[\s.:]*|ref[\s.:]*(?:no\.?)?[\s.:]*)(\d{12})', caseSensitive: false);
    final match = pattern.firstMatch(text);
    return match?.group(1);
  }

  /// Extract general transaction ID
  static String? extractTransactionId(String text) {
    final patterns = [
      // Txn ID: ABC123456
      RegExp(r'(?:txn|transaction|ref|reference)[\s.:]*(?:no\.?|id)?[\s.:]*([A-Za-z0-9]{6,20})', caseSensitive: false),
      // IMPS Ref: 123456789012
      RegExp(r'(?:imps|neft|rtgs)\s*(?:ref)?[\s.:]*(\d{10,16})', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }
}

/// Date/Time extraction patterns
class DatePatterns {
  /// Extract date from SMS
  static String? extractDate(String text) {
    final patterns = [
      // DD-MM-YYYY or DD/MM/YYYY
      RegExp(r'(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})'),
      // DD-Mon-YYYY (e.g., 15-Jan-2024)
      RegExp(r'(\d{1,2}[-\s](?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[-\s]\d{2,4})', caseSensitive: false),
    ];

    for (var pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  /// Extract time from SMS
  static String? extractTime(String text) {
    final pattern = RegExp(r'(\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?)', caseSensitive: false);
    final match = pattern.firstMatch(text);
    return match?.group(1);
  }
}

