import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'face_registration_screen.dart';
import '../providers/guard_enrollment_provider.dart';
import '../../data/models/guard_model.dart';
import '../../core/constants/app_constants.dart';
import '../providers/attendance_provider.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // Controllers
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _aadharNumberController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _guardCodeController = TextEditingController();
  final _basicSalaryController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _ifscCodeController = TextEditingController();

  DateTime? _dob;
  DutyShift _dutyShift = DutyShift.day;
  bool _isPfEnabled = false;
  bool _isPtEnabled = false;
  bool _isEsicEnabled = false;
  String? _selectedUnitId;
  final Map<String, File> _documents = {};

  Future<void> _pickImage(String type) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _documents[type] = File(pickedFile.path);
      });
    }
  }

  String? _faceEncoding;

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Date of Birth')),
        );
        return;
      }

      if (_faceEncoding == null) {
        // Navigate to Face Registration
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FaceRegistrationScreen(
              onFaceRegistered: (encoding, imageFile) {
                setState(() => _faceEncoding = encoding);
                _executeEnrollment();
              },
            ),
          ),
        );
      } else {
        _executeEnrollment();
      }
    }
  }

  void _executeEnrollment() {
    final guard = Guard(
      id: const Uuid().v4(),
      companyId: defaultCompanyId,
      guardCode: _guardCodeController.text,
      fullName: _fullNameController.text,
      phone: _phoneController.text,
      emergencyContact: _emergencyContactController.text,
      aadharNumber: _aadharNumberController.text,
      panNumber:
          _panNumberController.text.isEmpty ? null : _panNumberController.text,
      dateOfBirth: _dob!,
      assignedUnitId: _selectedUnitId ?? 'placeholder_unit_id',
      assignedUnitCode: 'PH',
      dutyShift: _dutyShift,
      basicSalary: double.parse(_basicSalaryController.text),
      bankName: _bankNameController.text,
      accountNumber: _accountNumberController.text,
      ifscCode: _ifscCodeController.text,
      faceEncoding: _faceEncoding,
      isPfEnabled: _isPfEnabled,
      isPtEnabled: _isPtEnabled,
      isEsicEnabled: _isEsicEnabled,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    ref
        .read(guardEnrollmentProvider.notifier)
        .enroll(guard: guard, documents: _documents);
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentState = ref.watch(guardEnrollmentProvider);

    ref.listen(guardEnrollmentProvider, (previous, next) {
      if (next.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guard enrolled successfully!')),
        );
        Navigator.pop(context);
      } else if (next.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${next.error}')));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('New Guard Enrollment')),
      body: enrollmentState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('Personal Information'),
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number *',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    ListTile(
                      title: Text(
                        _dob == null
                            ? 'Date of Birth *'
                            : 'DOB: ${DateFormat('yyyy-MM-dd').format(_dob!)}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().subtract(
                            const Duration(days: 365 * 18),
                          ),
                          firstDate: DateTime(1960),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) setState(() => _dob = date);
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Documents'),
                    _buildDocPicker('Aadhar Front', 'aadhar_front'),
                    _buildDocPicker('Aadhar Back', 'aadhar_back'),
                    _buildDocPicker('PAN Card', 'pan_card'),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Employment Details'),
                    TextFormField(
                      controller: _guardCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Guard Code (e.g., BH001) *',
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    _buildUnitSelector(),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<DutyShift>(
                      value: _dutyShift,
                      items: DutyShift.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.name.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _dutyShift = v!),
                      decoration: const InputDecoration(
                        labelText: 'Duty Shift',
                      ),
                    ),
                    TextFormField(
                      controller: _basicSalaryController,
                      decoration: const InputDecoration(
                        labelText: 'Basic Salary *',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Payroll Toggles'),
                    SwitchListTile(
                      title: const Text('Enable PF (12% of Basic)'),
                      value: _isPfEnabled,
                      onChanged: (v) => setState(() => _isPfEnabled = v),
                    ),
                    SwitchListTile(
                      title: const Text('Enable PT (Professional Tax)'),
                      subtitle: const Text(
                        'Auto-deduct ₹200 if Gross >= ₹12,000',
                      ),
                      value: _isPtEnabled,
                      onChanged: (v) => setState(() => _isPtEnabled = v),
                    ),
                    SwitchListTile(
                      title: const Text('Enable ESIC'),
                      value: _isEsicEnabled,
                      onChanged: (v) => setState(() => _isEsicEnabled = v),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: _submit,
                        child: const Text('Proceed to Face Registration'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildUnitSelector() {
    final unitsAsync = ref.watch(unitsProvider);
    return unitsAsync.when(
      data: (units) => DropdownButtonFormField<String>(
        value: _selectedUnitId,
        decoration: const InputDecoration(labelText: 'Assigned Unit *'),
        items: units
            .map((u) => DropdownMenuItem(value: u.id, child: Text(u.name)))
            .toList(),
        onChanged: (v) => setState(() => _selectedUnitId = v),
        validator: (v) => v == null ? 'Required' : null,
      ),
      loading: () => const LinearProgressIndicator(),
      error: (e, s) => Text('Error loading units: $e'),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blueAccent,
        ),
      ),
    );
  }

  Widget _buildDocPicker(String label, String key) {
    return ListTile(
      title: Text(label),
      leading: _documents.containsKey(key)
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.camera_alt),
      onTap: () => _pickImage(key),
    );
  }
}
