import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/attendance_providers.dart';
import '../providers/unit_providers.dart';
import '../../data/services/export_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String? _selectedUnitId;
  String? _selectedUnitName;
  bool _isLoading = false;

  final exportService = ExportService();

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _exportAttendance() async {
    setState(() => _isLoading = true);
    try {
      // Fetch data
      final logs =
          await ref.read(attendanceRepositoryProvider).getAttendanceReport(
                startDate: _startDate,
                endDate: _endDate,
                unitId: _selectedUnitId,
              );

      if (logs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No records found for this period.')),
          );
        }
        return;
      }

      // Export
      await exportService.exportAttendanceReport(
        logs: logs,
        startDate: _startDate,
        endDate: _endDate,
        unitName: _selectedUnitName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report generated successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We reuse unitListProvider.
    // Optimization: create a specific provider for dropdown if needed, but this works.
    final unitsAsync = ref.watch(unitListProvider(''));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Exports')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Attendance Report Card
            Card(
              color: const Color(0xFF1E293B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.table_chart, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Attendance Report',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Date Range',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.blue.withAlpha((0.1 * 255)
                                  .round())), // Changed to withAlpha for valid syntax
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Icon(Icons.calendar_today, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Filter by Unit (Optional)',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    unitsAsync.when(
                      data: (units) {
                        return DropdownButtonFormField<String>(
                          value: _selectedUnitId,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          hint: const Text('All Units'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('All Units')),
                            ...units.map((u) => DropdownMenuItem(
                                  value: u['id'] as String,
                                  child: Text(u['name'] as String),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedUnitId = v;
                              if (v == null) {
                                _selectedUnitName = null;
                              } else {
                                final unit = units.firstWhere(
                                    (u) => u['id'] == v,
                                    orElse: () => {});
                                _selectedUnitName = unit['name'];
                              }
                            });
                          },
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (e, s) => Text('Error loading units: $e',
                          style: const TextStyle(color: Colors.red)),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _exportAttendance,
                        icon: const Icon(Icons.download),
                        label: Text(
                            _isLoading ? 'Generating...' : 'Export to Excel'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
