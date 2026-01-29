import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../data/models/unit_model.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/attendance_model.dart';
import '../../data/services/supabase_service.dart';
import '../providers/attendance_provider.dart';
import '../providers/current_profile_provider.dart';
import '../services/face_comparison_service.dart';
import 'face_registration_screen.dart';
import 'manual_fallback_screen.dart';
import 'salary_slip_list_screen.dart';
import '../widgets/animated_button.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _isVerifying = false;
  String? _selectedUnitId;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF1F2937)],
          ),
        ),
        child: SafeArea(
          child: profileAsync.when(
            data: (profile) {
              if (profile == null) {
                return const Center(
                  child: Text('No guard profile linked to this user.', style: TextStyle(color: Colors.white)),
                );
              }
              return _buildAttendanceUI(profile);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceUI(dynamic profile) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInDown(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome,',
                      style: TextStyle(color: Colors.grey[400], fontSize: 16),
                    ),
                    Text(
                      profile.fullName,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blueAccent.withOpacity(0.2),
                  child: IconButton(
                    icon: const Icon(Icons.receipt_long, color: Colors.blueAccent),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SalarySlipListScreen())),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Center(
            child: FadeIn(
              delay: const Duration(milliseconds: 300),
              child: _buildShiftClock(),
            ),
          ),
          const Spacer(),
          FadeInUp(
            delay: const Duration(milliseconds: 600),
            child: _buildAttendanceCard(profile),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildShiftClock() {
    return Column(
      children: [
        Text(
          DateFormat('EEEE, MMM d').format(DateTime.now()),
          style: TextStyle(color: Colors.grey[400], fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          DateFormat('hh:mm a').format(DateTime.now()),
          style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildAttendanceCard(dynamic profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          const Text(
            'Punch In',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Status: Not Marked',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 24),
          _buildUnitSelector(profile),
          const SizedBox(height: 32),
          AnimatedButton(
            text: 'Verify Face & Location',
            isLoading: _isVerifying,
            onPressed: () => _startAttendanceFlow(profile),
          ),
        ],
      ),
    );
  }

  Future<void> _startAttendanceFlow(dynamic profile) async {
    setState(() => _isVerifying = true);
    
    try {
      // 1. GPS Validation
      final position = await _getCurrentLocation();
      
      // 2. Navigate to Face Capture
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceRegistrationScreen(
            onFaceRegistered: (encoding, imageFile) {
              _processAttendance(profile, encoding, position);
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Widget _buildUnitSelector(dynamic profile) {
    final unitsAsync = ref.watch(unitsProvider);
    
    // Set initial selection to assigned unit if not already set
    if (_selectedUnitId == null) {
      _selectedUnitId = profile.assignedUnitId;
    }

    return unitsAsync.when(
      data: (units) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedUnitId,
            isExpanded: true,
            dropdownColor: const Color(0xFF1F2937),
            style: const TextStyle(color: Colors.white),
            items: units.map((u) => DropdownMenuItem(
              value: u.id,
              child: Text(u.name, style: const TextStyle(color: Colors.white)),
            )).toList(),
            onChanged: (val) => setState(() => _selectedUnitId = val),
          ),
        ),
      ),
      loading: () => const LinearProgressIndicator(),
      error: (e, s) => Text('Error loading units: $e', style: const TextStyle(color: Colors.red)),
    );
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw 'Location services are disabled.';

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw 'Location permissions are denied';
    }
    
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  void _processAttendance(dynamic profile, String encoding, Position position) async {
    // 1. Calculate Face Match Score using real comparison
    final faceService = FaceComparisonService();
    double matchScore = 0.0;
    
    if (profile.faceEncoding != null) {
      matchScore = faceService.calculateMatchScore(encoding, profile.faceEncoding!);
    }
    
    // Check if the user wants to test fallback (optional logic for testing)
    // if (encoding.contains("failure")) matchScore = 0.5;

    if (matchScore >= 0.8) {
      final isOt = _selectedUnitId != profile.assignedUnitId;
      
      final attendance = Attendance(
        id: const Uuid().v4(),
        companyId: DEFAULT_COMPANY_ID,
        guardId: profile.id,
        attendanceDate: DateTime.now(),
        shift: _determineShift(),
        unitId: _selectedUnitId!, // worked_unit_id
        workedUnitId: _selectedUnitId,
        primaryUnitId: profile.assignedUnitId,
        type: isOt ? AttendanceType.OT : AttendanceType.NORMAL,
        attendanceMethod: AttendanceMethod.FACE,
        faceVerified: true,
        faceMatchScore: matchScore,
        gpsLocation: LatLng(position.latitude, position.longitude),
        gpsAccuracy: position.accuracy,
        markedByUserId: SupabaseService().currentUser?.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        approvalStatus: ApprovalStatus.APPROVED,
      );

      try {
        await ref.read(attendanceRepositoryProvider).markAttendance(attendance: attendance);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Success: Attendance marked!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      }
    } else {
      // 2. Trigger Manual Fallback
      if (!mounted) return;
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ManualFallbackScreen(
            profile: profile,
            location: LatLng(position.latitude, position.longitude),
            accuracy: position.accuracy,
            shift: _determineShift(),
            workedUnitId: _selectedUnitId,
            primaryUnitId: profile.assignedUnitId,
            attendanceType: _selectedUnitId != profile.assignedUnitId ? AttendanceType.OT : AttendanceType.NORMAL,
          ),
        ),
      );

      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted for Supervisor Approval.')),
        );
      }
    }
  }

  String _determineShift() {
    final hour = DateTime.now().hour;
    if (hour >= 8 && hour < 20) return 'day';
    return 'night';
  }
}
