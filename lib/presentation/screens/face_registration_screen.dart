import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final Function(String encoding, XFile imageFile) onFaceRegistered;

  const FaceRegistrationScreen({super.key, required this.onFaceRegistered});

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final _picker = ImagePicker();
  final faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  
  bool _isProcessing = false;
  String? _error;

  Future<void> _captureAndProcess() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final inputImage = InputImage.fromFilePath(image.path);
      final List<Face> faces = await faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        throw Exception('No face detected. Please try again with better lighting.');
      }

      if (faces.length > 1) {
        throw Exception('Multiple faces detected. Please ensure only one person is in the frame.');
      }

      final face = faces.first;
      
      // Extract face "encoding" - as a simple landmark-based representation for foundation
      // In a production app, we would use a model like FaceNet for real embeddings (TFLite)
      // For Phase 2, we store the landmark coordinates as a JSON string
      final Map<String, dynamic> encoding = {
        'boundingBox': {
          'left': face.boundingBox.left,
          'top': face.boundingBox.top,
          'right': face.boundingBox.right,
          'bottom': face.boundingBox.bottom,
        },
        'landmarks': face.landmarks.map((type, landmark) => MapEntry(
          type.name,
          {'x': landmark?.position.x, 'y': landmark?.position.y}
        )),
      };

      widget.onFaceRegistered(jsonEncode(encoding), image);
      Navigator.pop(context);

    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Registration')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: Main_AxisAlignment.center,
            children: [
              const Icon(Icons.face, size: 100, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                'Register Face Data',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please ensure you are in a well-lit area and looking directly at the camera.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 48),
              if (_isProcessing)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _captureAndProcess,
                    icon: const Icon(Icons.camera),
                    label: const Text('Capture Face'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
