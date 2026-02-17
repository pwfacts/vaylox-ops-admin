// import 'dart:io'; // Removed for web compatibility
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'face_registration_screen.dart';
import '../providers/guard_enrollment_provider.dart';
import '../../data/models/guard_model.dart';

import '../providers/attendance_provider.dart';
import '../providers/access_profile_provider.dart'; // Added

import 'package:logger/logger.dart';

final _logger = Logger();

class EnrollmentScreen extends ConsumerStatefulWidget {
  final Guard? guardToEdit; // Update mode if not null

  const EnrollmentScreen({super.key, this.guardToEdit});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // Controllers
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController(); // Added email controller
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
  String? _selectedUnitCode; // Track Unit Code
  String? _organizationId; // Store organization ID from profile
  final Map<String, XFile> _documents = {};

  // For update mode - keep track of existing URLs
  final Map<String, String> _existingDocumentUrls = {};

  @override
  void initState() {
    super.initState();
    if (widget.guardToEdit != null) {
      final g = widget.guardToEdit!;
      _fullNameController.text = g.fullName;
      _emailController.text = g.email ?? '';
      _phoneController.text = g.phone;
      _emergencyContactController.text = g.emergencyContact;
      _aadharNumberController.text = g.aadharNumber;
      _panNumberController.text = g.panNumber ?? '';
      _guardCodeController.text = g.guardCode;
      _basicSalaryController.text = g.basicSalary.toString();
      _bankNameController.text = g.bankName ?? '';
      _accountNumberController.text = g.accountNumber ?? '';
      _ifscCodeController.text = g.ifscCode ?? '';

      _dob = g.dateOfBirth;
      _dutyShift = g.dutyShift;
      _isPfEnabled = g.isPfEnabled;
      _isPtEnabled = g.isPtEnabled;
      _isEsicEnabled = g.isEsicEnabled;
      _selectedUnitId = g.assignedUnitId;
      _selectedUnitCode = g.assignedUnitCode;
      _faceEncoding = g.faceEncoding;

      // Load existing docs
      if (g.aadharFrontUrl != null) {
        _existingDocumentUrls['aadhar_front'] = g.aadharFrontUrl!;
      }
      if (g.aadharBackUrl != null) {
        _existingDocumentUrls['aadhar_back'] = g.aadharBackUrl!;
      }
      if (g.panCardUrl != null) {
        _existingDocumentUrls['pan_card'] = g.panCardUrl!;
      }
      if (g.photoUrl != null) _existingDocumentUrls['photo'] = g.photoUrl!;
      if (g.policeVerificationUrl != null) {
        _existingDocumentUrls['police_verification'] = g.policeVerificationUrl!;
      }
    }
  }

  Future<void> _pickImage(String type) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _documents[type] = pickedFile;
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
    // If editing, use existing org ID if strictly needed, or ensure _organizationId is set.
    // Ideally _organizationId comes from loaded profile or the guard itself.
    if (_organizationId == null && widget.guardToEdit != null) {
      _organizationId = widget.guardToEdit!.organizationId;
    }

    if (_organizationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Organization ID not loaded')),
      );
      return;
    }

    final String guardId = widget.guardToEdit?.id ?? const Uuid().v4();
    final DateTime createdAt = widget.guardToEdit?.createdAt ?? DateTime.now();

    final guard = Guard(
      id: guardId,
      organizationId: _organizationId!,
      userId: widget.guardToEdit?.userId, // Keep existing user link if any
      guardCode: _guardCodeController.text,
      fullName: _fullNameController.text,
      phone: _phoneController.text,
      email: _emailController.text.isNotEmpty ? _emailController.text : null,
      emergencyContact: _emergencyContactController.text,
      aadharNumber: _aadharNumberController.text,
      panNumber: _panNumberController.text.isNotEmpty
          ? _panNumberController.text
          : null,
      dateOfBirth: _dob!,
      // Keep existing URLs unless replaced (logic handled in repository mainly for new docs,
      // but here we pass current state's known URLs if not uploading new?)
      // Actually, Guard model holds current state. Repository update merges new docs.
      // So we should pass existing URLs here so they aren't lost if not updating documents.
      aadharFrontUrl: widget.guardToEdit?.aadharFrontUrl,
      aadharBackUrl: widget.guardToEdit?.aadharBackUrl,
      panCardUrl: widget.guardToEdit?.panCardUrl,
      photoUrl: widget.guardToEdit?.photoUrl,
      policeVerificationUrl: widget.guardToEdit?.policeVerificationUrl,

      assignedUnitId: _selectedUnitId!,
      assignedUnitCode: _selectedUnitCode ?? 'UNKNOWN',
      dutyShift: _dutyShift,
      basicSalary: double.parse(_basicSalaryController.text),
      bankName: _bankNameController.text,
      accountNumber: _accountNumberController.text,
      ifscCode: _ifscCodeController.text,
      faceEncoding: _faceEncoding ??
          widget.guardToEdit
              ?.faceEncoding, // Keep existing encoding if not re-registered
      isPfEnabled: _isPfEnabled,
      isPtEnabled: _isPtEnabled,
      isEsicEnabled: _isEsicEnabled,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      status: widget.guardToEdit?.status ?? 'active',
    );

    if (widget.guardToEdit != null) {
      ref
          .read(guardEnrollmentProvider.notifier)
          .updateGuard(guard: guard, documents: _documents);
    } else {
      ref
          .read(guardEnrollmentProvider.notifier)
          .enroll(guard: guard, documents: _documents);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentState = ref.watch(guardEnrollmentProvider);
    final profileAsync = ref.watch(accessProfileProvider);

    // Store organization ID when profile loads
    profileAsync.whenData((profile) {
      if (_organizationId == null && profile.organizationId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _organizationId = profile.organizationId;
          });
        });
      }
    });

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
      appBar: AppBar(
          title: Text(widget.guardToEdit != null
              ? 'Edit Guard'
              : 'New Guard Enrollment')),
      body: profileAsync.when(
        data: (profile) => enrollmentState.isLoading
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
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          helperText: 'Login credentials will be sent here',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Invalid Email';
                          return null;
                        },
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error loading profile: $err')),
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
        onChanged: (v) async {
          // Update selected unit ID and Code
          final unit = units.firstWhere((u) => u.id == v);
          setState(() {
            _selectedUnitId = v;
            _selectedUnitCode = unit.code;
          });

          if (v != null) {
            try {
              final repo = ref.read(guardRepositoryProvider);
              final code = await repo.generateNextGuardCode(v);
              if (mounted) {
                setState(() {
                  _guardCodeController.text = code;
                });
              }
            } catch (e) {
              _logger.e('Error generating code: $e');
            }
          }
        },
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
