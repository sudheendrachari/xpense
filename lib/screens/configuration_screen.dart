import 'package:xpense/services/database_service.dart';
import 'package:xpense/services/biometric_service.dart';
import 'package:xpense/main.dart';
import 'package:xpense/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigurationScreen extends StatefulWidget {
  final Function(bool)? onThemeChanged;
  
  const ConfigurationScreen({super.key, this.onThemeChanged});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  bool _isDarkMode = false;
  bool _isBiometricEnabled = false;
  bool _isDeviceSupported = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final supported = await BiometricService.isDeviceSupported();
    final enabled = await BiometricService.isBiometricEnabled();
    
    setState(() {
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _isDeviceSupported = supported;
      _isBiometricEnabled = enabled;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // If enabling, authenticate first to confirm
      final authenticated = await BiometricService.authenticate();
      if (!authenticated) return;
    }
    
    await BiometricService.setBiometricEnabled(value);
    if (mounted) {
      setState(() {
        _isBiometricEnabled = value;
      });
      HapticFeedback.lightImpact();

      // Notify MyApp to refresh biometric status
      MyApp.of(context)?.refreshPreferences();
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    setState(() {
      _isDarkMode = value;
    });
    HapticFeedback.lightImpact();
    // Notify parent to update theme
    if (widget.onThemeChanged != null) {
      widget.onThemeChanged!(value);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration'),
        backgroundColor: AppColors.background,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync & Cache', style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.delete_sweep, color: AppColors.error),
                title: const Text('Clear Local Cache'),
                subtitle: const Text('Deletes all parsed transactions from DB'),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear Local Cache?'),
                      content: const Text('This will delete all stored transactions. You will need to re-sync your SMS.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true), 
                          child: const Text('Clear', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await DatabaseService().clearAll();
                    HapticFeedback.heavyImpact();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache cleared successfully'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 32),
            Text('Database', style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.info_outline, color: AppColors.primary),
                title: const Text('Database Info'),
                subtitle: const Text('View stats and export command'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final stats = await DatabaseService().getDatabaseStats();
                  if (mounted) {
                    showModalBottomSheet(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (ctx) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text('Database Info', style: AppTextStyles.headlineMedium),
                            const SizedBox(height: 16),
                            _buildInfoRow('Total Transactions', '${stats['totalCount']}'),
                            if (stats['earliestDate'] != null)
                              _buildInfoRow('Earliest', '${stats['earliestDate'].toString().substring(0, 10)}'),
                            if (stats['latestDate'] != null)
                              _buildInfoRow('Latest', '${stats['latestDate'].toString().substring(0, 10)}'),
                            const SizedBox(height: 20),
                            Text('Export to Mac', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const SelectableText(
                                'adb exec-out run-as sudheendra.personal.finance_app cat databases/finance_tracker.db > ~/Downloads/finance.db',
                                style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '💡 Open with DB Browser for SQLite',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            // Bottom safe area padding
                            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 24),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 32),
            Text('Appearance', style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: AppColors.primary.withOpacity(0.05),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Switch between light and dark theme'),
                value: _isDarkMode,
                onChanged: _toggleDarkMode,
                activeColor: AppColors.primary,
              ),
            ),
            if (_isDeviceSupported) ...[
              const SizedBox(height: 32),
              Text('Security', style: AppTextStyles.headlineMedium.copyWith(fontSize: 18)),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: AppColors.primary.withOpacity(0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile(
                  title: const Text('Biometric Login'),
                  subtitle: const Text('Use fingerprint to unlock the app'),
                  value: _isBiometricEnabled,
                  onChanged: _toggleBiometric,
                  activeColor: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(value, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
