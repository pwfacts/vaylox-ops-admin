import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/guard_model.dart';
import '../services/supabase_service.dart';
import '../services/imagekit_service.dart';

class GuardRepository {
  final SupabaseClient _client = SupabaseService().client;
  final ImageKitService _imageKit = ImageKitService();

  Future<void> enrollGuard({
    required Guard guard,
    Map<String, File>? documents,
  }) async {
    try {
      // 1. Upload documents if any
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

      // 2. Prepare final guard data
      final guardData = guard.toJson();
      guardData.addAll(documentUrls);

      // 3. Insert into Supabase
      await _client.from('guards').insert(guardData);
    } catch (e) {
      throw Exception('Failed to enroll guard: $e');
    }
  }

  Future<List<Guard>> getGuards({String? query, String? unitId}) async {
    var supabaseQuery = _client.from('guards').select();
    
    if (unitId != null) {
      supabaseQuery = supabaseQuery.eq('assigned_unit_id', unitId);
    }
    
    if (query != null && query.isNotEmpty) {
      supabaseQuery = supabaseQuery.ilike('full_name', '%$query%');
    }

    final response = await supabaseQuery.order('created_at', ascending: false);
    return (response as List).map((json) => Guard.fromJson(json)).toList();
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

  Future<void> deleteGuard(String id) async {
    // Soft delete
    await _client.from('guards').update({'status': 'inactive'}).eq('id', id);
  }
}
