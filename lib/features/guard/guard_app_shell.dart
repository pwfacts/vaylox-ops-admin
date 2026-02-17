import 'package:flutter/material.dart';
import 'screens/guard_home_screen.dart';
import 'screens/guard_attendance_screen.dart';
import 'screens/guard_history_screen.dart';
import 'screens/guard_profile_screen.dart';

/// Guard app shell with bottom navigation
/// Simple personal tracking interface for guards
class GuardAppShell extends StatefulWidget {
  const GuardAppShell({super.key});

  @override
  State<GuardAppShell> createState() => _GuardAppShellState();
}

class _GuardAppShellState extends State<GuardAppShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    GuardHomeScreen(),
    GuardAttendanceScreen(),
    GuardHistoryScreen(),
    GuardProfileScreen(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today,
      label: 'Attendance',
    ),
    _NavItem(
      icon: Icons.history_outlined,
      activeIcon: Icons.history,
      label: 'History',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      elevation: 8,
      height: 64,
      destinations: _navItems
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.activeIcon),
              label: item.label,
            ),
          )
          .toList(),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
