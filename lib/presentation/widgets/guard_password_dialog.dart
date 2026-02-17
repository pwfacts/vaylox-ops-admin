import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/guard_creation_service.dart';

class GuardPasswordDialog extends ConsumerStatefulWidget {
  final String guardName;
  final String guardEmail;
  final String userId;
  final String? guardCode;

  const GuardPasswordDialog({
    super.key,
    required this.guardName,
    required this.guardEmail,
    required this.userId,
    this.guardCode,
  });

  @override
  ConsumerState<GuardPasswordDialog> createState() =>
      _GuardPasswordDialogState();
}

class _GuardPasswordDialogState extends ConsumerState<GuardPasswordDialog> {
  final _service = GuardCreationService();
  String? _password;
  bool _isLoading = true;
  bool _isPasswordVisible = false;
  bool _isSendingEmail = false;

  @override
  void initState() {
    super.initState();
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    setState(() => _isLoading = true);
    try {
      final password = await _service.getTemporaryPassword(widget.userId);
      setState(() {
        _password = password;
        _isLoading = false;
      });

      if (password != null) {
        await _service.markPasswordAsViewed(widget.userId);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading password: $e')),
        );
      }
    }
  }

  Future<void> _resendEmail() async {
    if (_password == null) return;

    setState(() => _isSendingEmail = true);
    try {
      final success = await _service.resendPasswordEmail(
        guardEmail: widget.guardEmail,
        guardName: widget.guardName,
        password: _password!,
        guardCode: widget.guardCode,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '✅ Password email sent successfully!'
                  : '❌ Failed to send email. Please check SMTP settings.',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isSendingEmail = false);
    }
  }

  void _copyToClipboard() {
    if (_password == null) return;

    Clipboard.setData(ClipboardData(text: _password!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.key, color: Colors.deepPurple),
          const SizedBox(width: 8),
          const Text('Guard Credentials'),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : _password == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.orange),
                    SizedBox(height: 16),
                    Text(
                      'Password not available',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'The temporary password has expired or was already sent via email.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Guard info
                      _buildInfoRow('Guard Name', widget.guardName),
                      const SizedBox(height: 8),
                      _buildInfoRow('Email', widget.guardEmail),
                      if (widget.guardCode != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow('Guard Code', widget.guardCode!),
                      ],
                      const Divider(height: 24),

                      // Password section
                      const Text(
                        'Temporary Password:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.deepPurple),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isPasswordVisible
                                    ? _password!
                                    : '••••••••••••',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _isPasswordVisible
                                      ? Colors.red[700]
                                      : Colors.black,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                              tooltip: _isPasswordVisible ? 'Hide' : 'Show',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Warning
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: Colors.orange[700]),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Share this password securely. It will expire in 7 days.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      actions: [
        if (_password != null) ...[
          // Copy button
          TextButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),

          // Resend email button
          TextButton.icon(
            onPressed: _isSendingEmail ? null : _resendEmail,
            icon: _isSendingEmail
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.email),
            label: Text(_isSendingEmail ? 'Sending...' : 'Resend Email'),
          ),
        ],

        // Close button
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Helper function to show the dialog
Future<void> showGuardPasswordDialog(
  BuildContext context, {
  required String guardName,
  required String guardEmail,
  required String userId,
  String? guardCode,
}) {
  return showDialog(
    context: context,
    builder: (context) => GuardPasswordDialog(
      guardName: guardName,
      guardEmail: guardEmail,
      userId: userId,
      guardCode: guardCode,
    ),
  );
}
