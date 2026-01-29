import 'package:google_maps_flutter/google_maps_flutter.dart';

enum AttendanceMethod { FACE, MANUAL_FALLBACK, SUPERVISOR }
enum FallbackReason { poor_lighting, camera_issue, face_mismatch, device_issue, other }
enum ApprovalStatus { PENDING_APPROVAL, APPROVED, REJECTED }
enum AttendanceType { NORMAL, OT }

class Attendance {
  final String id;
  final String companyId;
  final String guardId;
  final DateTime attendanceDate;
  final String shift;
  final String unitId; // Deprecated but kept for compatibility
  final String? workedUnitId;
  final String? primaryUnitId;
  final AttendanceType type;
  final String? unitName; 
  final bool isTemporaryAssignment;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final AttendanceMethod attendanceMethod;
  final bool faceVerified;
  final double? faceMatchScore;
  final FallbackReason? fallbackReason;
  final String? fallbackReasonText;
  final String? fallbackPhotoUrl;
  final ApprovalStatus approvalStatus;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? approvalNotes;
  final LatLng? gpsLocation;
  final double? gpsAccuracy;
  final bool isOt;
  final double otHours;
  final double? otRateApplied;
  final bool syncedFromOffline;
  final String? deviceId;
  final DateTime? offlineCreatedAt;
  final String? markedByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Attendance({
    required this.id,
    required this.companyId,
    required this.guardId,
    required this.attendanceDate,
    required this.shift,
    required this.unitId,
    this.workedUnitId,
    this.primaryUnitId,
    this.type = AttendanceType.NORMAL,
    this.unitName,
    this.isTemporaryAssignment = false,
    this.checkInTime,
    this.checkOutTime,
    required this.attendanceMethod,
    this.faceVerified = false,
    this.faceMatchScore,
    this.fallbackReason,
    this.fallbackReasonText,
    this.fallbackPhotoUrl,
    this.approvalStatus = ApprovalStatus.PENDING_APPROVAL,
    this.approvedBy,
    this.approvedAt,
    this.approvalNotes,
    this.gpsLocation,
    this.gpsAccuracy,
    this.isOt = false,
    this.otHours = 0,
    this.otRateApplied,
    this.syncedFromOffline = false,
    this.deviceId,
    this.offlineCreatedAt,
    this.markedByUserId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    LatLng? location;
    if (json['gps_location'] != null && json['gps_location'] is String) {
      try {
        // Simple POINT string parsing: "POINT(long lat)"
        final str = json['gps_location'] as String;
        final coords = str.split('(')[1].split(')')[0].split(' ');
        location = LatLng(double.parse(coords[1]), double.parse(coords[0]));
      } catch (_) {}
    }

    return Attendance(
      id: json['id'],
      companyId: json['company_id'],
      guardId: json['guard_id'],
      attendanceDate: DateTime.parse(json['attendance_date']),
      shift: json['shift'],
      unitId: json['unit_id'],
      workedUnitId: json['worked_unit_id'],
      primaryUnitId: json['primary_unit_id'],
      type: AttendanceType.values.firstWhere((e) => e.name == (json['type'] ?? 'NORMAL')),
      unitName: json['units']?['name'], 
      isTemporaryAssignment: json['is_temporary_assignment'] ?? false,
      checkInTime: json['check_in_time'] != null ? DateTime.parse(json['check_in_time']) : null,
      checkOutTime: json['check_out_time'] != null ? DateTime.parse(json['check_out_time']) : null,
      attendanceMethod: AttendanceMethod.values.firstWhere((e) => e.name == json['attendance_method']),
      faceVerified: json['face_verified'] ?? false,
      faceMatchScore: json['face_match_score'] != null ? (json['face_match_score'] as num).toDouble() : null,
      fallbackReason: json['fallback_reason'] != null 
          ? FallbackReason.values.firstWhere((e) => e.name == json['fallback_reason']) 
          : null,
      fallbackReasonText: json['fallback_reason_text'],
      fallbackPhotoUrl: json['fallback_photo_url'],
      approvalStatus: ApprovalStatus.values.firstWhere((e) => e.name == json['approval_status']),
      approvedBy: json['approved_by'],
      approvedAt: json['approved_at'] != null ? DateTime.parse(json['approved_at']) : null,
      approvalNotes: json['approval_notes'],
      gpsLocation: location,
      gpsAccuracy: json['gps_accuracy'] != null ? (json['gps_accuracy'] as num).toDouble() : null,
      isOt: json['is_ot'] ?? false,
      otHours: (json['ot_hours'] as num? ?? 0).toDouble(),
      otRateApplied: json['ot_rate_applied'] != null ? (json['ot_rate_applied'] as num).toDouble() : null,
      syncedFromOffline: json['synced_from_offline'] ?? false,
      deviceId: json['device_id'],
      offlineCreatedAt: json['offline_created_at'] != null ? DateTime.parse(json['offline_created_at']) : null,
      markedByUserId: json['marked_by_user_id'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'guard_id': guardId,
      'attendance_date': attendanceDate.toIso8601String().split('T')[0],
      'shift': shift,
      'unit_id': unitId,
      'worked_unit_id': workedUnitId ?? unitId,
      'primary_unit_id': primaryUnitId,
      'type': type.name,
      'is_temporary_assignment': isTemporaryAssignment,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'attendance_method': attendanceMethod.name,
      'face_verified': faceVerified,
      'face_match_score': faceMatchScore,
      'fallback_reason': fallbackReason?.name,
      'fallback_reason_text': fallbackReasonText,
      'fallback_photo_url': fallbackPhotoUrl,
      'approval_status': approvalStatus.name,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'approval_notes': approvalNotes,
      'gps_location': gpsLocation != null 
          ? 'POINT(${gpsLocation!.longitude} ${gpsLocation!.latitude})' 
          : null,
      'gps_accuracy': gpsAccuracy,
      'is_ot': isOt,
      'ot_hours': otHours,
      'ot_rate_applied': otRateApplied,
      'synced_from_offline': syncedFromOffline,
      'device_id': deviceId,
      'offline_created_at': offlineCreatedAt?.toIso8601String(),
      'marked_by_user_id': markedByUserId,
    };
  }
}
