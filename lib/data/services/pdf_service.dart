import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/salary_slip_model.dart';
import '../models/guard_model.dart';

class PdfService {
  Future<void> generateAndPrintSlip({
    required SalarySlip slip,
    required Guard guard,
    required String companyName,
  }) async {
    final pdf = pw.Document();

    final font = await PdfGoogleFonts.interRegular();
    final boldFont = await PdfGoogleFonts.interBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 24,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.Text(
                        'Monthly Salary Slip',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 14,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Month: ${DateFormat('MMMM yyyy').format(DateTime(slip.year, slip.month))}',
                        style: pw.TextStyle(font: boldFont, fontSize: 12),
                      ),
                      pw.Text(
                        'Slip ID: ${slip.id.substring(0, 8).toUpperCase()}',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 2, color: PdfColors.blue900),
              pw.SizedBox(height: 10),

              // Guard Details
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: _buildInfoColumn(
                      'Employee Details',
                      [
                        'Name: ${guard.fullName}',
                        'Guard Code: ${guard.guardCode}',
                        'Designation: ${guard.designation.replaceAll('_', ' ').toUpperCase()}',
                        'Unit: ${guard.assignedUnitCode}',
                      ],
                      font,
                      boldFont,
                    ),
                  ),
                  pw.Expanded(
                    child: _buildInfoColumn(
                      'Bank Details',
                      [
                        'Bank: ${guard.bankName ?? '-'}',
                        'A/C No: ${guard.accountNumber ?? '-'}',
                        'IFSC: ${guard.ifscCode ?? '-'}',
                        'PAN: ${guard.panNumber ?? '-'}',
                      ],
                      font,
                      boldFont,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Attendance Summary Table
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(
                  font: boldFont,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue900,
                ),
                cellStyle: pw.TextStyle(font: font),
                headers: [
                  'Total Days',
                  'Present Days',
                  'OT Days (Calculated)',
                  'Basic Rate',
                ],
                data: [
                  [
                    slip.totalWorkingDays.toString(),
                    slip.presentDays.toString(),
                    (slip.otPay > 0
                        ? (slip.otPay / (slip.basicPay / slip.totalWorkingDays))
                              .toStringAsFixed(1)
                        : '0'),
                    'Rs. ${slip.basicPay.toStringAsFixed(0)}',
                  ],
                ],
              ),
              pw.SizedBox(height: 30),

              // Earnings and Deductions
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Earnings Table
                  pw.Expanded(
                    child: _buildTransactionTable(
                      'EARNINGS',
                      [
                        ['Basic Salary', slip.earnedBasic.toStringAsFixed(2)],
                        ['Overtime (OT)', slip.otPay.toStringAsFixed(2)],
                        ['HRA', slip.hra.toStringAsFixed(2)],
                        [
                          'Other Earnings',
                          slip.otherEarnings.toStringAsFixed(2),
                        ],
                      ],
                      PdfColors.green900,
                      font,
                      boldFont,
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  // Deductions Table
                  pw.Expanded(
                    child: _buildTransactionTable(
                      'DEDUCTIONS',
                      [
                        ['PF (12%)', slip.pfDeduction.toStringAsFixed(2)],
                        ['ESIC', slip.esicDeduction.toStringAsFixed(2)],
                        ['PT', slip.ptDeduction.toStringAsFixed(2)],
                        ['LWF', slip.lwfDeduction.toStringAsFixed(2)],
                        ['Advance', slip.advanceDeduction.toStringAsFixed(2)],
                        ['Penalty', slip.penaltyDeduction.toStringAsFixed(2)],
                        ['Canteen', slip.canteenDeduction.toStringAsFixed(2)],
                        ['Uniform', slip.uniformDeduction.toStringAsFixed(2)],
                      ],
                      PdfColors.red900,
                      font,
                      boldFont,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Totals
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border(
                    top: pw.BorderSide(width: 1),
                    bottom: pw.BorderSide(width: 1),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Gross: Rs. ${slip.grossPay.toStringAsFixed(2)}',
                      style: pw.TextStyle(font: boldFont),
                    ),
                    pw.Text(
                      'Total Deductions: Rs. ${slip.totalDeductions.toStringAsFixed(2)}',
                      style: pw.TextStyle(font: boldFont),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              // Net Pay
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'NET PAYABLE',
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      'Rs. ${slip.netPay.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 24,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.Text(
                      '(Rupees ${slip.netPay.toStringAsFixed(2)} only)',
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 10,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated by JDS Management System',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                  pw.Text(
                    'Computer Generated - No Signature Required',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _buildInfoColumn(
    String title,
    List<String> items,
    pw.Font font,
    pw.Font boldFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: 10,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 4),
        ...items.map(
          (item) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1),
            child: pw.Text(item, style: pw.TextStyle(font: font, fontSize: 10)),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildTransactionTable(
    String title,
    List<List<String>> data,
    PdfColor accentColor,
    pw.Font font,
    pw.Font boldFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(font: boldFont, fontSize: 10, color: accentColor),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: data
              .map(
                (row) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        row[0],
                        style: pw.TextStyle(font: font, fontSize: 9),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        row[1],
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(font: font, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
