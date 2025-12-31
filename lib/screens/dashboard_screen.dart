import 'package:xpense/models/transaction.dart';
import 'package:xpense/main.dart' as main_app;
import 'package:xpense/screens/configuration_screen.dart';
import 'package:xpense/services/background_service.dart';
import 'package:xpense/services/database_service.dart';
import 'package:xpense/services/sms_service.dart';
import 'package:xpense/utils/theme.dart';
import 'package:xpense/widgets/day_spending_chart.dart';
import 'package:xpense/widgets/total_spent_card.dart';
import 'package:xpense/widgets/transaction_detail_sheet.dart';
import 'package:xpense/widgets/transaction_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardScreen extends StatefulWidget {
  final Function(bool)? onThemeChanged;
  final bool isDarkMode;
  final bool showSettingsIcon;
  
  const DashboardScreen({
    super.key,
    this.onThemeChanged,
    this.isDarkMode = false,
    this.showSettingsIcon = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedBank = 'HDFC Bank';
  List<Transaction> _allTransactions = []; 
  List<Transaction> _currentTransactions = [];
  bool _isSyncing = false;
  bool _isLoading = true; // Loading state for initial DB read
  String _transactionFilter = 'All';
  
  // Progress tracking for AI processing
  String _syncStatus = '';
  int _syncProgress = 0;
  int _syncTotal = 0;

  final SmsService _smsService = SmsService();
  DateTime? _lastRefreshTime;
  static const Duration _refreshThrottle = Duration(milliseconds: 500); // Throttle refreshes to max once per 500ms

  
  DateTime _cycleStart = DateTime.now();
  DateTime _cycleEnd = DateTime.now();
  
  // Track if we've ever synced (for better empty states)
  bool _hasEverSynced = false;
  
  // Carousel and scroll controllers
  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  bool _showScrollToTop = false;
  static const double _scrollThreshold = 200; // Show FAB after scrolling this much

  @override
  void initState() {
    super.initState();
    _updateCycleDates(DateTime.now());
    
    // Setup scroll listener for FAB visibility
    _scrollController.addListener(_onScroll);
    
    // Register callback for real-time SMS updates
    main_app.setRealTimeTransactionCallback((Transaction tx) {
      if (mounted) {
        _refreshTransactionList();
      }
    });
    
    // Load existing transactions from DB first, then run delta sync in background
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Step 1: Load existing transactions from DB immediately (instant!)
      await _loadExistingTransactions();
      
      // Step 2: Let UI settle before starting delta sync
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Step 3: Run delta sync in background (non-blocking)
      if (mounted) _performDeltaSync();
    });
  }
  
  void _onScroll() {
    final shouldShow = _scrollController.offset > _scrollThreshold;
    if (shouldShow != _showScrollToTop) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
  }
  
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }
  
  void _scrollToDay(DateTime targetDate) {
    HapticFeedback.lightImpact();
    
    // Calculate approximate scroll position
    // Header height: ~50px, Transaction height: ~75px
    // Carousel + dots + container header: ~280px
    const double baseOffset = 280;
    const double headerHeight = 50;
    const double txHeight = 75;
    
    double offset = baseOffset;
    
    // Group transactions by date to calculate position
    final Map<DateTime, List<Transaction>> byDate = {};
    for (var tx in _currentTransactions) {
      final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
      byDate.putIfAbsent(date, () => []).add(tx);
    }
    
    // Sort dates descending (most recent first)
    final sortedDates = byDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    
    // Check if target date has transactions
    final normalizedTarget = DateTime(targetDate.year, targetDate.month, targetDate.day);
    if (!byDate.containsKey(normalizedTarget)) {
      // No transactions for this day
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No transactions on this day'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    
    // Find position of target date
    for (var date in sortedDates) {
      if (date == normalizedTarget) {
        // Found it! Scroll to this position
        break;
      }
      // Add height for this date's header + transactions
      offset += headerHeight;
      offset += (byDate[date]?.length ?? 0) * txHeight;
    }
    
    // Scroll with animation
    _scrollController.animateTo(
      offset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }
  
  @override
  void dispose() {
    // Unregister callback when screen is disposed
    main_app.setRealTimeTransactionCallback(null);
    _pageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Load existing transactions from database (fast, no SMS scanning)
  Future<void> _loadExistingTransactions() async {
    try {
      final db = DatabaseService();
      final transactions = await db.getTransactionsInRange(_cycleStart, _cycleEnd);
      
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
          _filterTransactions();
          _hasEverSynced = transactions.isNotEmpty; // If we have transactions, we've synced before
          _isLoading = false; // Done loading from DB
        });
        debugPrint('DASHBOARD: Loaded ${transactions.length} existing transactions from DB');
      }
    } catch (e) {
      debugPrint('DASHBOARD: Error loading existing transactions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _updateCycleDates(DateTime referenceDate) {
    // Strict Calendar Month: 1st Day to Last Day
    _cycleStart = DateTime(referenceDate.year, referenceDate.month, 1);
    // 0th day of next month gives the last day of current month, add 23:59:59 for full day
    _cycleEnd = DateTime(referenceDate.year, referenceDate.month + 1, 0, 23, 59, 59); 
  }

// ... existing code ...


  double get _totalSpent {
    // Only sum DEBITS for "Total Spent". 
    // Exclude ignored and investments
    return _currentTransactions
        .where((tx) => tx.type == TransactionType.debit && !tx.isIgnored && !tx.isInvestment)
        .fold(0, (sum, item) => sum + item.amount);
  }

  void _onBankChanged(String? newValue) {
    if (newValue != null) {
      setState(() {
        _selectedBank = newValue;
        _filterTransactions();
      });
    }
  }

  void _filterTransactions() {
    final targetBank = _selectedBank == 'HDFC Bank' ? 'HDFC' : 'AXIS';
    
    _currentTransactions = _allTransactions.where((tx) {
      // 1. Bank Filter
      if (tx.bankName != targetBank) return false;
      
      // 2. Type Filter
      if (_transactionFilter == 'Debit' && tx.type != TransactionType.debit) return false;
      if (_transactionFilter == 'Credit' && tx.type != TransactionType.credit) return false;
      
      
      return true;
    }).toList();
  }

  /// Refresh transaction list from database (for real-time updates)
  /// Throttled to avoid excessive DB queries when transactions come in quickly
  Future<void> _refreshTransactionList() async {
    final now = DateTime.now();
    
    // Throttle: only refresh if enough time has passed since last refresh
    if (_lastRefreshTime != null && 
        now.difference(_lastRefreshTime!) < _refreshThrottle) {
      return;
    }
    
    _lastRefreshTime = now;
    
    try {
      final db = DatabaseService();
      final transactions = await db.getTransactionsInRange(_cycleStart, _cycleEnd);
      if (mounted) {
        setState(() {
          _allTransactions = transactions;
          _filterTransactions();
        });
      }
    } catch (e) {
      debugPrint('DASHBOARD: Error refreshing transaction list: $e');
    }
  }

  /// Perform delta sync - only fetch new SMS since last sync (silent, no UI indicator)
  Future<void> _performDeltaSync() async {
    if (_isSyncing) return; // Prevent multiple syncs
    
    // Skip delta sync if last sync was < 30 seconds ago (e.g., just came from setup)
    final lastSync = await DatabaseService().getLastSyncTimestamp();
    if (lastSync != null && DateTime.now().difference(lastSync).inSeconds < 30) {
      debugPrint('DASHBOARD: Skipping delta sync - last sync was ${DateTime.now().difference(lastSync).inSeconds}s ago');
      return;
    }
    
    // Silent sync - no UI indicator for background sync
    debugPrint('DASHBOARD: Starting silent delta sync...');

    try {
      final newCount = await _smsService.performDeltaSync();
      
      // Refresh transaction list if new transactions found
      if (newCount > 0) {
        await _refreshTransactionList();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Found $newCount new transaction${newCount == 1 ? '' : 's'}'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
      
      _hasEverSynced = true;
      debugPrint('DASHBOARD: Delta sync complete - $newCount new transactions');
    } catch (e) {
      debugPrint('DASHBOARD: Delta sync error: $e');
    }
  }

  /// Manual sync triggered by user (uses delta sync)
  Future<void> _performManualSync() async {
    if (_isSyncing) return;
    
    setState(() {
      _isSyncing = true;
      _syncStatus = 'Syncing...';
      _syncProgress = 0;
      _syncTotal = 0;
    });
    HapticFeedback.mediumImpact();

    try {
      // Start foreground service for longer syncs
      await BackgroundService.startService(
        title: 'Syncing Transactions',
        message: 'Checking for new SMS...',
      );
      
      final newCount = await _smsService.performDeltaSync(
        onProgress: (current, total, status) {
          if (mounted) {
            setState(() {
              _syncProgress = current;
              _syncTotal = total;
              _syncStatus = status;
            });
          }
          BackgroundService.updateNotification(
            title: 'Syncing Transactions',
            message: status,
          );
        },
      );
      
      await BackgroundService.stopService();
      await _refreshTransactionList();
      
      setState(() {
        _isSyncing = false;
        _syncStatus = '';
        _syncProgress = 0;
        _syncTotal = 0;
        _lastRefreshTime = null;
        _hasEverSynced = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newCount > 0 
                ? 'Sync complete: $newCount new transaction${newCount == 1 ? '' : 's'}'
                : 'All up to date!'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      await BackgroundService.stopService();
      
      setState(() {
        _isSyncing = false;
        _syncStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }



  Future<void> _pickDateRange() async {
    // Show preset options first
    final preset = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Date Range',
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 16),
              _buildPresetButton(context, 'This Month', () {
                Navigator.pop(context, 'this_month');
              }),
              _buildPresetButton(context, 'Last Month', () {
                Navigator.pop(context, 'last_month');
              }),
              _buildPresetButton(context, 'Last 7 Days', () {
                Navigator.pop(context, 'last_7_days');
              }),
              _buildPresetButton(context, 'Last 30 Days', () {
                Navigator.pop(context, 'last_30_days');
              }),
              _buildPresetButton(context, 'Custom Range', () {
                Navigator.pop(context, 'custom');
              }),
            ],
          ),
        ),
      ),
    );

    if (preset == null) return;

    DateTime newStart, newEnd;
    final now = DateTime.now();

    switch (preset) {
      case 'this_month':
        newStart = DateTime(now.year, now.month, 1);
        newEnd = DateTime(now.year, now.month + 1, 0);
        break;
      case 'last_month':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        newStart = lastMonth;
        newEnd = DateTime(now.year, now.month, 0);
        break;
      case 'last_7_days':
        newStart = now.subtract(const Duration(days: 7));
        newEnd = now;
        break;
      case 'last_30_days':
        newStart = now.subtract(const Duration(days: 30));
        newEnd = now;
        break;
      case 'custom':
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2023),
          lastDate: DateTime.now().add(const Duration(days: 30)),
          initialDateRange: DateTimeRange(start: _cycleStart, end: _cycleEnd),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                ),
              ),
              child: child!,
            );
          }
        );
        if (picked == null) return;
        newStart = picked.start;
        newEnd = picked.end;
        break;
      default:
        return;
    }

    setState(() {
      _cycleStart = newStart;
      _cycleEnd = newEnd;
    });
    
    // Just filter existing data from DB (instant) - no need to rescan SMS
    await _refreshTransactionList();
  }

  Widget _buildPresetButton(BuildContext context, String label, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(Icons.calendar_today, color: AppColors.primary),
      title: Text(label, style: AppTextStyles.bodyLarge),
      onTap: onTap,
    );
  }

  Widget _buildEmptyState() {
    // Different empty states based on context
    if (!_hasEverSynced) {
      // Never synced before
      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.sms_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome!',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the sync button below to scan your SMS and start tracking expenses.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _performManualSync,
                icon: const Icon(Icons.sync),
                label: const Text('Sync'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_allTransactions.isEmpty) {
      // Synced before but no transactions in current date range
      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'No transactions in this period',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try selecting a different date range or sync again to check for new transactions.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range),
                label: const Text('Change Date Range'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Has transactions but filtered out
      return Padding(
        padding: const EdgeInsets.all(48.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'No transactions match your filters',
                style: AppTextStyles.headlineMedium.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try changing the bank or transaction type filter.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showTransactionDetail(Transaction tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionDetailSheet(
        transaction: tx,
        onUpdate: (updatedTx) {
          // Update the local list and trigger UI refresh
          setState(() {
            final index = _allTransactions.indexWhere((t) => t.id == updatedTx.id);
            if (index != -1) {
              _allTransactions[index] = updatedTx;
              _filterTransactions();
            }
          });
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/app_icon.png',
              width: 36,
              height: 36,
            ),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ['HDFC', 'Axis'].map((bank) {
              final isSelected = _selectedBank == '$bank Bank';
              return GestureDetector(
                onTap: () => _onBankChanged('$bank Bank'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    bank,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          if (widget.showSettingsIcon)
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppColors.primary),
               onPressed: () async {
                 await Navigator.of(context).push(
                   MaterialPageRoute(
                     builder: (_) => ConfigurationScreen(
                       onThemeChanged: widget.onThemeChanged,
                     ),
                   ),
                 );
                 // Reload theme if changed
                 if (mounted && widget.onThemeChanged != null) {
                   final prefs = await SharedPreferences.getInstance();
                   final isDark = prefs.getBool('dark_mode') ?? false;
                   widget.onThemeChanged!(isDark);
                 }
              },
            ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Stack(
        fit: StackFit.expand,
        children: [
          RefreshIndicator(
            onRefresh: () async {
              // Don't await - let the custom banner handle the UI
              _performManualSync();
              // Return immediately so RefreshIndicator hides its spinner
              return;
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(), // Enable pull-to-refresh even when content is short
              child: Column(
                children: [
                // Carousel of cards
                SizedBox(
                  height: 210,
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    children: [
                      // Card 1: Total Spent
                      GestureDetector(
                        onTap: _pickDateRange,
                        child: TotalSpentCard(
                          totalAmount: _totalSpent,
                          cycleStart: _cycleStart,
                          cycleEnd: _cycleEnd,
                        ),
                      ),
                      // Card 2: Daily Spending Chart
                      DaySpendingChart(
                        transactions: _currentTransactions,
                        startDate: _cycleStart,
                        endDate: _cycleEnd,
                        onDayTap: _scrollToDay,
                      ),
                    ],
                  ),
                ),
                // Dot indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(2, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index 
                            ? AppColors.primary 
                            : AppColors.primary.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: BoxConstraints(
                    minHeight: (MediaQuery.of(context).size.height - 200).clamp(0.0, double.infinity),
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Transactions',
                              style: AppTextStyles.headlineMedium.copyWith(fontSize: 20),
                            ),
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: ['All', 'Debit', 'Credit'].map((filter) {
                                  final isSelected = _transactionFilter == filter;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _transactionFilter = filter;
                                        _filterTransactions();
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: isSelected ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ] : null,
                                      ),
                                      child: Text(
                                        filter,
                                        style: TextStyle(
                                          color: isSelected ? AppColors.primary : Colors.grey[600],
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _currentTransactions.isEmpty 
                        ? _buildEmptyState()
                        : TransactionList(
                            transactions: _currentTransactions,
                            onTransactionTap: _showTransactionDetail,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                          ),
                      // Add extra padding at bottom so FAB doesn't cover last item
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          // Non-blocking progress indicator at the top
          if (_isSyncing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          value: _syncTotal > 0 ? _syncProgress / _syncTotal : null,
                          color: AppColors.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _syncStatus.isNotEmpty ? _syncStatus : 'Syncing...',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_syncTotal > 0)
                              Text(
                                '$_syncProgress / $_syncTotal transactions',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _showScrollToTop
          ? FloatingActionButton(
              onPressed: _scrollToTop,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            )
          : null,
    );
  }
}
