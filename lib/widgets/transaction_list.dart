import 'package:xpense/models/transaction.dart';
import 'package:xpense/utils/currency_formatter.dart';
import 'package:xpense/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TransactionList extends StatefulWidget {
  final List<Transaction> transactions;
  final Function(Transaction) onTransactionTap;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const TransactionList({
    super.key,
    required this.transactions,
    required this.onTransactionTap,
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  State<TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends State<TransactionList> {
  final Set<DateTime> _collapsedDates = {};

  void _toggleCollapse(DateTime date) {
    setState(() {
      if (_collapsedDates.contains(date)) {
        _collapsedDates.remove(date);
      } else {
        _collapsedDates.add(date);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildGroupedList();

    return ListView.builder(
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      padding: const EdgeInsets.only(bottom: 8), 
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        if (item is HeaderItem) {
          final isCollapsed = _collapsedDates.contains(item.date);
          return GestureDetector(
            onTap: () => _toggleCollapse(item.date),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: isCollapsed ? -0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
              _formatDateHeader(item.date),
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                    ),
                  ),
                  if (isCollapsed) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${item.txCount} transactions',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (item.dayTotal > 0)
                    Text(
                      IndianCurrencyFormatter.format(item.dayTotal),
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
          );
        } else if (item is TxItem) {
          // Skip rendering if this date is collapsed
          if (_collapsedDates.contains(item.dateKey)) {
            return const SizedBox.shrink();
          }
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Opacity(
                  opacity: item.tx.isIgnored ? 0.4 : 1.0,
                  child: ListTile(
                    onTap: () => widget.onTransactionTap(item.tx),
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      radius: 20,
                      child: Icon(
                        _getCategoryIcon(item.tx.effectiveCategory),
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.tx.merchant,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: item.tx.isIgnored ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.tx.manualCategory != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.edit, size: 12, color: Colors.grey[400]),
                          ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(item.tx.date),
                          style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                        ),
                        if (item.tx.isInvestment) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.trending_up, size: 12, color: AppColors.secondary),
                          const SizedBox(width: 2),
                          Text(
                            'Investment',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 10,
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (item.tx.isIgnored) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.visibility_off_outlined, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 2),
                          Text(
                            'Ignored',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Text(
                      '${item.tx.type == TransactionType.credit ? '+' : '-'} ${item.tx.formattedAmount}',
                      style: AppTextStyles.amountList.copyWith(
                        color: item.tx.isIgnored 
                            ? Colors.grey[400]
                            : (item.tx.type == TransactionType.debit ? AppColors.debit : AppColors.credit),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (index < items.length - 1 && items[index + 1] is TxItem && !_collapsedDates.contains(item.dateKey))
                  const Divider(height: 1, indent: 72, endIndent: 24, color: Color(0xFFEEEEEE)),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  List<ListItem> _buildGroupedList() {
    if (widget.transactions.isEmpty) return [];

    // First, calculate day totals and counts (only non-ignored, non-investment debits for total)
    final Map<DateTime, double> dayTotals = {};
    final Map<DateTime, int> dayCounts = {};
    for (var tx in widget.transactions) {
      final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
      dayCounts[date] = (dayCounts[date] ?? 0) + 1;
      if (tx.type == TransactionType.debit && !tx.isIgnored && !tx.isInvestment) {
        dayTotals[date] = (dayTotals[date] ?? 0) + tx.amount;
      }
    }

    final List<ListItem> items = [];
    DateTime? lastDate;

    for (var tx in widget.transactions) {
      final date = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (lastDate == null || date != lastDate) {
        items.add(HeaderItem(date, dayTotals[date] ?? 0, dayCounts[date] ?? 0));
        lastDate = date;
      }
      items.add(TxItem(tx, date));
    }
    return items;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    return DateFormat('EEE, dd MMM').format(date);
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'travel':
        return Icons.directions_car;
      case 'bills':
        return Icons.receipt_long;
      case 'entertainment':
        return Icons.movie;
      case 'investments':
        return Icons.trending_up;
      case 'health':
        return Icons.local_hospital;
      case 'transfer':
        return Icons.swap_horiz;
      case 'atm':
        return Icons.atm;
      case 'income':
        return Icons.account_balance_wallet;
      case 'others':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }
}

abstract class ListItem {}

class HeaderItem implements ListItem {
  final DateTime date;
  final double dayTotal;
  final int txCount;
  HeaderItem(this.date, this.dayTotal, this.txCount);
}

class TxItem implements ListItem {
  final Transaction tx;
  final DateTime dateKey;
  TxItem(this.tx, this.dateKey);
}
