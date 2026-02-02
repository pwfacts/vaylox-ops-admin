import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;
import '../../core/constants/app_constants.dart';

class ImageKitService {
  static final ImageKitService _instance = ImageKitService._internal();
  factory ImageKitService() => _instance;
  ImageKitService._internal();

  final Dio _dio = Dio();

  // Signed URL approach:
  // In a production app, the backend (Supabase Edge Function) should provide the signature.
  // For now, we define the structure for the client.

  Future<String> getSignature(String token, int expire) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'imagekit-signature',
        body: {'token': token, 'expire': expire},
      );
      return response.data['signature'];
    } catch (e) {
      throw Exception('Failed to generate ImageKit signature: $e');
    }
  }

  Future<Map<String, dynamic>> uploadImage({
    required List<int> fileBytes,
    required String fileName,
    required String folder,
  }) async {
    final expire =
        DateTime.now()
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch ~/
        1000;
    final token = base64Encode(utf8.encode(fileName + expire.toString()));

    // Get signature from our Supabase Edge Function
    final signature = await getSignature(token, expire);

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      'fileName': fileName,
      'publicKey': imagekitPublicKey,
      'signature': signature,
      'expire': expire,
      'token': token,
      'folder': folder,
      'useUniqueFileName': 'true',
    });

    try {
      final response = await _dio.post(
        'https://upload.imagekit.io/api/v1/files/upload',
        data: formData,
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('ImageKit Upload Failed: ${response.data}');
      }
    } catch (e) {
      throw Exception('ImageKit Upload Error: $e');
    }
  }
}
