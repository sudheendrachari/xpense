import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:xpense/models/transaction.dart';
import 'package:xpense/utils/theme.dart';
import 'package:xpense/utils/merchant_categories.dart';
import 'package:xpense/utils/currency_formatter.dart';
import 'package:xpense/services/database_service.dart';

class TransactionDetailSheet extends StatefulWidget {
  final Transaction transaction;
  final Function(Transaction) onUpdate;

  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    required this.onUpdate,
  });

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  late Transaction _tx;

  @override
  void initState() {
    super.initState();
    _tx = widget.transaction;
  }

  Future<void> _updateOverride({bool? isIgnored, bool? isInvestment, String? manualCategory}) async {
    final updatedTx = _tx.copyWith(
      isIgnored: isIgnored,
      isInvestment: isInvestment,
      manualCategory: manualCategory,
    );

    await DatabaseService().updateTransactionManualOverrides(
      updatedTx.id,
      isIgnored: updatedTx.isIgnored,
      isInvestment: updatedTx.isInvestment,
      manualCategory: updatedTx.manualCategory,
    );

    setState(() {
      _tx = updatedTx;
    });
    
    widget.onUpdate(updatedTx);
    HapticFeedback.mediumImpact();
  }

  void _showCategoryPicker() {
    final categories = MerchantCategories.allCategories;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Category',
              style: AppTextStyles.headlineMedium.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return ListTile(
                    title: Text(cat, style: AppTextStyles.bodyLarge),
                    trailing: _tx.effectiveCategory == cat 
                        ? const Icon(Icons.check, color: AppColors.primary) 
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _updateOverride(manualCategory: cat);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Merchant name
              Text(_tx.merchant, style: AppTextStyles.headlineMedium),
              const SizedBox(height: 8),
              
              // Amount
              Text(
                '${_tx.type == TransactionType.credit ? '+' : '-'} ${_tx.formattedAmount}',
                style: AppTextStyles.amountLarge.copyWith(
                  color: _tx.isIgnored 
                      ? Colors.grey[400] 
                      : (_tx.type == TransactionType.debit ? AppColors.debit : AppColors.credit),
                  fontSize: 32,
                  decoration: _tx.isIgnored ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 24),

              // Quick Actions
              Text(
                'Management',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildActionChip(
                    label: 'Ignore',
                    icon: _tx.isIgnored ? Icons.visibility : Icons.visibility_off_outlined,
                    isSelected: _tx.isIgnored,
                    onTap: () => _updateOverride(isIgnored: !_tx.isIgnored),
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  _buildActionChip(
                    label: 'Investment',
                    icon: Icons.trending_up,
                    isSelected: _tx.isInvestment,
                    onTap: () => _updateOverride(isInvestment: !_tx.isInvestment),
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  _buildActionChip(
                    label: 'Category',
                    icon: Icons.edit_outlined,
                    isSelected: _tx.manualCategory != null,
                    onTap: _showCategoryPicker,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Details
              _buildDetailRow('Date', _tx.formattedDate, theme),
              _buildDetailRow('Bank', _tx.bankName, theme),
              _buildDetailRow(
                'Category', 
                _tx.effectiveCategory, 
                theme, 
                isManual: _tx.manualCategory != null,
                onEdit: _showCategoryPicker,
              ),
              _buildDetailRow('Type', _tx.type.name.toUpperCase(), theme),
              
              const SizedBox(height: 24),
              
              // Raw SMS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Raw SMS',
                    style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final smsOneLine = _tx.body.replaceAll('\n', ' ');
                      // ignore: avoid_print
                      print('${_tx.merchant} | ${_tx.formattedAmount} | ${_tx.type.name} | ${_tx.bankName} | $smsOneLine');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Printed to console'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Print'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _tx.body,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              // Bottom safe area padding
              SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
            border: Border.all(
              color: isSelected ? color : Colors.grey.withOpacity(0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? color : Colors.grey[600],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme, {bool isManual = false, VoidCallback? onEdit}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isManual)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.edit, size: 12, color: AppColors.primary),
                    ),
                  Flexible(
                    child: Text(
                      value,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isManual ? AppColors.primary : null,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

