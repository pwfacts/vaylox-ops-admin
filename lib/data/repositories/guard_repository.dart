import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../models/guard_model.dart';
import '../services/supabase_service.dart';
import '../services/imagekit_service.dart';
import '../../core/utils/scoped_query_helper.dart';

class GuardRepository {
  final SupabaseClient _client = SupabaseService.client;
  final ImageKitService _imageKit = ImageKitService();
  final _logger = Logger();

  Future<void> enrollGuard({
    required Guard guard,
    Map<String, XFile>? documents,
  }) async {
    try {
      // 1. Create Auth User via Edge Function
      // This creates the user in auth.users and returns the user_id (and sends email)
      String? userId;
      if (guard.email != null && guard.email!.isNotEmpty) {
        try {
          final userRes =
              await _client.functions.invoke('create-guard-user', body: {
            'email': guard.email,
            'fullName': guard.fullName,
            'organizationId': guard.organizationId,
          });

          if (userRes.data != null && userRes.data['user_id'] != null) {
            userId = userRes.data['user_id'];
          }
        } catch (e) {
          _logger.w('Warning: Failed to create auth user: $e');
          // Proceeding without user_id? Or fail?
          // If we fail, we can't login.
          // For now, let's rethrow to show error in UI.
          throw Exception('Failed to create login account: $e');
        }
      }

      // 2. Upload documents if any
      final Map<String, String> documentUrls = {};
      if (documents != null) {
        for (var entry in documents.entries) {
          final uploadResult = await _imageKit.uploadImage(
            fileBytes: await entry.value.readAsBytes(),
            fileName: '${guard.guardCode}_${entry.key}',
            folder: 'guards/${guard.guardCode}',
          );
          documentUrls['${entry.key}_url'] = uploadResult['url'];
        }
      }

      // 3. Prepare final guard data
      // If we got a userId, link it.
      Guard finalGuard = guard;
      if (userId != null) {
        finalGuard = guard.copyWith(userId: userId);
      }

      final guardData = finalGuard.toJson();
      guardData.addAll(documentUrls);

      // 4. Insert into Supabase
      await _client.from('guards').insert(guardData);
    } catch (e) {
      throw Exception('Failed to enroll guard: $e');
    }
  }

  Future<List<Guard>> getGuards({
    String? query,
    String? unitId,
    String status = 'active',
    int page = 0,
    int pageSize = 20,
  }) async {
    final scopedHelper = ScopedQueryHelper();
    var supabaseQuery = await scopedHelper.scopedQuery('guards');

    if (unitId != null) {
      supabaseQuery = supabaseQuery.eq('assigned_unit_id', unitId);
    }

    if (status != 'all') {
      supabaseQuery = supabaseQuery.eq('status', status);
    }

    if (query != null && query.isNotEmpty) {
      // Search by name or phone or guard code
      supabaseQuery = supabaseQuery.or(
          'full_name.ilike.%$query%,phone.ilike.%$query%,guard_code.ilike.%$query%');
    }

    final start = page * pageSize;
    final end = start + pageSize - 1;

    final response = await supabaseQuery
        .order('created_at', ascending: false)
        .range(start, end);

    final data = response as List<dynamic>;
    return data.map((json) => Guard.fromJson(json)).toList();
  }

  Future<Guard?> getGuardByUserId(String userId) async {
    final response = await _client
        .from('guards')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return Guard.fromJson(response);
  }

  Future<void> updateGuard(String id, Map<String, dynamic> updates) async {
    await _client.from('guards').update(updates).eq('id', id);
  }

  Future<void> updateGuardDetails({
    required Guard guard,
    Map<String, XFile>? newDocuments,
  }) async {
    try {
      final Map<String, String> documentUrls = {};

      // Upload new documents if provided
      if (newDocuments != null && newDocuments.isNotEmpty) {
        for (var entry in newDocuments.entries) {
          final uploadResult = await _imageKit.uploadImage(
            fileBytes: await entry.value.readAsBytes(),
            fileName:
                '${guard.guardCode}_${entry.key}_${DateTime.now().millisecondsSinceEpoch}',
            folder: 'guards/${guard.guardCode}',
          );
          documentUrls['${entry.key}_url'] = uploadResult['url'];
        }
      }

      // Prepare update data
      final updates = guard.toJson();
      // Remove fields that shouldn't be updated or are handled separately if needed
      // For now, updating all fields is fine, except maybe created_at/id/organization_id which won't change anyway
      // But we must merge new doc URLs
      updates.addAll(documentUrls);

      // We don't update ID or Organization ID typically, but toJson includes them.
      // Supabase ignores ID in update if it's the PK and matches the filter, but let's be safe.
      updates.remove('id');
      updates.remove('created_at');

      await _client.from('guards').update(updates).eq('id', guard.id);
    } catch (e) {
      throw Exception('Failed to update guard: $e');
    }
  }

  Future<void> deleteGuard(String id) async {
    // Soft delete
    await _client.from('guards').update({'status': 'inactive'}).eq('id', id);
  }

  Future<String> generateNextGuardCode(String unitId) async {
    try {
      // 1. Get Unit Code
      final unitRes =
          await _client.from('units').select('code').eq('id', unitId).single();

      String prefix = (unitRes['code'] as String?)?.toUpperCase() ?? 'EMP';
      // Clean prefix if needed
      prefix = prefix.replaceAll(RegExp(r'[^A-Z0-9]'), '');

      // 2. Get last guard with this prefix
      final lastGuardRes = await _client
          .from('guards')
          .select('guard_code')
          .ilike('guard_code', '$prefix-%')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      int nextNum = 1;
      if (lastGuardRes != null) {
        final lastCode = lastGuardRes['guard_code'] as String;
        // Expected format: PRE-001
        final parts = lastCode.split('-');
        if (parts.length > 1) {
          final numPart = int.tryParse(parts.last);
          if (numPart != null) {
            nextNum = numPart + 1;
          }
        }
      }

      return '$prefix-${nextNum.toString().padLeft(3, '0')}';
    } catch (e) {
      _logger.e('Error generating code: $e');
      return 'EMP-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'; // Fallback
    }
  }
}
