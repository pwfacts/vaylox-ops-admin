import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import './supabase_service.dart';

class BackupService {
  final _client = SupabaseService().client;
  final _logger = Logger();

  // Encryption configuration
  // In production, NEVER hardcode these. Use a secure vault or env.
  final _key = enc.Key.fromUtf8('jds_secure_vault_32char_key_!!!!');
  final _iv = enc.IV.fromLength(16);

  /// Archives attendance and salary data older than N days
  Future<Map<String, dynamic>> createSecureArchive({
    int olderThanDays = 90,
  }) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: olderThanDays));
    final dateStr = cutoffDate.toIso8601String().split('T')[0];

    try {
      // 1. Fetch historical data
      final attendanceRes = await _client
          .from('attendance')
          .select()
          .lt('attendance_date', dateStr);

      final slipsRes = await _client
          .from('salary_slips')
          .select()
          .lt('created_at', cutoffDate.toIso8601String());

      if (attendanceRes.isEmpty && slipsRes.isEmpty) {
        return {'status': 'info', 'message': 'No old data found to archive'};
      }

      final archiveData = {
        'metadata': {
          'version': '1.0',
          'type': 'PURGE_AND_BACKUP',
          'archived_at': DateTime.now().toIso8601String(),
          'range_end': dateStr,
          'record_counts': {
            'attendance': attendanceRes.length,
            'slips': slipsRes.length,
          },
        },
        'payload': {'attendance': attendanceRes, 'salary_slips': slipsRes},
      };

      // 2. Encrypt Data (AES-256)
      final encrypter = enc.Encrypter(enc.AES(_key));
      final encrypted = encrypter.encrypt(jsonEncode(archiveData), iv: _iv);

      // 3. Save to Local File temp
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'archive_${DateTime.now().millisecondsSinceEpoch}.jds';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(encrypted.bytes);

      // 4. Backup to Cloud (GitHub Private Repo)
      final backupSuccess = await _pushToGitHub(file, fileName);

      if (backupSuccess) {
        // 5. Purge from DB (Only after successful cloud backup)
        // await _purgeOldRecords(attendanceRes, slipsRes);
        return {
          'status': 'success',
          'message':
              'Archive created and secured. ${attendanceRes.length + slipsRes.length} records processed.',
          'fileName': fileName,
        };
      } else {
        return {
          'status': 'error',
          'message': 'Cloud backup failed. Purge aborted.',
        };
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<bool> _pushToGitHub(File file, String fileName) async {
    try {
      final contentBase64 = base64Encode(await file.readAsBytes());

      // We invoke a secure Supabase Edge Function that holds all GitHub secrets
      final response = await _client.functions.invoke(
        'perform-secure-backup',
        body: {'fileName': fileName, 'content': contentBase64},
      );

      if (response.status == 200) {
        _logger.i(
          'BACKUP: Pushed $fileName to GitHub via Secure Edge Function.',
        );
        return true;
      } else {
        _logger.e('BACKUP ERROR: ${response.data}');
        return false;
      }
    } catch (e) {
      _logger.e('BACKUP FUNCTION ERROR: $e');
      return false;
    }
  }

  /// Restoration Decrypts a backup file
  Future<Map<String, dynamic>> decryptArchive(String filePath) async {
    try {
      final file = File(filePath);
      final encryptedBytes = await file.readAsBytes();

      final encrypter = enc.Encrypter(enc.AES(_key));
      final decrypted = encrypter.decrypt(
        enc.Encrypted(encryptedBytes),
        iv: _iv,
      );

      return jsonDecode(decrypted);
    } catch (e) {
      throw Exception(
        'Decryption failed: Might be wrong key or corrupted file.',
      );
    }
  }
}
