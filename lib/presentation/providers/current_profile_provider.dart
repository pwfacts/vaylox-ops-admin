import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/guard_model.dart';
import '../../data/repositories/guard_repository.dart';
import '../../data/services/supabase_service.dart';

final currentProfileProvider = FutureProvider<Guard?>((ref) async {
  final user = SupabaseService().currentUser;
  if (user == null) return null;
  
  // Fetch guard profile linked to this user ID
  return ref.read(guardRepositoryProvider).getGuardByUserId(user.id);
});
