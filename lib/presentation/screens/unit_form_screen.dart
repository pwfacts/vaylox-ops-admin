import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/unit_providers.dart';
import 'field_officer_assignment_dialog.dart';

class UnitFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? unitData;

  const UnitFormScreen({super.key, this.unitData});

  @override
  ConsumerState<UnitFormScreen> createState() => _UnitFormScreenState();
}

class _UnitFormScreenState extends ConsumerState<UnitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _geoController;
  String _status = 'active';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.unitData?['name']);
    _addressController =
        TextEditingController(text: widget.unitData?['address']);
    // geo_location is typically JSON or point, assuming string/lat-long text for now
    _geoController = TextEditingController(
        text: widget.unitData?['geo_location']?.toString());
    _status = widget.unitData?['status'] ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _geoController.dispose();
    super.dispose();
  }

  Future<void> _saveUnit() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'geo_location': _geoController.text.trim(),
      'status': _status,
    };

    try {
      if (widget.unitData == null) {
        // Create
        await ref.read(unitRepositoryProvider).createUnit(data);
      } else {
        // Update
        await ref
            .read(unitRepositoryProvider)
            .updateUnit(widget.unitData!['id'], data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unit Saved Successfully')));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.unitData != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Unit' : 'Create Unit'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Unit Name'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 3,
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _geoController,
                decoration: const InputDecoration(
                  labelText: 'Geo Location (Lat, Long)',
                  helperText: 'Optional: e.g. 26.9124, 75.7873',
                ),
              ),
              const SizedBox(height: 16),
              if (isEditing) ...[
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 24),
                // Section for Team Assignments
                const Divider(),
                const Text(
                  'Team Assignment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('Manage Assigned Guards'),
                  subtitle: const Text('View and assign guards'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Navigate to Guard Assignment or filter Guard List
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Manage Field Officers'),
                  subtitle: const Text('Assign FO to this unit'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => FieldOfficerAssignmentDialog(
                        unitId: widget.unitData!['id'],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveUnit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(isEditing ? 'Update Unit' : 'Create Unit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
