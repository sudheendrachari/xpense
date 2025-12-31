import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xpense/models/transaction.dart';
import 'package:xpense/services/database_service.dart';
import 'package:xpense/utils/theme.dart';
import 'package:xpense/utils/currency_formatter.dart';
import 'package:xpense/widgets/transaction_detail_sheet.dart';
import 'package:xpense/widgets/transaction_list.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  List<Transaction> _transactions = [];
  String? _selectedCategory;
  bool _isLoading = true;
  
  // Date range - default to current month
  late DateTime _startDate;
  late DateTime _endDate;

  // Category colors
  static const Map<String, Color> _categoryColors = {
    'Food': Color(0xFFFF6B6B),
    'Shopping': Color(0xFF4ECDC4),
    'Travel': Color(0xFF45B7D1),
    'Bills': Color(0xFFFFA726),
    'Entertainment': Color(0xFFAB47BC),
    'Investments': Color(0xFF66BB6A),
    'Health': Color(0xFFEF5350),
    'Transfer': Color(0xFF78909C),
    'ATM': Color(0xFF8D6E63),
    'Income': Color(0xFF26A69A),
    'Others': Color(0xFF90A4AE),
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    
    final db = DatabaseService();
    final transactions = await db.getTransactionsInRange(_startDate, _endDate);
    
    setState(() {
      _transactions = transactions;
      _isLoading = false;
    });
  }

  Map<String, double> _getCategoryTotals({bool excludeInvestments = true}) {
    final Map<String, double> totals = {};
    
    for (var tx in _transactions) {
      // Respect manual flags: skip ignored transactions entirely
      if (tx.isIgnored) continue;

      if (tx.type == TransactionType.debit) {
        final category = tx.effectiveCategory;
        // Optionally exclude Investments from totals (both auto and manual)
        if (excludeInvestments && (category == 'Investments' || tx.isInvestment)) continue;
        totals[category] = (totals[category] ?? 0) + tx.amount;
      }
    }
    
    // Sort by amount (descending)
    return Map.fromEntries(
      totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))
    );
  }

  List<Transaction> _getFilteredTransactions() {
    if (_selectedCategory == null) return [];
    return _transactions
        .where((tx) => 
            tx.effectiveCategory == _selectedCategory && 
            tx.type == TransactionType.debit &&
            !tx.isIgnored)
        .toList();
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
            final index = _transactions.indexWhere((t) => t.id == updatedTx.id);
            if (index != -1) {
              _transactions[index] = updatedTx;
            }
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryTotals = _getCategoryTotals();
    // Total spent excludes Investments (stocks, mutual funds are not "spending")
    final totalSpent = _getCategoryTotals(excludeInvestments: true).values.fold(0.0, (a, b) => a + b);
    final filteredTransactions = _getFilteredTransactions();

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    'Insights',
                    style: AppTextStyles.headlineLarge.copyWith(color: Colors.white),
                  ),
                  const Spacer(),
                  // Month selector
                  GestureDetector(
                    onTap: _pickMonth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _getMonthLabel(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : categoryTotals.isEmpty
                        ? _buildEmptyState()
                        : _buildContent(categoryTotals, totalSpent, filteredTransactions),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No expenses this month',
            style: AppTextStyles.bodyLarge.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    Map<String, double> categoryTotals,
    double totalSpent,
    List<Transaction> filteredTransactions,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total spent header
          Center(
            child: Column(
              children: [
                Text(
                  'Total Expenses',
                  style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  IndianCurrencyFormatter.format(totalSpent),
                  style: AppTextStyles.amountLarge.copyWith(fontSize: 32),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Donut Chart
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      return;
                    }
                    final index = pieTouchResponse.touchedSection!.touchedSectionIndex;
                    if (index >= 0 && index < categoryTotals.length) {
                      final category = categoryTotals.keys.elementAt(index);
                      setState(() {
                        _selectedCategory = _selectedCategory == category ? null : category;
                      });
                    }
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: _buildChartSections(categoryTotals, totalSpent),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Category list
          Text(
            'By Category',
            style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),
          
          ...categoryTotals.entries.map((entry) => 
            _buildCategoryTile(entry.key, entry.value, totalSpent)
          ),

          // Filtered transactions
          if (_selectedCategory != null) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  '$_selectedCategory Transactions',
                  style: AppTextStyles.headlineMedium.copyWith(fontSize: 18),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _selectedCategory = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Clear',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.close, size: 14, color: Colors.grey[700]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            if (filteredTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No transactions',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              TransactionList(
                transactions: filteredTransactions,
                onTransactionTap: _showTransactionDetail,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
          ],

          const SizedBox(height: 100), // Bottom padding for nav bar
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildChartSections(
    Map<String, double> categoryTotals,
    double totalSpent,
  ) {
    int index = 0;
    return categoryTotals.entries.map((entry) {
      final isSelected = entry.key == _selectedCategory;
      final radius = isSelected ? 55.0 : 45.0;
      index++;
      
      return PieChartSectionData(
        color: _categoryColors[entry.key] ?? Colors.grey,
        value: entry.value,
        title: isSelected ? '${(entry.value / totalSpent * 100).toStringAsFixed(0)}%' : '',
        radius: radius,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      );
    }).toList();
  }

  Widget _buildCategoryTile(String category, double amount, double total) {
    final percentage = (amount / total * 100);
    final color = _categoryColors[category] ?? Colors.grey;
    final isSelected = category == _selectedCategory;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = _selectedCategory == category ? null : category;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getCategoryIcon(category),
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isSelected ? color : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  IndianCurrencyFormatter.format(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isSelected ? color : null,
                  ),
                ),
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food': return Icons.restaurant;
      case 'shopping': return Icons.shopping_bag;
      case 'travel': return Icons.directions_car;
      case 'bills': return Icons.receipt_long;
      case 'entertainment': return Icons.movie;
      case 'investments': return Icons.trending_up;
      case 'health': return Icons.local_hospital;
      case 'transfer': return Icons.swap_horiz;
      case 'atm': return Icons.atm;
      case 'income': return Icons.account_balance_wallet;
      case 'others': return Icons.more_horiz;
      default: return Icons.category;
    }
  }

  String _getMonthLabel() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[_startDate.month - 1]} ${_startDate.year}';
  }

  void _pickMonth() async {
    final now = DateTime.now();
    
    // Generate last 6 months
    final List<DateTime> months = [];
    for (int i = 0; i < 6; i++) {
      months.add(DateTime(now.year, now.month - i, 1));
    }
    
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    await showModalBottomSheet(
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
                'Select Month',
                style: AppTextStyles.headlineMedium.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 16),
              ...months.map((month) {
                final isSelected = _startDate.year == month.year && 
                                   _startDate.month == month.month;
                final label = '${monthNames[month.month - 1]} ${month.year}';
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.calendar_today_outlined,
                    color: isSelected ? AppColors.primary : Colors.grey[400],
                    size: 20,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.primary : null,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _startDate = DateTime(month.year, month.month, 1);
                      _endDate = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
                      _selectedCategory = null;
                    });
                    _loadTransactions();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

