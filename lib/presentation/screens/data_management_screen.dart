import 'package:flutter/material.dart';
import '../../data/services/backup_service.dart';
import 'package:intl/intl.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  final BackupService _backupService = BackupService();
  bool _isArchiving = false;
  final List<Map<String, dynamic>> _localBackups = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Data & Archives'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildInfoHero(),
          const SizedBox(height: 32),
          _buildActionSection(),
          const SizedBox(height: 32),
          _buildBackupHistory(),
        ],
      ),
    );
  }

  Widget _buildInfoHero() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueAccent.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text(
                'Secured Archives',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your data is protected by industry-standard AES-256 encryption. Archives are automatically prepared for cold storage in our private vault.',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),
        _buildArchiveTile(
          title: 'Full Database Backup',
          subtitle: 'Create a secured snapshot of all records',
          icon: Icons.cloud_upload_outlined,
          color: Colors.greenAccent,
          onTap: _runBackup,
        ),
        const SizedBox(height: 12),
        _buildArchiveTile(
          title: 'Clean Historical Data',
          subtitle: 'Archive & Purge records older than 90 days',
          icon: Icons.cleaning_services_outlined,
          color: Colors.orangeAccent,
          onTap: () {}, // Future implementation
        ),
      ],
    );
  }

  Widget _buildArchiveTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        trailing: _isArchiving && title.contains('Database')
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: _isArchiving ? null : onTap,
      ),
    );
  }

  Widget _buildBackupHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Backup History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 16),
        if (_localBackups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No archives generated yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ..._localBackups.map((b) => _buildHistoryCard(b)),
      ],
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> backup) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: Colors.blueAccent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup['fileName'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())} • AES-256 Encrypted',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          const Text(
            'SECURED',
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runBackup() async {
    setState(() => _isArchiving = true);

    final result = await _backupService.createSecureArchive();

    setState(() {
      _isArchiving = false;
      if (result['status'] == 'success') {
        _localBackups.insert(0, result);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: result['status'] == 'success'
              ? Colors.green
              : Colors.red,
        ),
      );
    }
  }
}
