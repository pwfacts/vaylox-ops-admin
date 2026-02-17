enum CorrectionType {
  timeAdjustment,
  unitChange,
  voidCorrection,
  approvalOverride,
  otAdjustment,
}

enum CorrectionStatus {
  pending,
  approved,
  rejected,
}

class AttendanceCorrection {
  final String id;
  final String organizationId;
  final String attendanceId;
  final CorrectionType correctionType;
  final String? fieldChanged;
  final String? oldValue;
  final String? newValue;
  final String reason;
  final String requestedBy;
  final DateTime requestedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final CorrectionStatus correctionStatus;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  AttendanceCorrection({
    required this.id,
    required this.organizationId,
    required this.attendanceId,
    required this.correctionType,
    this.fieldChanged,
    this.oldValue,
    this.newValue,
    required this.reason,
    required this.requestedBy,
    required this.requestedAt,
    this.approvedBy,
    this.approvedAt,
    this.correctionStatus = CorrectionStatus.pending,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AttendanceCorrection.fromJson(Map<String, dynamic> json) {
    return AttendanceCorrection(
      id: json['id'],
      organizationId: json['organization_id'],
      attendanceId: json['attendance_id'],
      correctionType: CorrectionType.values.firstWhere(
        (e) =>
            e.name.toUpperCase() ==
            (json['correction_type'] as String).replaceAll('_', ''),
        orElse: () => CorrectionType.timeAdjustment,
      ),
      fieldChanged: json['field_changed'],
      oldValue: json['old_value'],
      newValue: json['new_value'],
      reason: json['reason'],
      requestedBy: json['requested_by'],
      requestedAt: DateTime.parse(json['requested_at']),
      approvedBy: json['approved_by'],
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'])
          : null,
      correctionStatus: CorrectionStatus.values.firstWhere(
        (e) => e.name.toUpperCase() == json['correction_status'],
        orElse: () => CorrectionStatus.pending,
      ),
      rejectionReason: json['rejection_reason'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'attendance_id': attendanceId,
      'correction_type': correctionType.name.toUpperCase().replaceAll(
            RegExp(r'([a-z])([A-Z])'),
            r'$1_$2',
          ),
      'field_changed': fieldChanged,
      'old_value': oldValue,
      'new_value': newValue,
      'reason': reason,
      'requested_by': requestedBy,
      'requested_at': requestedAt.toIso8601String(),
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'correction_status': correctionStatus.name.toUpperCase(),
      'rejection_reason': rejectionReason,
    };
  }
}
