import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/unit_providers.dart';
import 'unit_form_screen.dart';

class UnitListScreen extends ConsumerStatefulWidget {
  const UnitListScreen({super.key});

  @override
  ConsumerState<UnitListScreen> createState() => _UnitListScreenState();
}

class _UnitListScreenState extends ConsumerState<UnitListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final unitsAsync = ref.watch(unitListProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit Management'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search units...',
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
      body: unitsAsync.when(
        data: (units) => units.isEmpty
            ? const Center(child: Text('No units found.'))
            : ListView.builder(
                itemCount: units.length,
                itemBuilder: (context, index) {
                  final unit = units[index];
                  return Card(
                    elevation: 0,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFF1E293B),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                        child: const Icon(Icons.business, color: Colors.blue),
                      ),
                      title: Text(unit['name'] ?? 'Unnamed'),
                      subtitle: Text(unit['address'] ?? 'No Address'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                UnitFormScreen(unitData: unit),
                          ),
                        ).then(
                            (_) => ref.refresh(unitListProvider(_searchQuery)));
                      },
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UnitFormScreen()),
        ).then((_) => ref.refresh(unitListProvider(_searchQuery))),
        icon: const Icon(Icons.add),
        label: const Text('Add Unit'),
      ),
    );
  }
}
