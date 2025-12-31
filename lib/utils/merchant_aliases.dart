/// Merchant name aliases mapping
/// Maps common variations to clean merchant names
class MerchantAliases {
  static final Map<String, String> _aliases = {
    // Food & Delivery
    'SWIGGY': 'Swiggy',
    'SWIGGYINSTAMART': 'Swiggy Instamart',
    'BUNDL TECHN': 'Swiggy',
    'BUNDL': 'Swiggy',
    'TOWER 5IAND5J BUNDLTECHNO': 'Swiggy',
    'ZOMATO': 'Zomato',
    'ZOMATOGOLD': 'Zomato Gold',
    'UBEREATS': 'Uber Eats',
    'DOMINOS': 'Domino\'s',
    'PIZZAHUT': 'Pizza Hut',
    'MCDONALDS': 'McDonald\'s',
    'KFC': 'KFC',
    'STARBUCKS': 'Starbucks',
    'CAFE': 'Cafe',
    
    // Shopping
    'AMAZON': 'Amazon',
    'AMAZONIN': 'Amazon',
    'FLIPKART': 'Flipkart',
    'MYNTRA': 'Myntra',
    'NYKA': 'Nykaa',
    'NYKAAMAN': 'Nykaa Man',
    'UNIQLO': 'Uniqlo',
    'AJIO': 'Ajio',
    'MEESHO': 'Meesho',
    
    // Travel
    'UBER': 'Uber',
    'OLA': 'Ola',
    'RAPIDO': 'Rapido',
    'IRCTC': 'IRCTC',
    'MAKEMYTRIP': 'MakeMyTrip',
    'GOIBIBO': 'Goibibo',
    'YATRA': 'Yatra',
    
    // Entertainment
    'NETFLIX': 'Netflix',
    'PRIMEVIDEO': 'Prime Video',
    'DISNEYPLUS': 'Disney+',
    'HOTSTAR': 'Disney+ Hotstar',
    'SPOTIFY': 'Spotify',
    'YOUTUBEPREMIUM': 'YouTube Premium',
    
    // Bills & Utilities - ISPs
    'AIRTEL': 'Airtel',
    'AIRTEL BROADBAND': 'Airtel Broadband',
    'JIO': 'Jio',
    'JIOFIBER': 'JioFiber',
    'VI': 'Vi',
    'ATRIA CONVERGENCE TECHNOLOGIES PRIVATE LIMITED': 'ACT Internet',
    'ATRIA CONVERGENCE': 'ACT Internet',
    'ACT FIBERNET': 'ACT Internet',
    'HATHWAY': 'Hathway',
    'TIKONA': 'Tikona',
    'YOU BROADBAND': 'YOU Broadband',
    'SPECTRA': 'Spectra',
    'EXCITEL': 'Excitel',
    'BSNL': 'BSNL',
    'MTNL': 'MTNL',
    
    // Bills & Utilities - Electricity
    'BSES': 'BSES',
    'TATAPOWER': 'Tata Power',
    'ADANI': 'Adani Electricity',
    'BESCOM': 'BESCOM',
    'TORRENT POWER': 'Torrent Power',
    'MSEDCL': 'MSEDCL',
    
    // Insurance
    'HDFC STANDARD LIFE INSURANCE': 'HDFC Life Insurance',
    'HDFC LIFE': 'HDFC Life Insurance',
    'ICICI PRUDENTIAL': 'ICICI Prudential',
    'ICICI PRU': 'ICICI Prudential',
    'LIC': 'LIC',
    'LIC OF INDIA': 'LIC',
    'SBI LIFE': 'SBI Life Insurance',
    'MAX LIFE': 'Max Life Insurance',
    'BAJAJ ALLIANZ': 'Bajaj Allianz',
    'TATA AIA': 'Tata AIA',
    'BIRLA SUN LIFE': 'Aditya Birla Insurance',
    'KOTAK LIFE': 'Kotak Life Insurance',
    'PNB METLIFE': 'PNB MetLife',
    'STAR HEALTH': 'Star Health Insurance',
    'CARE HEALTH': 'Care Health Insurance',
    
    // Trading / Investment - Brokers
    'INDIAN CLEARING CORP': 'Zerodha',
    'INDIAN CLEARING CORPORATION': 'Zerodha',
    'ZERODHA': 'Zerodha',
    'GROWW': 'Groww',
    'UPSTOX': 'Upstox',
    'ANGEL ONE': 'Angel One',
    'ANGEL BROKING': 'Angel One',
    'ICICI DIRECT': 'ICICI Direct',
    'ICICI SECURITIES': 'ICICI Direct',
    'HDFC SECURITIES': 'HDFC Securities',
    'KOTAK SECURITIES': 'Kotak Securities',
    '5PAISA': '5Paisa',
    'MOTILAL OSWAL': 'Motilal Oswal',
    'SHAREKHAN': 'Sharekhan',
    'PAYTM MONEY': 'Paytm Money',
    'KUVERA': 'Kuvera',
    'ET MONEY': 'ET Money',
    'COIN BY ZERODHA': 'Zerodha Coin',
    
    // Salary / Income - Tech Companies
    'LINKEDIN TECHNOLOGY': 'Salary',
    'LINKEDIN': 'Salary',
    
    // Banking & Finance
    'PAYTM': 'Paytm',
    'PHONEPE': 'PhonePe',
    'GOOGLEPAY': 'Google Pay',
    'GPAY': 'Google Pay',
    'AMAZONPAY': 'Amazon Pay',
    'CRED': 'CRED',
    
    // Fuel
    'BPCL': 'BPCL',
    'IOCL': 'Indian Oil',
    'HPCL': 'HPCL',
    'RELIANCE': 'Reliance',
    
    // Grocery
    'BIGBAZAAR': 'Big Bazaar',
    'DMART': 'DMart',
    'RELIANCEFRESH': 'Reliance Fresh',
    'MOREMEGASTORE': 'More',
    
    // Common abbreviations
    'ATM': 'ATM',
    'UPI': 'UPI Payment',
    'NEFT': 'NEFT',
    'IMPS': 'IMPS',
    'RTGS': 'RTGS',
  };

  /// Normalize merchant name using aliases
  /// Returns cleaned merchant name if alias exists, otherwise returns original
  static String normalize(String merchant) {
    if (merchant.isEmpty || merchant == 'Unknown') {
      return merchant;
    }
    
    final upperMerchant = merchant.toUpperCase().trim();
    
    // Direct match
    if (_aliases.containsKey(upperMerchant)) {
      return _aliases[upperMerchant]!;
    }
    
    // Partial match - only for aliases with 4+ characters (avoid "VI", "KFC" etc matching within words)
    for (var entry in _aliases.entries) {
      if (entry.key.length >= 4 && upperMerchant.contains(entry.key)) {
        return entry.value;
      }
    }
    
    // Word boundary match for short aliases (2-3 chars)
    final words = upperMerchant.split(RegExp(r'\s+'));
    for (var word in words) {
      if (_aliases.containsKey(word)) {
        return _aliases[word]!;
      }
    }
    
    // If no match, return original but clean it up
    return _cleanMerchantName(merchant);
  }

  /// Clean merchant name (remove extra spaces, capitalize properly)
  static String _cleanMerchantName(String name) {
    // Remove multiple spaces
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    
    // Capitalize first letter of each word
    final words = name.split(' ');
    final cleaned = words.map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
    
    return cleaned.trim();
  }
}

