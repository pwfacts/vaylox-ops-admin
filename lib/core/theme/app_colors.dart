import 'package:flutter/material.dart';

class AppColors {
  // Primary
  static const primaryBlue = Color(0xFF2563EB);
  static const primaryBlueDark = Color(0xFF1E40AF);
  static const primaryBlueLight = Color(0xFF60A5FA);
  
  // Success (Face Recognition Success)
  static const success = Color(0xFF10B981);
  static const successLight = Color(0xFF34D399);
  
  // Warning (Manual Fallback)
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFBBF24);
  
  // Error
  static const error = Color(0xFFEF4444);
  static const errorLight = Color(0xFFF87171);
  
  // Neutral
  static const backgroundLight = Color(0xFFF9FAFB);
  static const backgroundDark = Color(0xFF111827);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  
  // Gradients
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const warningGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTextStyles {
  static const heading1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
    height: 1.2,
  );
  
  static const heading2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.3,
    height: 1.3,
  );
  
  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );
  
  static const caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.4,
  );
}
