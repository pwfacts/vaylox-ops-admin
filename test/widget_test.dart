// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaylox_ops/main.dart';
import 'package:vaylox_ops/data/services/supabase_service.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Initialize Supabase for testing
    final supabaseService = SupabaseService();
    await supabaseService.initialize();

    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: VayloxOpsApp()));

    // Wait for the app to finish loading
    await tester.pumpAndSettle();

    // Verify that the app loads (should show login screen initially)
    expect(find.text('JDS MANAGEMENT'), findsOneWidget);
    expect(find.text('Login Default Account'), findsOneWidget);
  });
}
