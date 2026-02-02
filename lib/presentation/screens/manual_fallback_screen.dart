import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/attendance_model.dart';
import '../../data/models/guard_model.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/services/imagekit_service.dart';
import '../../data/services/supabase_service.dart';
import '../widgets/animated_button.dart';

class ManualFallbackScreen extends StatefulWidget {
  final Guard profile;
  final LatLng location;
  final double accuracy;
  final String shift;
  final String? workedUnitId;
  final String? primaryUnitId;
  final AttendanceType attendanceType;

  const ManualFallbackScreen({
    super.key,
    required this.profile,
    required this.location,
    required this.accuracy,
    required this.shift,
    this.workedUnitId,
    this.primaryUnitId,
    this.attendanceType = AttendanceType.normal,
  });

  @override
  State<ManualFallbackScreen> createState() => _ManualFallbackScreenState();
}

class _ManualFallbackScreenState extends State<ManualFallbackScreen> {
  final _picker = ImagePicker();
  final _imageKit = ImageKitService();
  final _repository = AttendanceRepository();

  File? _fallbackPhoto;
  FallbackReason _reason = FallbackReason.poorLighting;
  final _reasonTextController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _capturePhoto() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (image != null) {
      setState(() => _fallbackPhoto = File(image.path));
    }
  }

  Future<void> _submit() async {
    if (_fallbackPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Live photo is mandatory for manual fallback.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. Upload photo to ImageKit
      final photoName =
          'fallback_${widget.profile.guardCode}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final uploadResult = await _imageKit.uploadImage(
        fileBytes: await _fallbackPhoto!.readAsBytes(),
        fileName: photoName,
        folder: 'attendance/fallbacks',
      );

      // 2. Create Attendance record
      final attendance = Attendance(
        id: const Uuid().v4(),
        companyId: defaultCompanyId,
        guardId: widget.profile.id,
        attendanceDate: DateTime.now(),
        shift: widget.shift,
        unitId: widget.workedUnitId ?? widget.profile.assignedUnitId,
        workedUnitId: widget.workedUnitId,
        primaryUnitId: widget.primaryUnitId,
        type: widget.attendanceType,
        attendanceMethod: AttendanceMethod.manualFallback,
        faceVerified: false,
        fallbackReason: _reason,
        fallbackReasonText: _reason == FallbackReason.other
            ? _reasonTextController.text
            : null,
        fallbackPhotoUrl: uploadResult['url'],
        approvalStatus: ApprovalStatus.pendingApproval,
        gpsLocation: widget.location,
        gpsAccuracy: widget.accuracy,
        markedByUserId: SupabaseService().currentUser?.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 3. Save
      await _repository.markAttendance(attendance: attendance);

      if (mounted) {
        Navigator.pop(context, true); // Success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual Fallback')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Face Verification Failed',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please provide a manual reason and a live photo for supervisor approval.',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),
            _buildPhotoSection(),
            const SizedBox(height: 32),
            _buildReasonDropdown(),
            if (_reason == FallbackReason.other) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _reasonTextController,
                decoration: const InputDecoration(
                  labelText: 'Specify Reason',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 48),
            AnimatedButton(
              text: 'Submit for Approval',
              isLoading: _isSubmitting,
              gradient: AppColors.warningGradient,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mandatory Photo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _isSubmitting ? null : _capturePhoto,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(13),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(26)),
              image: _fallbackPhoto != null
                  ? DecorationImage(
                      image: FileImage(_fallbackPhoto!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _fallbackPhoto == null
                ? const Icon(
                    Icons.add_a_photo,
                    size: 40,
                    color: Colors.blueAccent,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildReasonDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reason for Failure',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<FallbackReason>(
          initialValue: _reason,
          items: FallbackReason.values
              .map(
                (r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.name.replaceAll('_', ' ').toUpperCase()),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _reason = v!),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            filled: true,
          ),
        ),
      ],
    );
  }
}
