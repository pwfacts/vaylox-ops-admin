import 'dart:convert';
import 'dart:math';

class FaceComparisonService {
  /// Compares current landmarks with registered landmarks.
  /// Returns a similarity score between 0.0 and 1.0.
  double calculateMatchScore(String currentEncoding, String registeredEncoding) {
    try {
      final List<dynamic> current = jsonDecode(currentEncoding);
      final List<dynamic> registered = jsonDecode(registeredEncoding);

      if (current.isEmpty || registered.isEmpty) return 0.0;

      // We compare the relative positions of key landmarks (Eyes, Nose, Mouth)
      // This is a simplified version of face matching for the foundation phase.
      // In production, you would use TFLite FaceNet embeddings (128-d vectors).
      
      double totalDistance = 0;
      int count = min(current.length, registered.length);

      for (int i = 0; i < count; i++) {
        final d1 = current[i];
        final d2 = registered[i];
        
        // Calculate Euclidean distance between points (normalized by image size)
        double dx = d1['x'] - d2['x'];
        double dy = d1['y'] - d2['y'];
        totalDistance += sqrt(dx * dx + dy * dy);
      }

      // Average distance (closer to 0 is better)
      double avgDist = totalDistance / count;

      // Map distance to a score 0-1 (heuristic: distance > 50 is a fail)
      double score = max(0.0, 1.0 - (avgDist / 50.0));
      
      return score;
    } catch (e) {
      return 0.0;
    }
  }
}
