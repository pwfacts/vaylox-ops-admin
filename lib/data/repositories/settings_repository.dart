import '../services/supabase_service.dart';

class PayrollSettings {
  final String organizationId;
  final double pfCap;
  final double esicThreshold;
  final double ptThreshold;
  final double lwfAmount;
  final List<int> lwfMonths;
  final double hraPercentage;

  PayrollSettings({
    required this.organizationId,
    required this.pfCap,
    required this.esicThreshold,
    required this.ptThreshold,
    required this.lwfAmount,
    required this.lwfMonths,
    required this.hraPercentage,
  });

  factory PayrollSettings.fromJson(Map<String, dynamic> json) {
    return PayrollSettings(
      organizationId: json['organization_id'],
      pfCap: (json['pf_cap'] as num).toDouble(),
      esicThreshold: (json['esic_threshold'] as num).toDouble(),
      ptThreshold: (json['pt_threshold'] as num).toDouble(),
      lwfAmount: (json['lwf_amount'] as num).toDouble(),
      lwfMonths: List<int>.from(json['lwf_months'] ?? []),
      hraPercentage: (json['hra_percentage'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pf_cap': pfCap,
      'esic_threshold': esicThreshold,
      'pt_threshold': ptThreshold,
      'lwf_amount': lwfAmount,
      'lwf_months': lwfMonths,
      'hra_percentage': hraPercentage,
    };
  }
}

class SettingsRepository {
  final _client = SupabaseService.client;

  Future<PayrollSettings> getSettings(String organizationId) async {
    final response = await _client
        .from('payroll_settings')
        .select()
        .eq('organization_id', organizationId)
        .single();
    return PayrollSettings.fromJson(response);
  }

  Future<void> updateSettings(PayrollSettings settings) async {
    await _client
        .from('payroll_settings')
        .update(settings.toJson())
        .eq('organization_id', settings.organizationId);
  }
}
