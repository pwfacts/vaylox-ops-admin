import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/attendance_model.dart';
import '../../data/services/supabase_service.dart';

class MonthlyAttendanceLogScreen extends ConsumerWidget {
  final String guardId;
  final String guardName;
  final int month;
  final int year;

  const MonthlyAttendanceLogScreen({
    super.key,
    required this.guardId,
    required this.guardName,
    required this.month,
    required this.year,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(guardAttendanceLogProvider(this));

    return Scaffold(
      appBar: AppBar(title: Text('Attendance: $guardName')),
      body: attendanceAsync.when(
        data: (records) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${DateFormat('MMMM yyyy').format(DateTime(year, month))}', 
                       style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('${records.length} Duty Logs', style: const TextStyle(color: Colors.blueAccent)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: records.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return _buildLogCard(record);
                },
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildLogCard(Attendance record) {
    final bool isOt = record.type == AttendanceType.OT;
    
    return Card(
      margin: const EdgeInsets.bottom(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: isOt ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
          child: Text(
            DateFormat('dd').format(record.attendanceDate),
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              color: isOt ? Colors.orange : Colors.blueAccent
            ),
          ),
        ),
        title: Row(
          children: [
            Text(DateFormat('EEEE').format(record.attendanceDate)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(record.shift.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    record.unitName ?? 'Main Unit', 
                    style: TextStyle(
                      color: isOt ? Colors.orange : Colors.grey[400],
                      fontWeight: isOt ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
            if (record.checkInTime != null)
              Text('In: ${DateFormat('hh:mm a').format(record.checkInTime!)}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: isOt 
          ? const Tooltip(message: 'OT Duty at Different Unit', child: Icon(Icons.bolt, color: Colors.orange))
          : null,
      ),
    );
  }
}

final guardAttendanceLogProvider = FutureProvider.family<List<Attendance>, MonthlyAttendanceLogScreen>((ref, params) async {
  final client = SupabaseService().client;
  final startDate = DateTime(params.year, params.month, 1);
  final endDate = DateTime(params.year, params.month + 1, 0);

  final response = await client
      .from('attendance')
      .select('*, units(name)')
      .eq('guard_id', params.guardId)
      .eq('approval_status', 'APPROVED')
      .gte('attendance_date', startDate.toIso8601String().split('T')[0])
      .lte('attendance_date', endDate.toIso8601String().split('T')[0])
      .order('attendance_date', ascending: true);

  return (response as List).map((json) => Attendance.fromJson(json)).toList();
});
