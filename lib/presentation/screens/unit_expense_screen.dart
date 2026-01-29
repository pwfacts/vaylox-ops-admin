import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/supabase_service.dart';
import 'package:intl/intl.dart';

final unitExpensesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = SupabaseService().client;
  final now = DateTime.now();

  // Fetch salary slips grouped by unit
  // join with guards to get unit_name (or assigned_unit_id)
  final response = await client
      .from('salary_slips')
      .select('net_pay, gross_pay, pf_deduction, esic_deduction, guards(assigned_unit_id, units(name))')
      .eq('month', now.month)
      .eq('year', now.year);

  final Map<String, Map<String, dynamic>> grouped = {};

  for (var row in (response as List)) {
    final unitData = row['guards']['units'];
    if (unitData == null) continue;
    
    final unitName = unitData['name'];
    
    grouped.putIfAbsent(unitName, () => {
      'name': unitName,
      'totalNet': 0.0,
      'totalGross': 0.0,
      'totalPf': 0.0,
      'count': 0,
    });

    grouped[unitName]!['totalNet'] += (row['net_pay'] as num).toDouble();
    grouped[unitName]!['totalGross'] += (row['gross_pay'] as num).toDouble();
    grouped[unitName]!['totalPf'] += (row['pf_deduction'] as num).toDouble();
    grouped[unitName]!['count']++;
  }

  return grouped.values.toList();
});

class UnitExpenseScreen extends ConsumerWidget {
  const UnitExpenseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(unitExpensesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Unit-wise Financials'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: expensesAsync.when(
        data: (data) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Financial Summary for ${DateFormat('MMMM yyyy').format(DateTime.now())}',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ...data.map((unit) => _buildUnitCard(unit)).toList(),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildUnitCard(Map<String, dynamic> unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(unit['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text('${unit['count']} Guards', style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildRow('Gross Billing (Estimated)', '₹${NumberFormat('#,##,###').format(unit['totalGross'])}', Colors.grey[400]!),
          const SizedBox(height: 8),
          _buildRow('Statutory Co. (PF/ESIC)', '₹${NumberFormat('#,##,###').format(unit['totalPf'])}', Colors.orangeAccent),
          const Divider(height: 24, color: Colors.white10),
          _buildRow('Net Payout', '₹${NumberFormat('#,##,###').format(unit['totalNet'])}', Colors.greenAccent, isBold: true),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }
}
