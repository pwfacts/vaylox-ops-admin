import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/salary_slip_model.dart';
import '../models/guard_model.dart';

class ExportService {
  Future<void> exportMonthlyPayroll({
    required List<SalarySlip> slips,
    required List<Guard> guards,
    required String unitName,
    required int month,
    required int year,
  }) async {
    final excel = Excel.createExcel();
    
    // 1. Detailed Salary Register Sheet
    final Sheet sheet1 = excel['Salary Register'];
    excel.delete('Sheet1'); // Remove default sheet

    // Header styling
    final CellStyle headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: '#E0E0E0',
      fontFamily: getFontFamily(FontFamily.Arial),
    );

    final List<String> headers = [
      'Guard Code', 'Full Name', 'Designation', 
      'Bank Name', 'A/C Number', 'IFSC',
      'Target Days', 'Present Days', 'OT Days',
      'Basic Rate', 'Earned Basic', 'OT Pay', 'HRA', 'Other Earnings',
      'Gross Pay',
      'PF (12%)', 'ESIC (0.75%)', 'PT', 'LWF',
      'Advance', 'Penalty', 'Canteen', 'Uniform', 'Other Ded 1', 'Other Ded 2',
      'Total Deductions', 'Net Payable',
      'Audit Note', 'Override By'
    ];

    sheet1.appendRow(headers);
    for (var i = 0; i < headers.length; i++) {
       sheet1.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = headerStyle;
    }

    for (var slip in slips) {
      final guard = guards.firstWhere((g) => g.id == slip.guardId);
      
      sheet1.appendRow([
        guard.guardCode,
        guard.fullName,
        guard.designation,
        guard.bankName ?? '-',
        guard.accountNumber ?? '-',
        guard.ifscCode ?? '-',
        slip.totalWorkingDays,
        slip.presentDays,
        slip.otPay > 0 ? (slip.otPay / (slip.basicPay / slip.totalWorkingDays)).toStringAsFixed(1) : '0',
        slip.basicPay,
        slip.earnedBasic,
        slip.otPay,
        slip.hra,
        slip.otherEarnings,
        slip.grossPay,
        slip.pfDeduction,
        slip.esicDeduction,
        slip.ptDeduction,
        slip.lwfDeduction,
        slip.advanceDeduction,
        slip.penaltyDeduction,
        slip.canteenDeduction,
        slip.uniformDeduction,
        slip.otherDed1,
        slip.otherDed2,
        slip.totalDeductions,
        slip.netPay,
        slip.manualOverrideNote ?? '',
        slip.manualOverrideBy ?? '',
      ]);
    }

    // 2. Bank Transfer List Sheet
    final Sheet sheet2 = excel['Bank Transfer List'];
    final List<String> bankHeaders = [
      'S.No', 'Employee Name', 'Account Number', 'IFSC Code', 'Amount', 'Remarks'
    ];
    
    sheet2.appendRow(bankHeaders);
    for (var i = 0; i < bankHeaders.length; i++) {
       sheet2.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = headerStyle;
    }

    int serial = 1;
    for (var slip in slips) {
      final guard = guards.firstWhere((g) => g.id == slip.guardId);
      sheet2.appendRow([
        serial++,
        guard.fullName,
        guard.accountNumber ?? '-',
        guard.ifscCode ?? '-',
        slip.netPay,
        'Salary ${DateFormat('MMM yyyy').format(DateTime(year, month))}'
      ]);
    }

    // 3. Save and Share
    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final fileName = 'Payroll_${unitName.replaceAll(' ', '_')}_${DateFormat('MMM_yyyy').format(DateTime(year, month))}.xlsx';
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(fileBytes);

    await Share.shareXFiles([XFile(file.path)], text: 'Monthly Payroll for $unitName');
  }
}
