# 💰 Xpense - Track Your Money

An **offline-first** personal finance tracker that automatically parses your bank SMS messages. Built for Indian banks. **100% private** — all data stays on your device.

---

## ✨ Features

### 📱 Automatic SMS Parsing
- Scans bank SMS messages and extracts transaction details
- Supports debit, credit, UPI, NEFT, IMPS, ATM withdrawals
- Smart merchant name detection and normalization
- OTP filtering — only real transactions are tracked

### 📊 Insights & Analytics
- **Total Spent** card with date range selection
- **Daily Spending Chart** — visual bar graph of expenses
- **Category Breakdown** — see where your money goes (Food, Shopping, Travel, Bills, etc.)
- Tap any day to jump to those transactions

### 🏦 Multi-Bank Support
- HDFC Bank
- Axis Bank
- More banks can be added via regex patterns

### 🔐 Privacy & Security
- **Biometric Lock** — fingerprint/face unlock
- **Offline-first** — no internet required, no data leaves your device
- All transactions stored locally in SQLite

### 🎯 Smart Features
- **Collapsible Date Headers** — with daily spending totals
- **Transaction Filters** — All / Debit / Credit
- **Pull-to-Refresh** sync
- **Manual Overrides** — mark transactions as ignored, investment, or change category
- **Dark Mode** support

---

## 📸 Screenshots

| Home | Insights | Transaction Details |
|------|----------|---------------------|
| *Coming soon* | *Coming soon* | *Coming soon* |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.10+)
- Android device with SMS permissions
- Bank accounts with HDFC or Axis Bank

### Installation

```bash
# Clone the repository
git clone https://github.com/sudheendrachari/xpense.git
cd xpense

# Install dependencies
flutter pub get

# Run on connected device
flutter run
```

### First Launch
1. Grant SMS permission when prompted
2. App will scan your SMS inbox for bank messages
3. View your transactions on the Home screen

---

## 🛠️ Development

### Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── transaction.dart      # Transaction data model
├── screens/
│   ├── app_shell.dart        # Bottom navigation wrapper
│   ├── dashboard_screen.dart # Home screen
│   ├── insights_screen.dart  # Category breakdown
│   ├── configuration_screen.dart # Settings
│   └── setup_screen.dart     # First-time setup
├── services/
│   ├── sms_service.dart      # SMS parsing logic
│   ├── database_service.dart # SQLite operations
│   └── biometric_service.dart # Fingerprint auth
├── utils/
│   ├── sms_parser.dart       # Regex patterns
│   ├── merchant_aliases.dart # Merchant name mapping
│   ├── merchant_categories.dart # Auto-categorization
│   ├── bank_patterns.dart    # Bank detection
│   └── theme.dart            # App theming
└── widgets/
    ├── transaction_list.dart
    ├── total_spent_card.dart
    ├── day_spending_chart.dart
    └── transaction_detail_sheet.dart
```

### Running Tests

```bash
flutter test
```

### Building Release APK

```bash
flutter build apk --release
```

APK will be at `build/app/outputs/flutter-apk/app-release.apk`

---

## 🔧 Debugging

### View Database Contents

**Option 1: In-App**
- Settings → Database Info → shows stats and ADB command

**Option 2: ADB Command**
```bash
adb exec-out run-as io.github.sudheendrachari.xpense cat databases/finance_tracker.db > ~/Downloads/xpense.db
```
Then open with [DB Browser for SQLite](https://sqlitebrowser.org/)

### Clear App Data
```bash
# Via environment variable
CLEAR_CACHE=true flutter run

# Or via app: Settings → Clear Local Cache
```

### Logs
Transaction parsing logs appear in the debug console with prefixes like:
- `SMS_SERVICE:` — SMS fetching and parsing
- `DATABASE:` — Database operations
- `BIOMETRIC_SERVICE:` — Auth events

---

## 🏗️ Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart) |
| Database | SQLite (`sqflite`) |
| Charts | `fl_chart` |
| SMS Access | `flutter_sms_inbox` |
| Biometrics | `local_auth` |
| Fonts | Source Sans 3 (bundled) |

---

## 🇮🇳 Indian Bank SMS Patterns

The app detects banks via SMS sender IDs:
- `XX-HDFCBK` → HDFC Bank
- `XX-AXISBK` → Axis Bank

Transaction amounts are parsed from formats like:
- `Rs. 1,500.00` / `INR 1500`
- Indian lakh format: `Rs. 1,50,000`

---

## 🔒 Privacy

- **No internet required** — works completely offline
- **No analytics** — zero tracking
- **No cloud sync** — all data stays on your device
- **SMS content never leaves your phone**

---

## 📝 License

MIT License — feel free to use, modify, and distribute.

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Add support for more banks
- Improve merchant detection
- Fix parsing issues
- Enhance UI/UX

---

## 👤 Author

**Sudheendra Chari**
- GitHub: [@sudheendrachari](https://github.com/sudheendrachari)
- Twitter: [@itsmesudheendra](https://twitter.com/itsmesudheendra)

---

<p align="center">
  Made with ❤️ in Bangalore
</p>
