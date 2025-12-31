import 'package:xpense/models/transaction.dart';
import 'package:xpense/utils/bank_patterns.dart';
import 'package:xpense/utils/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bank Pattern Tests', () {
    test('Identifies HDFC Bank from sender', () {
      expect(BankPatterns.identifyBank('VK-HDFCBK'), 'HDFC Bank');
      expect(BankPatterns.identifyBank('BZ-HDFC'), 'HDFC Bank');
    });

    test('Identifies SBI from sender', () {
      expect(BankPatterns.identifyBank('AD-SBIBNK'), 'State Bank of India');
      expect(BankPatterns.identifyBank('JD-SBINB'), 'State Bank of India');
    });

    test('Identifies payment apps', () {
      expect(BankPatterns.identifyBank('JD-PAYTMB'), 'Paytm');
      expect(BankPatterns.identifyBank('VK-GPAY'), 'Google Pay');
      expect(BankPatterns.identifyBank('AD-PHONEPE'), 'PhonePe');
    });

    test('Returns null for unknown sender', () {
      expect(BankPatterns.identifyBank('XX-UNKNOWN'), null);
      expect(BankPatterns.identifyBank('PROMO123'), null);
    });

    test('Detects financial sender correctly', () {
      expect(BankPatterns.isFinancialSender('VK-HDFCBK'), true);
      expect(BankPatterns.isFinancialSender('JD-PAYTMB'), true);
      expect(BankPatterns.isFinancialSender('PROMO123'), false);
      expect(BankPatterns.isFinancialSender('AMAZON'), false);
    });
  });

  group('Amount Extraction Tests', () {
    test('Extracts Rs. format', () {
      expect(SmsParser.extractAmount('Rs.2,500.00 debited'), 2500.0);
      expect(SmsParser.extractAmount('Rs 1500 sent'), 1500.0);
      expect(SmsParser.extractAmount('Rs.99 paid'), 99.0);
    });

    test('Extracts INR format', () {
      expect(SmsParser.extractAmount('INR 10,000.00 credited'), 10000.0);
      expect(SmsParser.extractAmount('INR 500 received'), 500.0);
    });

    test('Handles lakhs format', () {
      expect(SmsParser.extractAmount('Rs.1,50,000.00 transferred'), 150000.0);
      expect(SmsParser.extractAmount('INR 25,00,000 deposited'), 2500000.0);
    });

    test('Returns 0 for no amount', () {
      expect(SmsParser.extractAmount('Your OTP is 123456'), 0.0);
      expect(SmsParser.extractAmount('Hello world'), 0.0);
    });
  });

  group('Transaction Type Detection', () {
    test('Detects debit transactions', () {
      final debitSms = 'Rs.500 debited from your account';
      final result = SmsParser.parse(debitSms, sender: 'VK-HDFCBK');
      expect(result.type, TransactionType.debit);
    });

    test('Detects credit transactions', () {
      final creditSms = 'Rs.10,000 credited to your account';
      final result = SmsParser.parse(creditSms, sender: 'VK-HDFCBK');
      expect(result.type, TransactionType.credit);
    });

    test('Detects refund as credit', () {
      final refundSms = 'Refund of Rs.299 processed to your account';
      final result = SmsParser.parse(refundSms, sender: 'VK-HDFCBK');
      expect(result.type, TransactionType.credit);
    });
  });

  group('SMS Skip Logic', () {
    test('Skips credit card statements', () {
      final sms = 'Credit Card Statement: Total due: Rs.5,000 Min due: Rs.200';
      expect(SmsParser.shouldSkipSms(sms), true);
    });

    test('Skips E-Mandate warnings', () {
      final sms = 'E-Mandate! Rs.89 will be deducted on 20/12/25 for Netflix';
      expect(SmsParser.shouldSkipSms(sms), true);
    });

    test('Skips promotional messages', () {
      final sms = 'Pre-approved loan of Rs.5,00,000. Apply now!';
      expect(SmsParser.shouldSkipSms(sms), true);
    });

    test('Does not skip actual transactions', () {
      final sms = 'Rs.500 debited from A/c XX1234 for Swiggy';
      expect(SmsParser.shouldSkipSms(sms), false);
    });
  });

  group('Full SMS Parsing Tests', () {
    final testCases = [
      {
        'name': 'UPI Mandate (Google Play)',
        'sender': 'VK-HDFCBK',
        'sms': 'UPI Mandate: Sent Rs.89.00 from HDFC Bank A/c 1234 To Google Play 20/12/25 Ref 2001234567890',
        'expectedAmount': 89.0,
        'expectedType': TransactionType.debit,
        'expectedSuccess': true,
      },
      {
        'name': 'E-Mandate Warning (SKIP)',
        'sender': 'VK-HDFCBK',
        'sms': 'E-Mandate! Rs.89.00 will be deducted on 20/12/25 For Google Play mandate',
        'expectedSuccess': false,
      },
      {
        'name': 'Credit Card Statement (SKIP)',
        'sender': 'BZ-HDFCCC',
        'sms': 'HDFC Bank Credit Card XX1234 Statement: Total due: Rs.3,765.00 Min.due: Rs.200.00',
        'expectedSuccess': false,
      },
      {
        'name': 'Card Transaction (Swiggy)',
        'sender': 'JD-HDFCBK',
        'sms': 'Spent Rs.236 On HDFC Bank Card 5467 At BUNDL TECHNOLOGIES PVT On 2025-12-16',
        'expectedAmount': 236.0,
        'expectedType': TransactionType.debit,
        'expectedSuccess': true,
      },
      {
        'name': 'Insurance Payment',
        'sender': 'AD-HDFCBK',
        'sms': 'PAYMENT ALERT! INR 4391.00 deducted from HDFC Bank A/C No 1234 towards HDFC Standard Life Insurance',
        'expectedAmount': 4391.0,
        'expectedType': TransactionType.debit,
        'expectedSuccess': true,
      },
      {
        'name': 'ATM Withdrawal',
        'sender': 'VK-HDFCBK',
        'sms': 'Withdrawn Rs.7500 From HDFC Bank Card x1234 At ATM On 2025-12-05 Bal Rs.370482.74',
        'expectedAmount': 7500.0,
        'expectedType': TransactionType.debit,
        'expectedSuccess': true,
      },
      {
        'name': 'IMPS Transfer',
        'sender': 'BZ-HDFCBK',
        'sms': 'IMPS INR 32,000.00 sent from HDFC Bank A/c XX1234 on 02-12-25 To A/c xxxxxxxx1234 Ref-533621234',
        'expectedAmount': 32000.0,
        'expectedType': TransactionType.debit,
        'expectedSuccess': true,
      },
      {
        'name': 'UPI Credit',
        'sender': 'AD-SBIBNK',
        'sms': 'Rs.5,000.00 credited to your A/c XX5678 on 15/01/2025 via UPI. Ref: 501234567890',
        'expectedAmount': 5000.0,
        'expectedType': TransactionType.credit,
        'expectedSuccess': true,
      },
      {
        'name': 'Paytm Payment',
        'sender': 'JD-PAYTMB',
        'sms': 'Paid Rs 299 to NETFLIX using Paytm UPI. UPI Ref 987654321098. Balance: Rs 5,432.10',
        'expectedAmount': 299.0,
        'expectedType': TransactionType.debit,
        'expectedSuccess': true,
      },
      {
        'name': 'NEFT Credit',
        'sender': 'VK-ICICIB',
        'sms': 'INR 50,000.00 credited to A/c XX9876 by NEFT Cr-HDFC0001234-EMPLOYER NAME-SALARY Ref NEFT123456',
        'expectedAmount': 50000.0,
        'expectedType': TransactionType.credit,
        'expectedSuccess': true,
      },
    ];

    for (var testCase in testCases) {
      test(testCase['name'] as String, () {
        final result = SmsParser.parse(
          testCase['sms'] as String,
          sender: testCase['sender'] as String,
        );
        
        final expectedSuccess = testCase['expectedSuccess'] as bool;
        expect(result.parseSuccess, expectedSuccess, reason: 'parseSuccess mismatch');
        
        if (expectedSuccess) {
          expect(result.amount, testCase['expectedAmount'], reason: 'amount mismatch');
          expect(result.type, testCase['expectedType'], reason: 'type mismatch');
        }
        
        // Print for visual verification
        print('\n${testCase['name']}: ${result.parseSuccess ? "✅" : "⏭️ SKIPPED"}');
        if (result.parseSuccess) {
          print('  Amount: ₹${result.amount}');
          print('  Type: ${result.type.name}');
          print('  Merchant: ${result.merchant}');
          if (result.bank != null) print('  Bank: ${result.bank}');
          if (result.balance != null) print('  Balance: ₹${result.balance}');
          if (result.referenceId != null) print('  Ref: ${result.referenceId}');
        }
      });
    }
  });

  group('Merchant Extraction Tests', () {
    test('Extracts ATM as merchant for withdrawals', () {
      final sms = 'Rs.5000 withdrawn from ATM. Avl Bal: Rs.10,000';
      final result = SmsParser.parse(sms, sender: 'VK-HDFCBK');
      expect(result.merchant, 'ATM');
    });

    test('Extracts VPA merchant', () {
      final sms = 'Rs.100 paid to swiggy@paytm via UPI';
      final result = SmsParser.parse(sms, sender: 'JD-PAYTMB');
      expect(result.merchant.toLowerCase().contains('swiggy'), true);
    });

    test('Extracts IMPS Transfer as merchant', () {
      final sms = 'IMPS Rs.10,000 sent to A/c XX1234 Ref 123456';
      final result = SmsParser.parse(sms, sender: 'VK-HDFCBK');
      expect(result.merchant, 'IMPS Transfer');
    });
  });

  group('Balance Extraction Tests', () {
    test('Extracts available balance', () {
      final sms = 'Rs.500 debited. Avl Bal: Rs.10,234.56';
      final result = SmsParser.parse(sms, sender: 'VK-HDFCBK');
      expect(result.balance, 10234.56);
    });

    test('Extracts balance without comma', () {
      final sms = 'Withdrawn Rs.1000. Balance Rs 5000';
      final result = SmsParser.parse(sms, sender: 'VK-HDFCBK');
      expect(result.balance, 5000.0);
    });
  });

  group('Reference ID Extraction Tests', () {
    test('Extracts UPI reference', () {
      final sms = 'Rs.100 paid via UPI. Ref 123456789012';
      final result = SmsParser.parse(sms, sender: 'JD-GPAY');
      expect(result.referenceId, '123456789012');
    });
  });
}
