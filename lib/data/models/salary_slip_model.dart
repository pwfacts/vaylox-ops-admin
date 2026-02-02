class SalarySlip {
  final String id;
  final String companyId;
  final String guardId;
  final int month;
  final int year;

  // Earnings
  final int totalWorkingDays;
  final int presentDays;
  final int absentDays;
  final double basicPay;
  final double otPay;
  final double otherAllowances;
  final double grossPay;

  // Deductions
  final double pfDeduction;
  final double esicDeduction;
  final double ptDeduction;
  final double lwfDeduction;
  final double advanceDeduction;
  final double uniformDeduction;
  final double penaltyDeduction;
  final double canteenDeduction;
  final double otherDed1;
  final double otherDed2;
  final double totalDeductions;

  // Final
  final double netPay;

  // Getters for export/pdf
  double get earnedBasic => (basicPay / totalWorkingDays) * presentDays;
  double get hra => 0.0; // Placeholder or calculate if needed
  double get otherEarnings => otherAllowances;

  final String status;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? remarks;

  // Audit Trail
  final String? manualOverrideBy;
  final DateTime? manualOverrideAt;
  final String? manualOverrideNote;
  final int? attendanceSuggestedDays;
  final int? attendanceSuggestedOtDays;

  final DateTime createdAt;
  final DateTime updatedAt;

  SalarySlip({
    required this.id,
    required this.companyId,
    required this.guardId,
    required this.month,
    required this.year,
    required this.totalWorkingDays,
    required this.presentDays,
    required this.absentDays,
    required this.basicPay,
    required this.otPay,
    required this.otherAllowances,
    required this.grossPay,
    required this.pfDeduction,
    required this.esicDeduction,
    required this.ptDeduction,
    required this.lwfDeduction,
    required this.advanceDeduction,
    required this.uniformDeduction,
    required this.penaltyDeduction,
    required this.canteenDeduction,
    required this.otherDed1,
    required this.otherDed2,
    required this.totalDeductions,
    required this.netPay,
    this.status = 'DRAFT',
    this.paymentDate,
    this.paymentMethod,
    this.remarks,
    this.manualOverrideBy,
    this.manualOverrideAt,
    this.manualOverrideNote,
    this.attendanceSuggestedDays,
    this.attendanceSuggestedOtDays,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SalarySlip.fromJson(Map<String, dynamic> json) {
    return SalarySlip(
      id: json['id'],
      companyId: json['company_id'],
      guardId: json['guard_id'],
      month: json['month'],
      year: json['year'],
      totalWorkingDays: json['total_working_days'] ?? 0,
      presentDays: json['present_days'] ?? 0,
      absentDays: json['absent_days'] ?? 0,
      basicPay: (json['basic_pay'] as num).toDouble(),
      otPay: (json['ot_pay'] as num? ?? 0).toDouble(),
      otherAllowances: (json['other_allowances'] as num? ?? 0).toDouble(),
      grossPay: (json['gross_pay'] as num).toDouble(),
      pfDeduction: (json['pf_deduction'] as num? ?? 0).toDouble(),
      esicDeduction: (json['esic_deduction'] as num? ?? 0).toDouble(),
      ptDeduction: (json['pt_deduction'] as num? ?? 0).toDouble(),
      lwfDeduction: (json['lwf_deduction'] as num? ?? 0).toDouble(),
      advanceDeduction: (json['advance_deduction'] as num? ?? 0).toDouble(),
      uniformDeduction: (json['uniform_deduction'] as num? ?? 0).toDouble(),
      penaltyDeduction: (json['penalty_deduction'] as num? ?? 0).toDouble(),
      canteenDeduction: (json['canteen_deduction'] as num? ?? 0).toDouble(),
      otherDed1: (json['other_ded_1'] as num? ?? 0).toDouble(),
      otherDed2: (json['other_ded_2'] as num? ?? 0).toDouble(),
      totalDeductions: (json['total_deductions'] as num).toDouble(),
      netPay: (json['net_pay'] as num).toDouble(),
      status: json['status'] ?? 'DRAFT',
      paymentDate: json['payment_date'] != null
          ? DateTime.parse(json['payment_date'])
          : null,
      paymentMethod: json['payment_method'],
      remarks: json['remarks'],
      manualOverrideBy: json['manual_override_by'],
      manualOverrideAt: json['manual_override_at'] != null
          ? DateTime.parse(json['manual_override_at'])
          : null,
      manualOverrideNote: json['manual_override_note'],
      attendanceSuggestedDays: json['attendance_suggested_days'],
      attendanceSuggestedOtDays: json['attendance_suggested_ot_days'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'guard_id': guardId,
      'month': month,
      'year': year,
      'total_working_days': totalWorkingDays,
      'present_days': presentDays,
      'absent_days': absentDays,
      'basic_pay': basicPay,
      'ot_pay': otPay,
      'other_allowances': otherAllowances,
      'gross_pay': grossPay,
      'pf_deduction': pfDeduction,
      'esic_deduction': esicDeduction,
      'pt_deduction': ptDeduction,
      'lwf_deduction': lwfDeduction,
      'advance_deduction': advanceDeduction,
      'uniform_deduction': uniformDeduction,
      'penalty_deduction': penaltyDeduction,
      'canteen_deduction': canteenDeduction,
      'other_ded_1': otherDed1,
      'other_ded_2': otherDed2,
      'total_deductions': totalDeductions,
      'net_pay': netPay,
      'status': status,
      'payment_date': paymentDate?.toIso8601String().split('T')[0],
      'payment_method': paymentMethod,
      'remarks': remarks,
      'manual_override_by': manualOverrideBy,
      'manual_override_at': manualOverrideAt?.toIso8601String(),
      'manual_override_note': manualOverrideNote,
      'attendance_suggested_days': attendanceSuggestedDays,
      'attendance_suggested_ot_days': attendanceSuggestedOtDays,
    };
  }

  SalarySlip copyWith({
    String? id,
    String? companyId,
    String? guardId,
    int? month,
    int? year,
    int? totalWorkingDays,
    int? presentDays,
    int? absentDays,
    double? basicPay,
    double? otPay,
    double? otherAllowances,
    double? grossPay,
    double? pfDeduction,
    double? esicDeduction,
    double? ptDeduction,
    double? lwfDeduction,
    double? advanceDeduction,
    double? uniformDeduction,
    double? penaltyDeduction,
    double? canteenDeduction,
    double? otherDed1,
    double? otherDed2,
    double? totalDeductions,
    double? netPay,
    String? status,
    DateTime? paymentDate,
    String? paymentMethod,
    String? remarks,
    String? manualOverrideBy,
    DateTime? manualOverrideAt,
    String? manualOverrideNote,
    int? attendanceSuggestedDays,
    int? attendanceSuggestedOtDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SalarySlip(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      guardId: guardId ?? this.guardId,
      month: month ?? this.month,
      year: year ?? this.year,
      totalWorkingDays: totalWorkingDays ?? this.totalWorkingDays,
      presentDays: presentDays ?? this.presentDays,
      absentDays: absentDays ?? this.absentDays,
      basicPay: basicPay ?? this.basicPay,
      otPay: otPay ?? this.otPay,
      otherAllowances: otherAllowances ?? this.otherAllowances,
      grossPay: grossPay ?? this.grossPay,
      pfDeduction: pfDeduction ?? this.pfDeduction,
      esicDeduction: esicDeduction ?? this.esicDeduction,
      ptDeduction: ptDeduction ?? this.ptDeduction,
      lwfDeduction: lwfDeduction ?? this.lwfDeduction,
      advanceDeduction: advanceDeduction ?? this.advanceDeduction,
      uniformDeduction: uniformDeduction ?? this.uniformDeduction,
      penaltyDeduction: penaltyDeduction ?? this.penaltyDeduction,
      canteenDeduction: canteenDeduction ?? this.canteenDeduction,
      otherDed1: otherDed1 ?? this.otherDed1,
      otherDed2: otherDed2 ?? this.otherDed2,
      totalDeductions: totalDeductions ?? this.totalDeductions,
      netPay: netPay ?? this.netPay,
      status: status ?? this.status,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      remarks: remarks ?? this.remarks,
      manualOverrideBy: manualOverrideBy ?? this.manualOverrideBy,
      manualOverrideAt: manualOverrideAt ?? this.manualOverrideAt,
      manualOverrideNote: manualOverrideNote ?? this.manualOverrideNote,
      attendanceSuggestedDays:
          attendanceSuggestedDays ?? this.attendanceSuggestedDays,
      attendanceSuggestedOtDays:
          attendanceSuggestedOtDays ?? this.attendanceSuggestedOtDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
