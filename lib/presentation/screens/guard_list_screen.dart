import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/guard_model.dart';
import 'enrollment_screen.dart';
import '../providers/guard_enrollment_provider.dart';

final guardListProvider = FutureProvider.autoDispose
    .family<List<Guard>, String?>((ref, query) async {
      return ref.watch(guardRepositoryProvider).getGuards(query: query);
    });

class GuardListScreen extends ConsumerStatefulWidget {
  const GuardListScreen({super.key});

  @override
  ConsumerState<GuardListScreen> createState() => _GuardListScreenState();
}

class _GuardListScreenState extends ConsumerState<GuardListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final guardsAsync = ref.watch(guardListProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guard Management'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search guards...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: guardsAsync.when(
        data: (guards) => guards.isEmpty
            ? const Center(child: Text('No guards found.'))
            : ListView.builder(
                itemCount: guards.length,
                itemBuilder: (context, index) {
                  final guard = guards[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: guard.photoUrl != null
                          ? NetworkImage(guard.photoUrl!)
                          : null,
                      child: guard.photoUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(guard.fullName),
                    subtitle: Text('Code: ${guard.guardCode} | ${guard.phone}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to details or edit
                    },
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EnrollmentScreen()),
        ).then((_) => ref.refresh(guardListProvider(_searchQuery))),
        icon: const Icon(Icons.add),
        label: const Text('Enroll Guard'),
      ),
    );
  }
}
