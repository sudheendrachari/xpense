import 'package:flutter/material.dart';
import 'package:xpense/utils/currency_formatter.dart';
import 'package:xpense/utils/theme.dart';
import 'package:intl/intl.dart';

class TotalSpentCard extends StatelessWidget {
  final double totalAmount;
  final DateTime cycleStart;
  final DateTime cycleEnd;

  const TotalSpentCard({
    super.key,
    required this.totalAmount,
    required this.cycleStart,
    required this.cycleEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedAmount = IndianCurrencyFormatter.format(totalAmount);
    
    // Check if it's a full calendar month to simplify display
    String dateRange;
    final lastDayOfMonth = DateTime(cycleStart.year, cycleStart.month + 1, 0);
    
    if (cycleStart.day == 1 && 
        cycleEnd.year == lastDayOfMonth.year && 
        cycleEnd.month == lastDayOfMonth.month && 
        cycleEnd.day == lastDayOfMonth.day) {
      dateRange = DateFormat('MMMM yyyy').format(cycleStart);
    } else {
      dateRange = '${DateFormat('MMM d').format(cycleStart)} - ${DateFormat('MMM d').format(cycleEnd)}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.3 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Prevent expansion
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Total Spent',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600, 
              color: theme.colorScheme.onSurface.withOpacity(0.6)
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formattedAmount,
              style: AppTextStyles.amountLarge.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 40, // Slightly smaller
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              dateRange,
              style: AppTextStyles.bodyMedium.copyWith(
                color: theme.colorScheme.primary, 
                fontWeight: FontWeight.w500
              ),
            ),
          ),
        ],
      ),
    );
  }
}
