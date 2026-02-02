import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/settings_repository.dart';
import '../../core/constants/app_constants.dart';

final settingsProvider = FutureProvider<PayrollSettings>((ref) async {
  return SettingsRepository().getSettings(AppConstants.companyId);
});

class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() =>
      _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _pfCapController;
  late TextEditingController _esicThresholdController;
  late TextEditingController _ptThresholdController;
  late TextEditingController _lwfAmountController;
  late TextEditingController _hraPercentageController;
  List<int> _selectedLwfMonths = [];

  @override
  void initState() {
    super.initState();
    _pfCapController = TextEditingController();
    _esicThresholdController = TextEditingController();
    _ptThresholdController = TextEditingController();
    _lwfAmountController = TextEditingController();
    _hraPercentageController = TextEditingController();
  }

  void _initializeControllers(PayrollSettings settings) {
    if (_pfCapController.text.isEmpty) {
      _pfCapController.text = settings.pfCap.toString();
      _esicThresholdController.text = settings.esicThreshold.toString();
      _ptThresholdController.text = settings.ptThreshold.toString();
      _lwfAmountController.text = settings.lwfAmount.toString();
      _hraPercentageController.text = settings.hraPercentage.toString();
      _selectedLwfMonths = List.from(settings.lwfMonths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Payroll Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.greenAccent),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: settingsAsync.when(
        data: (settings) {
          _initializeControllers(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _sectionHeader('Statutory Thresholds'),
                _buildTextField(
                  'PF Contribution Cap',
                  _pfCapController,
                  'Maximum basic pay for PF calculation (e.g. 15000)',
                ),
                _buildTextField(
                  'ESIC Eligibility Limit',
                  _esicThresholdController,
                  'Gross pay limit for ESIC (e.g. 21000)',
                ),
                _buildTextField(
                  'PT Threshold',
                  _ptThresholdController,
                  'Minimum gross for Professional Tax (e.g. 12000)',
                ),

                const SizedBox(height: 32),
                _sectionHeader('Allowances & Others'),
                _buildTextField(
                  'HRA Percentage (%)',
                  _hraPercentageController,
                  'House Rent Allowance % of Basic (e.g. 5)',
                ),
                _buildTextField(
                  'LWF Deduction Amount',
                  _lwfAmountController,
                  'Flat amount for LWF (e.g. 30)',
                ),

                const SizedBox(height: 32),
                _sectionHeader('LWF Deduction Months'),
                Wrap(
                  spacing: 8,
                  children: List.generate(12, (index) {
                    final month = index + 1;
                    final isSelected = _selectedLwfMonths.contains(month);
                    return FilterChip(
                      label: Text(_getMonthName(month)),
                      selected: isSelected,
                      selectedColor: Colors.blueAccent.withAlpha(77),
                      checkmarkColor: Colors.blueAccent,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedLwfMonths.add(month);
                          } else {
                            _selectedLwfMonths.remove(month);
                          }
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saveSettings,
                  child: const Text(
                    'Update System Configuration',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.blueAccent,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    return [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];
  }

  Future<void> _saveSettings() async {
    final updated = PayrollSettings(
      companyId: AppConstants.companyId,
      pfCap: double.tryParse(_pfCapController.text) ?? 15000,
      esicThreshold: double.tryParse(_esicThresholdController.text) ?? 21000,
      ptThreshold: double.tryParse(_ptThresholdController.text) ?? 12000,
      lwfAmount: double.tryParse(_lwfAmountController.text) ?? 0,
      lwfMonths: _selectedLwfMonths,
      hraPercentage: double.tryParse(_hraPercentageController.text) ?? 0,
    );

    try {
      await SettingsRepository().updateSettings(updated);
      ref.invalidate(settingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System settings updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }
}
