import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../../core/utils/scoped_query_helper.dart';
import '../../core/auth/access_profile_service.dart';

final _logger = Logger();

class UnitRepository {
  final SupabaseClient _client = Supabase.instance.client;
  final ScopedQueryHelper _scopedHelper = ScopedQueryHelper();

  Future<List<Map<String, dynamic>>> getUnits({
    String? query,
    String status = 'active',
  }) async {
    var supabaseQuery = await _scopedHelper.scopedQuery('units');

    if (status != 'all') {
      supabaseQuery = supabaseQuery.eq('status', status);
    }

    if (query != null && query.isNotEmpty) {
      supabaseQuery = supabaseQuery.ilike('name', '%$query%');
    }

    final response = await supabaseQuery.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<void> createUnit(Map<String, dynamic> unitData) async {
    await _client.from('units').insert(unitData);
  }

  Future<void> updateUnit(String id, Map<String, dynamic> updates) async {
    await _client.from('units').update(updates).eq('id', id);
  }

  Future<void> assignFieldOfficer(String unitId, String userId) async {
    await _client.from('field_officer_units').upsert({
      'unit_id': unitId,
      'user_id': userId,
    });
  }

  Future<void> removeFieldOfficer(String unitId, String userId) async {
    await _client
        .from('field_officer_units')
        .delete()
        .eq('unit_id', unitId)
        .eq('user_id', userId);
  }

  /// Supervisors are Guards with special flag
  Future<void> assignSupervisor(String unitId, String guardId) async {
    await _client.from('guards').update({
      'is_supervisor': true,
      'supervised_unit_id': unitId,
    }).eq('id', guardId);
  }

  Future<void> unassignSupervisor(String guardId) async {
    await _client.from('guards').update({
      'is_supervisor': false,
      'supervised_unit_id': null,
    }).eq('id', guardId);
  }

  Future<List<Map<String, dynamic>>> getAssignedFieldOfficers(
      String unitId) async {
    final response = await _client
        .from('field_officer_units')
        .select('*, users(full_name, email)')
        .eq('unit_id', unitId);

    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<List<Map<String, dynamic>>> getAvailableFieldOfficers() async {
    try {
      final profile = await AccessProfileService().getAccessProfile();
      final orgId = profile.organizationId;
      if (orgId == null) return [];

      final response = await _client
          .from('organization_users')
          .select('role, users(id, full_name, email)')
          .eq('organization_id', orgId)
          .eq('role', 'field_officer');

      final results = (response as List).map((membership) {
        final userData = membership['users'] as Map<String, dynamic>?;
        return {
          ...?userData,
          'role': membership['role'],
        };
      }).toList();

      return results;
    } catch (e) {
      _logger.e('Error fetching available FOs: $e');
      return [];
    }
  }
}
