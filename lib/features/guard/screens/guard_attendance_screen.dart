import 'package:flutter/material.dart';

class GuardAttendanceScreen extends StatelessWidget {
  const GuardAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: const Center(child: Text('Guard Attendance - Coming Soon')),
    );
  }
}

class GuardHistoryScreen extends StatelessWidget {
  const GuardHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: const Center(child: Text('Guard History - Coming Soon')),
    );
  }
}

class GuardProfileScreen extends StatelessWidget {
  const GuardProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const Center(child: Text('Guard Profile - Coming Soon')),
    );
  }
}
