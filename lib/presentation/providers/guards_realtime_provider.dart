import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/guard_model.dart';
import '../../data/services/supabase_service.dart';
import '../providers/access_profile_provider.dart';

/// Real-time guards list provider with automatic updates
class GuardsRealtimeNotifier extends StateNotifier<AsyncValue<List<Guard>>> {
  final SupabaseClient _client;
  final String organizationId;
  RealtimeChannel? _subscription;

  GuardsRealtimeNotifier(this._client, this.organizationId)
      : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    // Initial load
    await _loadGuards();

    // Set up real-time subscription
    _subscription = _client
        .channel('guards_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'guards',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_id',
            value: organizationId,
          ),
          callback: (payload) {
            // _logger.d('🔄 Realtime update received: ${payload.eventType}');
            // Reload guards on any change
            _loadGuards();
          },
        )
        .subscribe();
  }

  Future<void> _loadGuards() async {
    try {
      final response = await _client
          .from('guards')
          .select()
          .eq('organization_id', organizationId)
          .order('created_at', ascending: false);

      final guards = (response as List)
          .map((json) => Guard.fromJson(json as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(guards);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadGuards();
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}

/// Provider for real-time guards list
final guardsRealtimeProvider = StateNotifierProvider.family<
    GuardsRealtimeNotifier, AsyncValue<List<Guard>>, String>(
  (ref, organizationId) {
    final client = SupabaseService.client;
    return GuardsRealtimeNotifier(client, organizationId);
  },
);

/// Convenience provider that auto-fetches using current organization
final currentOrgGuardsProvider = Provider<AsyncValue<List<Guard>>>((ref) {
  final profile = ref.watch(accessProfileProvider);

  return profile.when(
    data: (profile) {
      if (profile.organizationId == null) return const AsyncValue.loading();
      return ref.watch(guardsRealtimeProvider(profile.organizationId!));
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// Provider to get a specific guard by ID (with realtime updates)
final guardByIdProvider = Provider.family<AsyncValue<Guard?>, String>(
  (ref, guardId) {
    final guards = ref.watch(currentOrgGuardsProvider);

    return guards.when(
      data: (guardsList) {
        try {
          final guard = guardsList.firstWhere((g) => g.id == guardId);
          return AsyncValue.data(guard);
        } catch (e) {
          return const AsyncValue.data(null);
        }
      },
      loading: () => const AsyncValue.loading(),
      error: (err, stack) => AsyncValue.error(err, stack),
    );
  },
);

/// Provider for guard statistics (with realtime)
final guardStatsProvider = Provider<Map<String, int>>((ref) {
  final guards = ref.watch(currentOrgGuardsProvider);

  return guards.when(
    data: (guardsList) {
      return {
        'total': guardsList.length,
        'active': guardsList.where((g) => g.status == 'active').length,
        'inactive': guardsList.where((g) => g.status == 'inactive').length,
        'pending': guardsList.where((g) => g.status == 'pending').length,
      };
    },
    loading: () => {'total': 0, 'active': 0, 'inactive': 0, 'pending': 0},
    error: (_, __) => {'total': 0, 'active': 0, 'inactive': 0, 'pending': 0},
  );
});
