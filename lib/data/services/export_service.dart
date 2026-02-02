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
      backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'),
      fontFamily: getFontFamily(FontFamily.Arial),
    );

    final List<CellValue?> headers = [
      TextCellValue('Guard Code'),
      TextCellValue('Full Name'),
      TextCellValue('Designation'),
      TextCellValue('Bank Name'),
      TextCellValue('A/C Number'),
      TextCellValue('IFSC'),
      TextCellValue('Target Days'),
      TextCellValue('Present Days'),
      TextCellValue('OT Days'),
      TextCellValue('Basic Rate'),
      TextCellValue('Earned Basic'),
      TextCellValue('OT Pay'),
      TextCellValue('HRA'),
      TextCellValue('Other Earnings'),
      TextCellValue('Gross Pay'),
      TextCellValue('PF (12%)'),
      TextCellValue('ESIC (0.75%)'),
      TextCellValue('PT'),
      TextCellValue('LWF'),
      TextCellValue('Advance'),
      TextCellValue('Penalty'),
      TextCellValue('Canteen'),
      TextCellValue('Uniform'),
      TextCellValue('Other Ded 1'),
      TextCellValue('Other Ded 2'),
      TextCellValue('Total Deductions'),
      TextCellValue('Net Payable'),
      TextCellValue('Audit Note'),
      TextCellValue('Override By'),
    ];

    sheet1.appendRow(headers);
    for (var i = 0; i < headers.length; i++) {
      sheet1
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
              .cellStyle =
          headerStyle;
    }

    for (var slip in slips) {
      final guard = guards.firstWhere((g) => g.id == slip.guardId);

      sheet1.appendRow([
        TextCellValue(guard.guardCode),
        TextCellValue(guard.fullName),
        TextCellValue(guard.designation),
        TextCellValue(guard.bankName ?? '-'),
        TextCellValue(guard.accountNumber ?? '-'),
        TextCellValue(guard.ifscCode ?? '-'),
        IntCellValue(slip.totalWorkingDays),
        IntCellValue(slip.presentDays),
        TextCellValue(
          slip.otPay > 0
              ? (slip.otPay / (slip.basicPay / slip.totalWorkingDays))
                    .toStringAsFixed(1)
              : '0',
        ),
        DoubleCellValue(slip.basicPay),
        DoubleCellValue(slip.earnedBasic),
        DoubleCellValue(slip.otPay),
        DoubleCellValue(slip.hra),
        DoubleCellValue(slip.otherEarnings),
        DoubleCellValue(slip.grossPay),
        DoubleCellValue(slip.pfDeduction),
        DoubleCellValue(slip.esicDeduction),
        DoubleCellValue(slip.ptDeduction),
        DoubleCellValue(slip.lwfDeduction),
        DoubleCellValue(slip.advanceDeduction),
        DoubleCellValue(slip.penaltyDeduction),
        DoubleCellValue(slip.canteenDeduction),
        DoubleCellValue(slip.uniformDeduction),
        DoubleCellValue(slip.otherDed1),
        DoubleCellValue(slip.otherDed2),
        DoubleCellValue(slip.totalDeductions),
        DoubleCellValue(slip.netPay),
        TextCellValue(slip.manualOverrideNote ?? ''),
        TextCellValue(slip.manualOverrideBy ?? ''),
      ]);
    }

    // 2. Bank Transfer List Sheet
    final Sheet sheet2 = excel['Bank Transfer List'];
    final List<CellValue?> bankHeaders = [
      TextCellValue('S.No'),
      TextCellValue('Employee Name'),
      TextCellValue('Account Number'),
      TextCellValue('IFSC Code'),
      TextCellValue('Amount'),
      TextCellValue('Remarks'),
    ];

    sheet2.appendRow(bankHeaders);
    for (var i = 0; i < bankHeaders.length; i++) {
      sheet2
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
              .cellStyle =
          headerStyle;
    }

    int serial = 1;
    for (var slip in slips) {
      final guard = guards.firstWhere((g) => g.id == slip.guardId);
      sheet2.appendRow([
        IntCellValue(serial++),
        TextCellValue(guard.fullName),
        TextCellValue(guard.accountNumber ?? '-'),
        TextCellValue(guard.ifscCode ?? '-'),
        DoubleCellValue(slip.netPay),
        TextCellValue(
          'Salary ${DateFormat('MMM yyyy').format(DateTime(year, month))}',
        ),
      ]);
    }

    // 3. Save and Share
    final fileBytes = excel.save();
    if (fileBytes == null) return;

    final fileName =
        'Payroll_${unitName.replaceAll(' ', '_')}_${DateFormat('MMM_yyyy').format(DateTime(year, month))}.xlsx';

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(fileBytes);

    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Monthly Payroll for $unitName');
  }
}
