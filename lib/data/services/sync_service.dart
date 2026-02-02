import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../repositories/attendance_repository.dart';
import '../services/local_database_service.dart';
import '../models/attendance_model.dart';

class SyncService {
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final AttendanceRepository _attendanceRepo = AttendanceRepository();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isSyncing = false;

  void start() {
    debugPrint('Sync Service Started');
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

      debugPrint('Syncing ${pendingRecords.length} records...');

      for (var record in pendingRecords) {
        try {
          final String localId = record['id'];
          final Map<String, dynamic> data = jsonDecode(
            record['attendance_data'],
          );

          // Create Attendance object
          final attendance = Attendance.fromJson(data);

          // Push to Supabase
          await _attendanceRepo.markAttendance(
            attendance: attendance,
            isOffline: false,
          );

          // Update local status
          await _localDb.updateSyncStatus(localId, 'SYNCED');
          debugPrint('Synced record $localId');
        } catch (e) {
          debugPrint('Failed to sync record: $e');
          await _localDb.updateSyncStatus(
            record['id'],
            'FAILED',
            error: e.toString(),
          );
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
