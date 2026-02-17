import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/guard_model.dart';
import 'package:intl/intl.dart';
import 'enrollment_screen.dart';

class GuardProfileScreen extends ConsumerWidget {
  final Guard guard;

  const GuardProfileScreen({super.key, required this.guard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guard Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EnrollmentScreen(guardToEdit: guard),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: guard.photoUrl != null
                        ? NetworkImage(guard.photoUrl!)
                        : null,
                    child: guard.photoUrl == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    guard.fullName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    guard.guardCode,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(guard.status.toUpperCase()),
                    backgroundColor: guard.status == 'active'
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    labelStyle: TextStyle(
                      color:
                          guard.status == 'active' ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Personal Information'),
            _buildInfoRow('Phone', guard.phone),
            _buildInfoRow('Email', guard.email ?? 'N/A'),
            _buildInfoRow('Date of Birth',
                DateFormat('dd MMM yyyy').format(guard.dateOfBirth)),
            _buildInfoRow('Aadhar Number', guard.aadharNumber),
            _buildInfoRow('PAN Number', guard.panNumber ?? 'N/A'),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Employment Details'),
            _buildInfoRow('Designation', guard.designation),
            _buildInfoRow('Assigned Unit', guard.assignedUnitCode),
            _buildInfoRow('Duty Shift', guard.dutyShift.name.toUpperCase()),
            _buildInfoRow('Basic Salary', '₹${guard.basicSalary}'),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Bank Details'),
            _buildInfoRow('Bank Name', guard.bankName ?? 'N/A'),
            _buildInfoRow('Account Number', guard.accountNumber ?? 'N/A'),
            _buildInfoRow('IFSC Code', guard.ifscCode ?? 'N/A'),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Documents'),
            Wrap(
              spacing: 8,
              children: [
                if (guard.aadharFrontUrl != null)
                  _buildDocumentChip(
                      context, 'Aadhar Front', guard.aadharFrontUrl!),
                if (guard.aadharBackUrl != null)
                  _buildDocumentChip(
                      context, 'Aadhar Back', guard.aadharBackUrl!),
                if (guard.panCardUrl != null)
                  _buildDocumentChip(context, 'PAN Card', guard.panCardUrl!),
                if (guard.policeVerificationUrl != null)
                  _buildDocumentChip(context, 'Police Verification',
                      guard.policeVerificationUrl!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
        ),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentChip(BuildContext context, String label, String url) {
    return ActionChip(
      avatar: const Icon(Icons.description, size: 16),
      label: Text(label),
      onPressed: () {
        // Show image dialog
        showDialog(
            context: context,
            builder: (ctx) => Dialog(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppBar(
                      title: Text(label),
                      leading: const CloseButton(),
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      foregroundColor: Colors.black,
                    ), // Improved AppBar
                    Flexible(
                      // Use Flexible instead of Expanded for Dialog
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.network(url, fit: BoxFit.contain),
                      ),
                    ),
                  ],
                )));
      },
    );
  }
}
