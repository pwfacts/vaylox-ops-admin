import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/attendance_repository.dart';

class AttendanceLogsFilter {
  final String? date;
  final String? unitId;
  final String? status; // 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'all'

  const AttendanceLogsFilter({this.date, this.unitId, this.status = 'all'});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttendanceLogsFilter &&
        other.date == date &&
        other.unitId == unitId &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(date, unitId, status);
}

final attendanceRepositoryProvider = Provider((ref) => AttendanceRepository());

final attendanceLogsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, AttendanceLogsFilter>(
        (ref, filter) async {
  return ref.read(attendanceRepositoryProvider).getAttendanceLogs(
        date: filter.date,
        unitId: filter.unitId,
        status: filter.status,
      );
});
