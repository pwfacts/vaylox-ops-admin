import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/access_profile.dart';
import '../../core/auth/access_profile_service.dart';

final accessProfileProvider = FutureProvider<AccessProfile>((ref) async {
  return AccessProfileService().getAccessProfile();
});
