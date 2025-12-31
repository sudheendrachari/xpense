/// Maps merchants to expense categories
class MerchantCategories {
  // Category definitions with their merchant keywords
  static const Map<String, List<String>> _categoryKeywords = {
    'Food': [
      'swiggy',
      'zomato',
      'starbucks',
      'dominos',
      'pizza',
      'burger',
      'kfc',
      'mcdonalds',
      'restaurant',
      'cafe',
      'food',
      'eat',
      'kitchen',
      'biryani',
      'chai',
      'coffee',
      'bakery',
      'ice cream',
      'bundl', // Swiggy's merchant code
    ],
    'Investments': [
      'zerodha',
      'groww',
      'upstox',
      'kuvera',
      'coin',
      'mutual fund',
      'mf',
      'clearing corp',
      'nsdl',
      'cdsl',
      'demat',
      'stock',
      'trading',
    ],
    'Shopping': [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'nykaa',
      'meesho',
      'snapdeal',
      'decathlon',
      'uniqlo',
      'h&m',
      'zara',
      'ikea',
      'croma',
      'reliance digital',
      'vijay sales',
    ],
    'Entertainment': [
      'netflix',
      'hotstar',
      'prime video',
      'spotify',
      'youtube',
      'google play',
      'apple',
      'movie',
      'cinema',
      'pvr',
      'inox',
      'bookmyshow',
      'game',
      'playstation',
      'xbox',
    ],
    'Travel': [
      'uber',
      'ola',
      'rapido',
      'metro',
      'bmtc',
      'bus',
      'train',
      'irctc',
      'flight',
      'makemytrip',
      'goibibo',
      'yatra',
      'cleartrip',
      'hotel',
      'oyo',
      'airbnb',
      'fuel',
      'petrol',
      'diesel',
      'fastag',
      'toll',
      'parking',
    ],
    'Bills': [
      'electricity',
      'bescom',
      'water',
      'gas',
      'broadband',
      'internet',
      'act fibernet',
      'act internet',
      'jio',
      'airtel',
      'vi ',
      'vodafone',
      'bsnl',
      'phone',
      'mobile',
      'recharge',
      'rent',
      'maintenance',
      'society',
      'insurance',
      'hdfc life',
      'lic',
      'icici prudential',
      'sbi life',
    ],
    'Health': [
      'pharmacy',
      'apollo',
      'medplus',
      'netmeds',
      'pharmeasy',
      '1mg',
      'hospital',
      'clinic',
      'doctor',
      'medical',
      'diagnostic',
      'lab',
      'health',
      'gym',
      'fitness',
      'cult',
    ],
    'Transfer': [
      'imps',
      'neft',
      'rtgs',
      'upi',
      'transfer',
    ],
    'ATM': [
      'atm',
      'withdrawal',
      'cash',
    ],
    'Income': [
      'salary',
      'credited',
      'refund',
      'cashback',
    ],
  };

  /// Get category for a merchant name
  static String getCategory(String merchant) {
    final m = merchant.toLowerCase();
    
    for (var entry in _categoryKeywords.entries) {
      final category = entry.key;
      final keywords = entry.value;
      
      for (var keyword in keywords) {
        if (m.contains(keyword)) {
          return category;
        }
      }
    }
    
    return 'Others';
  }

  /// Get all available categories
  static List<String> get allCategories {
    return [..._categoryKeywords.keys, 'Others'];
  }
}

