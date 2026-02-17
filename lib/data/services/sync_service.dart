import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';
import '../repositories/attendance_repository.dart';
import '../services/local_database_service.dart';
import '../models/attendance_model.dart'; // Corrected import path assuming current dir structure

final _logger = Logger();

class SyncService {
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final AttendanceRepository _attendanceRepo =
      AttendanceRepository(); // Make sure this is instantiated correctly
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isSyncing = false;

  void start() {
    _logger.i('Sync Service Started');
    _subscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        _triggerSync();
      }
    });

    // Initial check
    _triggerSync();
  }

  void stop() {
    _subscription?.cancel();
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pendingRecords = await _localDb.getPendingSync();
      if (pendingRecords.isEmpty) {
        _isSyncing = false;
        return;
      }

      _logger.i('Syncing ${pendingRecords.length} records...');

      for (var record in pendingRecords) {
        try {
          // Assuming record is Map<String, dynamic>
          final String localId = record['id'] as String;
          final String attendanceDataStr = record['attendance_data'] as String;
          final Map<String, dynamic> data = jsonDecode(attendanceDataStr);

          // Create Attendance object
          final attendance = Attendance.fromJson(data);

          // Push to Supabase
          await _attendanceRepo.markAttendance(
            attendance: attendance,
            primaryUnitId: data['primary_unit_id'] ??
                data['unit_id'], // Fallback to unit_id
            workedUnitId: data['worked_unit_id'] ??
                data['unit_id'], // Fallback to unit_id
            isOffline: false,
          );

          // Update local status
          await _localDb.updateSyncStatus(localId, 'SYNCED');
          _logger.i('Synced record $localId');
        } catch (e) {
          _logger.e('Failed to sync record: $e');
          await _localDb.updateSyncStatus(
            record['id'],
            'FAILED',
            error: e.toString(),
          );
        }
      }
    } catch (e) {
      _logger.e('Sync process error: $e');
    } finally {
      // Use finally to ensure flag is reset
      _isSyncing = false;
    }
  }
}
