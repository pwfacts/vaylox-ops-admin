import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/unit_repository.dart';

final unitRepositoryProvider = Provider((ref) => UnitRepository());

final unitListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, query) async {
  return ref.watch(unitRepositoryProvider).getUnits(query: query);
});
