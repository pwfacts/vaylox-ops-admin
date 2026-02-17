import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../auth/auth_service.dart';

class ScopedQueryHelper {
  final SupabaseClient _client = Supabase.instance.client;
  final _logger = Logger();

  /// Helper to get a table query that is pre-filtered for the current user's role.
  /// This is an OPTIMIZATION. Security is handled by RLS.
  Future<PostgrestFilterBuilder> scopedQuery(
    String table, {
    String? select,
  }) async {
    var query = _client.from(table).select(select ?? '*');

    final role = await AuthService().getUserRole();
    final userId = _client.auth.currentUser?.id;

    if (userId == null) return query; // Should handle re-login

    if (role == 'field_officer') {
      // Field officers only see data related to their units
      // We need to fetch the units they are assigned to
      final unitIds = await _getUserUnitIds(userId);

      // If table has 'unit_id', filter by it
      // Custom filters per table
      if (table == 'attendance') {
        return query.filter('unit_id', 'in', unitIds);
      }
      if (table == 'guards') {
        return query.filter('assigned_unit_id', 'in', unitIds);
      }
      if (table == 'units') {
        return query.filter('id', 'in', unitIds);
      }
    } else if (role == 'supervisor') {
      // Supervisors see data for units they supervise
      // Logic is similar but source of unit IDs is different (from guards table or units table)
      // Since supervisors are defined in guards table (is_supervisor=true),
      // we need to find units where this user is the supervisor.
      final supervisedUnitIds = await _getSupervisedUnitIds(userId);

      if (table == 'attendance') {
        return query.filter('unit_id', 'in', supervisedUnitIds);
      }
      if (table == 'guards') {
        return query.filter('assigned_unit_id', 'in', supervisedUnitIds);
      }
      if (table == 'units') {
        return query.filter('id', 'in', supervisedUnitIds);
      }
    }

    // Admin/Accountant see everything (no extra filters needed, RLS allows all)
    return query;
  }

  Future<List<String>> _getUserUnitIds(String userId) async {
    try {
      final result = await _client
          .from('field_officer_units')
          .select('unit_id')
          .eq('user_id', userId);

      // Handle Supabase v2 response type (List<Map<String, dynamic>>)
      final data = result as List<dynamic>;
      return data.map((e) => e['unit_id'] as String).toList();
    } catch (e) {
      _logger.e('Error fetching FO units: $e');
      return [];
    }
  }

  Future<List<String>> _getSupervisedUnitIds(String userId) async {
    try {
      // Find units where this user is assigned as supervisor in guards table
      // Wait, the relationship is: Guard (is_supervisor) -> supervised_unit_id
      final result = await _client
          .from('guards')
          .select('supervised_unit_id')
          .eq('user_id', userId)
          .eq('is_supervisor', true);

      final data = result as List<dynamic>;
      return data
          .map((e) => e['supervised_unit_id'] as String?)
          .where((e) => e != null && e.isNotEmpty)
          .cast<String>()
          .toList();
    } catch (e) {
      _logger.e('Error fetching supervised units: $e');
      return [];
    }
  }
}
