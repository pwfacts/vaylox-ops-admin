import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'package:logger/logger.dart';

/// ============================================
/// FREE-TIER OPTIMIZED POLLING SYSTEM
/// Delta Sync Pattern for Minimal Bandwidth
/// ============================================

class DeltaSyncService {
  final SupabaseClient _client;
  final Logger _logger = Logger();

  // Sync timestamps stored locally
  static const String _prefixKey = 'last_sync_';

  // Polling intervals (configurable)
  static const Duration notificationPollInterval = Duration(seconds: 8);
  static const Duration guardsPollInterval = Duration(seconds: 12);
  static const Duration leaveRequestsPollInterval = Duration(seconds: 10);
  static const Duration overtimeRequestsPollInterval = Duration(seconds: 10);

  DeltaSyncService(this._client);

  /// Get last sync timestamp for a table
  Future<DateTime> getLastSync(String tableName) async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString('$_prefixKey$tableName');

    if (timestamp != null) {
      return DateTime.parse(timestamp);
    }

    // Default to 24 hours ago on first sync
    return DateTime.now().subtract(const Duration(hours: 24));
  }

  /// Update last sync timestamp
  Future<void> updateLastSync(String tableName, DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixKey$tableName', timestamp.toIso8601String());
  }

  /// Generic delta sync for any table
  Future<List<Map<String, dynamic>>> fetchDelta<T>({
    required String tableName,
    String? organizationFilter,
    Map<String, dynamic>? additionalFilters,
    String orderBy = 'updated_at',
  }) async {
    try {
      // Get last sync time
      final lastSync = await getLastSync(tableName);

      _logger.d('Fetching delta for $tableName since $lastSync');

      // Build query (start with select)
      var query = _client.from(tableName).select();

      // Apply updated_at filter
      query = query.gt('updated_at', lastSync.toIso8601String());

      // Apply organization filter if provided
      if (organizationFilter != null) {
        query = query.eq('organization_id', organizationFilter);
      }

      // Apply additional filters
      if (additionalFilters != null) {
        additionalFilters.forEach((key, value) {
          query = query.eq(key, value);
        });
      }

      // Finally apply order and await
      final response = await query.order(orderBy, ascending: false);

      // Update last sync timestamp to now
      if (response.isNotEmpty) {
        await updateLastSync(tableName, DateTime.now());
        _logger.i(
            '✅ Fetched ${response.length} new/updated records from $tableName');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('Error fetching delta for $tableName:', error: e);
      return [];
    }
  }

  /// Fetch delta with local cache merge
  Future<List<T>> fetchDeltaWithCache<T>({
    required String tableName,
    required List<T> currentCache,
    required T Function(Map<String, dynamic>) fromJson,
    required String Function(T) getId,
    String? organizationFilter,
    Map<String, dynamic>? additionalFilters,
  }) async {
    final deltaRecords = await fetchDelta(
      tableName: tableName,
      organizationFilter: organizationFilter,
      additionalFilters: additionalFilters,
    );

    if (deltaRecords.isEmpty) {
      return currentCache;
    }

    // Convert to objects
    final deltaObjects = deltaRecords.map((json) => fromJson(json)).toList();

    // Merge with cache
    final Map<String, T> mergedMap = {
      for (var item in currentCache) getId(item): item
    };

    // Update/add delta items
    for (var item in deltaObjects) {
      mergedMap[getId(item)] = item;
    }

    return mergedMap.values.toList();
  }

  /// Clear all sync timestamps (for logout/reset)
  Future<void> clearAllSyncTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(_prefixKey));

    for (var key in keys) {
      await prefs.remove(key);
    }

    _logger.i('🗑️ Cleared all sync timestamps');
  }
}

/// Provider for delta sync service
final deltaSyncServiceProvider = Provider<DeltaSyncService>((ref) {
  return DeltaSyncService(SupabaseService.client);
});

/// ============================================
/// POLLING PROVIDERS
/// ============================================

