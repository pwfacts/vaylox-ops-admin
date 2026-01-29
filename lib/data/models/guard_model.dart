import 'package:uuid/uuid.dart';

enum DutyShift { day, night, both }

class Guard {
  final String id;
  final String companyId;
  final String? userId; // Optional link to a user (e.g. supervisor)
  final String guardCode;
  final String fullName;
  final String phone;
  final String emergencyContact;
  final String aadharNumber;
  final String? panNumber;
  final DateTime dateOfBirth;
  
  // Documents
  final String? aadharFrontUrl;
  final String? aadharBackUrl;
  final String? panCardUrl;
  final String? photoUrl;
  final String? policeVerificationUrl;
  
  // Employment
  final String assignedUnitId;
  final String assignedUnitCode;
  final DutyShift dutyShift;
  final String designation;
  
  // Salary
  final double basicSalary;
  final double? otRatePerHour;
  final String otCalculationMethod;
  
  // Bank
  final String? bankName;
  final String? accountNumber;
  final String? ifscCode;
  
  // Face
  final String? faceEncoding;
  
  final String status;
  final bool isPfEnabled;
  final bool isPtEnabled;
  final bool isEsicEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  Guard({
    required this.id,
    required this.companyId,
    this.userId,
    required this.guardCode,
    required this.fullName,
    required this.phone,
    required this.emergencyContact,
    required this.aadharNumber,
    this.panNumber,
    required this.dateOfBirth,
    this.aadharFrontUrl,
    this.aadharBackUrl,
    this.panCardUrl,
    this.photoUrl,
    this.policeVerificationUrl,
    required this.assignedUnitId,
    required this.assignedUnitCode,
    required this.dutyShift,
    this.designation = 'security_guard',
    required this.basicSalary,
    this.otRatePerHour,
    this.otCalculationMethod = 'hourly',
    this.bankName,
    this.accountNumber,
    this.ifscCode,
    this.faceEncoding,
    this.status = 'active',
    this.isPfEnabled = false,
    this.isPtEnabled = false,
    this.isEsicEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Guard.fromJson(Map<String, dynamic> json) {
    return Guard(
      id: json['id'],
      companyId: json['company_id'],
      userId: json['user_id'],
      guardCode: json['guard_code'],
      fullName: json['full_name'],
      phone: json['phone'],
      emergencyContact: json['emergency_contact'],
      aadharNumber: json['aadhar_number'],
      panNumber: json['pan_number'],
      dateOfBirth: DateTime.parse(json['date_of_birth']),
      aadharFrontUrl: json['aadhar_front_url'],
      aadharBackUrl: json['aadhar_back_url'],
      panCardUrl: json['pan_card_url'],
      photoUrl: json['photo_url'],
      policeVerificationUrl: json['police_verification_url'],
      assignedUnitId: json['assigned_unit_id'],
      assigned_unit_code: json['assigned_unit_code'],
      dutyShift: DutyShift.values.firstWhere((e) => e.name == json['duty_shift']),
      designation: json['designation'],
      basicSalary: (json['basic_salary'] as num).toDouble(),
      otRatePerHour: json['ot_rate_per_hour'] != null ? (json['ot_rate_per_hour'] as num).toDouble() : null,
      otCalculationMethod: json['ot_calculation_method'],
      bankName: json['bank_name'],
      accountNumber: json['account_number'],
      ifscCode: json['ifsc_code'],
      faceEncoding: json['face_encoding'],
      status: json['status'],
      isPfEnabled: json['is_pf_enabled'] ?? false,
      isPtEnabled: json['is_pt_enabled'] ?? false,
      isEsicEnabled: json['is_esic_enabled'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'user_id': userId,
      'guard_code': guardCode,
      'full_name': fullName,
      'phone': phone,
      'emergency_contact': emergencyContact,
      'aadhar_number': aadharNumber,
      'pan_number': panNumber,
      'date_of_birth': dateOfBirth.toIso8601String(),
      'aadhar_front_url': aadharFrontUrl,
      'aadhar_back_url': aadharBackUrl,
      'pan_card_url': panCardUrl,
      'photo_url': photoUrl,
      'police_verification_url': policeVerificationUrl,
      'assigned_unit_id': assignedUnitId,
      'assigned_unit_code': assignedUnitCode,
      'duty_shift': dutyShift.name,
      'designation': designation,
      'basic_salary': basicSalary,
      'ot_rate_per_hour': otRatePerHour,
      'ot_calculation_method': otCalculationMethod,
      'bank_name': bankName,
      'account_number': accountNumber,
      'ifsc_code': ifscCode,
      'face_encoding': faceEncoding,
      'status': status,
      'is_pf_enabled': isPfEnabled,
      'is_pt_enabled': isPtEnabled,
      'is_esic_enabled': isEsicEnabled,
    };
  }
}
