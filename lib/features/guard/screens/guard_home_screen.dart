import 'package:flutter/material.dart';

class GuardHomeScreen extends StatelessWidget {
  const GuardHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(child: Text('Guard Home - Coming Soon')),
    );
  }
}