/// Notifications Polling Provider
class NotificationsPollingNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final DeltaSyncService _syncService;
  final String userId;
  Timer? _pollTimer;
  List<Map<String, dynamic>> _cache = [];

  NotificationsPollingNotifier(this._syncService, this.userId)
      : super(const AsyncValue.loading()) {
    _startPolling();
  }

  void _startPolling() {
    _poll();
    _pollTimer = Timer.periodic(
      DeltaSyncService.notificationPollInterval,
      (_) => _poll(),
    );
  }

  Future<void> _poll() async {
    try {
      final delta = await _syncService.fetchDelta(
        tableName: 'notifications',
        additionalFilters: {'user_id': userId},
        orderBy: 'created_at',
      );

      if (delta.isNotEmpty) {
        // Merge with cache
        final Map<String, Map<String, dynamic>> mergedMap = {
          for (var item in _cache) item['id'] as String: item
        };

        for (var item in delta) {
          mergedMap[item['id'] as String] = item;
        }

        _cache = mergedMap.values.toList()
          ..sort((a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String));

        state = AsyncValue.data(_cache);
      } else if (_cache.isEmpty) {
        // First load - fetch all unread
        final unread = await _syncService._client
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .eq('is_read', false)
            .order('created_at', ascending: false)
            .limit(50);

        _cache = List<Map<String, dynamic>>.from(unread);
        state = AsyncValue.data(_cache);
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _syncService._client.from('notifications').update({
        'is_read': true,
        'read_at': DateTime.now().toIso8601String()
      }).eq('id', notificationId);

      // Update cache
      _cache = _cache.map((n) {
        if (n['id'] == notificationId) {
          return {...n, 'is_read': true};
        }
        return n;
      }).toList();

      state = AsyncValue.data(_cache);
    } catch (e) {
      _logger.e('Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _syncService._client
          .from('notifications')
          .update(
              {'is_read': true, 'read_at': DateTime.now().toIso8601String()})
          .eq('user_id', userId)
          .eq('is_read', false);

      // Update cache
      _cache = _cache.map((n) => {...n, 'is_read': true}).toList();
      state = AsyncValue.data(_cache);
    } catch (e) {
      _logger.e('Error marking all notifications as read: $e');
    }
  }

  int get unreadCount {
    return _cache.where((n) => n['is_read'] == false).length;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final notificationsPollingProvider = StateNotifierProvider.family<
    NotificationsPollingNotifier,
    AsyncValue<List<Map<String, dynamic>>>,
    String>((ref, userId) {
  final syncService = ref.watch(deltaSyncServiceProvider);
  return NotificationsPollingNotifier(syncService, userId);
});

/// Unread notification count provider
final unreadNotificationCountProvider =
    Provider.family<int, String>((ref, userId) {
  final notifications = ref.watch(notificationsPollingProvider(userId));

  return notifications.when(
    data: (list) => list.where((n) => n['is_read'] == false).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// ============================================
/// GUARDS DELTA SYNC PROVIDER
/// ============================================

class GuardsDeltaSyncNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final DeltaSyncService _syncService;
  final String organizationId;
  Timer? _pollTimer;
  List<Map<String, dynamic>> _cache = [];

  GuardsDeltaSyncNotifier(this._syncService, this.organizationId)
      : super(const AsyncValue.loading()) {
    _initialize();
  }

  Future<void> _initialize() async {
    _logger
        .i('DeltaSyncService initialized with organization: $organizationId');
    // Initial full load
    await _fullSync();

    // Start polling for deltas
    _pollTimer = Timer.periodic(
      DeltaSyncService.guardsPollInterval,
      (_) => _deltaSync(),
    );
  }

  Future<void> _fullSync() async {
    try {
      final guards = await _syncService._client
          .from('guards')
          .select()
          .eq('organization_id', organizationId)
          .order('created_at', ascending: false);

      _cache = List<Map<String, dynamic>>.from(guards);
      state = AsyncValue.data(_cache);

      // Set initial sync timestamp
      await _syncService.updateLastSync('guards', DateTime.now());
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> _deltaSync() async {
    try {
      final delta = await _syncService.fetchDelta(
        tableName: 'guards',
        organizationFilter: organizationId,
      );

      if (delta.isNotEmpty) {
        // Merge delta with cache
        final Map<String, Map<String, dynamic>> mergedMap = {
          for (var item in _cache) item['id'] as String: item
        };

        for (var item in delta) {
          mergedMap[item['id'] as String] = item;
        }

        _cache = mergedMap.values.toList();
        state = AsyncValue.data(_cache);
      }
    } catch (e) {
      // Don't update state on error during delta sync
      _logger.d('Delta sync error for guards: $e');
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _fullSync();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final guardsDeltaSyncProvider = StateNotifierProvider.family<
    GuardsDeltaSyncNotifier,
    AsyncValue<List<Map<String, dynamic>>>,
    String>((ref, organizationId) {
  final syncService = ref.watch(deltaSyncServiceProvider);
  return GuardsDeltaSyncNotifier(syncService, organizationId);
});
