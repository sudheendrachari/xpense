import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xpense/models/transaction.dart';
import 'package:xpense/utils/theme.dart';
import 'package:xpense/utils/currency_formatter.dart';
import 'package:intl/intl.dart';

class DaySpendingChart extends StatelessWidget {
  final List<Transaction> transactions;
  final DateTime startDate;
  final DateTime endDate;
  final Function(DateTime)? onDayTap;

  const DaySpendingChart({
    super.key,
    required this.transactions,
    required this.startDate,
    required this.endDate,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final dayData = _calculateDaySpending();
    if (dayData.isEmpty) return const SizedBox.shrink();

    final maxSpending = dayData.values.reduce((a, b) => a > b ? a : b);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Spending',
            style: AppTextStyles.headlineMedium.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxSpending > 0 ? maxSpending * 1.1 : 1000, // Add 10% padding
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => AppColors.primary,
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final date = dayData.keys.elementAt(groupIndex);
                      final amount = dayData[date] ?? 0;
                      final isToday = date == todayDate;
                      return BarTooltipItem(
                        '${_formatDayLabel(date, isToday)}\n${IndianCurrencyFormatter.format(amount)}',
                        AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                  touchCallback: (FlTouchEvent event, barTouchResponse) {
                    if (event is FlTapUpEvent && 
                        barTouchResponse?.spot != null && 
                        onDayTap != null) {
                      final index = barTouchResponse!.spot!.touchedBarGroupIndex;
                      if (index >= 0 && index < dayData.length) {
                        final date = dayData.keys.elementAt(index);
                        onDayTap!(date);
                      }
                    }
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= dayData.length) return const SizedBox();
                        
                        // Only show labels for 1st, every 7th day, and today
                        final date = dayData.keys.elementAt(index);
                        final isToday = date == todayDate;
                        final isFirst = index == 0;
                        final isWeekStart = date.day == 1 || date.day == 8 || date.day == 15 || date.day == 22;
                        
                        if (!isToday && !isFirst && !isWeekStart) {
                          return const SizedBox();
                        }
                        
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            date.day.toString(),
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 9,
                              color: isToday ? AppColors.primary : Colors.grey[500],
                              fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        );
                      },
                      reservedSize: 20,
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxSpending > 0 ? maxSpending / 4 : 1000,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[200]!,
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: dayData.entries.toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final date = entry.value.key;
                  final amount = entry.value.value;
                  final isToday = date == todayDate;
                  
                  // Dynamic bar width based on number of days
                  final barWidth = dayData.length > 20 ? 6.0 : (dayData.length > 10 ? 8.0 : 12.0);
                  
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: amount > 0 ? amount : 0, // Ensure non-negative
                        color: isToday 
                            ? AppColors.primary 
                            : (amount > maxSpending * 0.7 
                                ? AppColors.debit.withOpacity(0.8)
                                : AppColors.primary.withOpacity(0.5)),
                        width: barWidth,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<DateTime, double> _calculateDaySpending() {
    final Map<DateTime, double> daySpending = {};
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Initialize all days in range with 0
    var current = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      // Only include days up to today
      if (current.isAfter(todayDate)) break;
      daySpending[current] = 0;
      current = current.add(const Duration(days: 1));
    }

    // Calculate spending per day (only non-ignored, non-investment debits)
    for (var tx in transactions) {
      if (tx.type != TransactionType.debit || tx.isIgnored || tx.isInvestment) continue;
      
      final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (daySpending.containsKey(date)) {
        daySpending[date] = (daySpending[date] ?? 0) + tx.amount;
      }
    }

    // Sort by date
    final sorted = daySpending.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    return Map.fromEntries(sorted);
  }

  String _formatDayLabel(DateTime date, bool isToday) {
    if (isToday) return 'Today';
    
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    
    if (date == yesterday) return 'Yest';
    
    // Show day number (1, 2, 3...) for other days
    return DateFormat('d').format(date);
  }
}

