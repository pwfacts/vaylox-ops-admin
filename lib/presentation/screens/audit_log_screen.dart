import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/audit_repository.dart';
import 'package:intl/intl.dart';

final auditLogsProvider = FutureProvider<List<AuditLogEntry>>((ref) {
  return AuditRepository().getRecentAudits();
});

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('System Audit Trail'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: logsAsync.when(
        data: (logs) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(auditLogsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildAuditItem(log);
            },
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildAuditItem(AuditLogEntry log) {
    final isSalary = log.type == 'SALARY';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isSalary ? Colors.purpleAccent : Colors.blueAccent).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isSalary ? Icons.account_balance_wallet : Icons.fact_check,
            color: isSalary ? Colors.purpleAccent : Colors.blueAccent,
            size: 20,
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(log.action, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            Text(
              DateFormat('dd MMM, hh:mm a').format(log.timestamp),
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(log.details, style: TextStyle(color: Colors.grey[300], fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text('By: ${log.actorName}', style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
