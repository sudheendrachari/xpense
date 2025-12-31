import 'package:xpense/models/transaction.dart';
import 'package:xpense/services/database_service.dart';
import 'package:xpense/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DatabaseViewerScreen extends StatefulWidget {
  const DatabaseViewerScreen({super.key});

  @override
  State<DatabaseViewerScreen> createState() => _DatabaseViewerScreenState();
}

class _DatabaseViewerScreenState extends State<DatabaseViewerScreen> {
  List<Transaction> _allTransactions = [];
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final transactions = await DatabaseService().getAllTransactions();
      final stats = await DatabaseService().getDatabaseStats();
      
      setState(() {
        _allTransactions = transactions;
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  List<Transaction> get _filteredTransactions {
    if (_searchQuery.isEmpty) return _allTransactions;
    
    final query = _searchQuery.toLowerCase();
    return _allTransactions.where((tx) {
      return tx.merchant.toLowerCase().contains(query) ||
             tx.body.toLowerCase().contains(query) ||
             tx.bankName.toLowerCase().contains(query) ||
             tx.amount.toString().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Viewer'),
        backgroundColor: AppColors.background,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats Card
                if (_stats != null)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem('Total', '${_stats!['totalCount']}'),
                        if (_stats!['earliestDate'] != null)
                          _buildStatItem(
                            'Earliest',
                            DateFormat('MMM d').format(_stats!['earliestDate'] as DateTime),
                          ),
                        if (_stats!['latestDate'] != null)
                          _buildStatItem(
                            'Latest',
                            DateFormat('MMM d').format(_stats!['latestDate'] as DateTime),
                          ),
                      ],
                    ),
                  ),
                
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by merchant, amount, bank...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Transaction Count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Showing ${_filteredTransactions.length} of ${_allTransactions.length} transactions',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Transactions List
                Expanded(
                  child: _filteredTransactions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No transactions found'
                                    : 'No matches for "$_searchQuery"',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final tx = _filteredTransactions[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: tx.type == TransactionType.debit
                                      ? AppColors.debit.withValues(alpha: 0.15)
                                      : AppColors.credit.withValues(alpha: 0.15),
                                  child: Icon(
                                    tx.type == TransactionType.debit
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    color: tx.type == TransactionType.debit
                                        ? AppColors.debit
                                        : AppColors.credit,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  tx.merchant,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${DateFormat('MMM d, yyyy hh:mm a').format(tx.date)} • ${tx.bankName}',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Text(
                                  '${tx.type == TransactionType.credit ? '+' : '-'}${tx.formattedAmount}',
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: tx.type == TransactionType.debit
                                        ? AppColors.debit
                                        : AppColors.credit,
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildDetailRow('ID', tx.id),
                                        _buildDetailRow('Amount', tx.formattedAmount),
                                        _buildDetailRow('Merchant', tx.merchant),
                                        _buildDetailRow('Category', tx.category),
                                        _buildDetailRow('Type', tx.type.name.toUpperCase()),
                                        _buildDetailRow('Bank', tx.bankName),
                                        _buildDetailRow('Date', DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.date)),
                                        const SizedBox(height: 8),
                                        const Divider(),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Raw SMS Body:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            tx.body,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

