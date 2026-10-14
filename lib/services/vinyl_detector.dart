import 'dart:math';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/vinyl_detection_result.dart';

/// Service responsable de la détection et de l'analyse visuelle des disques vinyles.
class VinylDetector {
  /// Analyse un fichier image situé à [imagePath].
  Future<VinylDetectionResult> detectFromFile(String imagePath) async {
    final mat = cv.imread(imagePath);
    if (mat.isEmpty) {
      return VinylDetectionResult.failure("Impossible de charger l'image depuis $imagePath");
    }
    try {
      return analyzeMat(mat);
    } finally {
      mat.dispose();
    }
  }

  /// Analyse une image fournie sous forme de bytes (ex: photo prise par la caméra).
  Future<VinylDetectionResult> detectFromBytes(Uint8List imageBytes) async {
    final mat = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) {
      return VinylDetectionResult.failure("Impossible de décoder les données de l'image.");
    }
    try {
      return analyzeMat(mat);
    } finally {
      mat.dispose();
    }
  }

  /// Analyse une matrice OpenCV ([cv.Mat]) contenant une vue du disque vinyle.
  VinylDetectionResult analyzeMat(cv.Mat src) {
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? circlesMat;

    try {
      // 1. Prétraitement : Conversion en niveaux de gris si nécessaire
      if (src.channels == 3 || src.channels == 4) {
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      } else {
        gray = src.clone();
      }

      // 2. Flou gaussien pour éliminer le bruit haute fréquence des micro-sillons
      blurred = cv.gaussianBlur(gray, (9, 9), 2.0);

      // 3. Détection du contour circulaire principal (le vinyle) via HoughCircles
      final minDimension = min(src.rows, src.cols);
      final minRadius = (minDimension * 0.25).toInt();
      final maxRadius = (minDimension * 0.52).toInt();

      circlesMat = cv.HoughCircles(
        blurred,
        cv.HOUGH_GRADIENT,
        1.2,
        minDimension / 4,
        param1: 100,
        param2: 45,
        minRadius: minRadius,
        maxRadius: maxRadius,
      );

      if (circlesMat.isEmpty || circlesMat.cols == 0) {
        return VinylDetectionResult.failure("Aucun disque circulaire détecté.");
      }

      // Récupérer le cercle le plus probable (le premier ou le plus proche du centre)
      // HoughCircles retourne une matrice 1 x N x 3 (x, y, rayon)
      double bestX = 0;
      double bestY = 0;
      double bestRadius = 0;

      final imgCenterX = src.cols / 2.0;
      final imgCenterY = src.rows / 2.0;
      double minCenterDistance = double.infinity;

      for (int i = 0; i < circlesMat.cols; i++) {
        final circle = circlesMat.at<cv.Vec3f>(0, i);
        final x = circle.val1;
        final y = circle.val2;
        final r = circle.val3;

        final distToCenter = sqrt(pow(x - imgCenterX, 2) + pow(y - imgCenterY, 2));
        if (distToCenter < minCenterDistance) {
          minCenterDistance = distToCenter;
          bestX = x;
          bestY = y;
          bestRadius = r;
        }
      }

      if (bestRadius <= 0) {
        return VinylDetectionResult.failure("Rayon du disque non valide.");
      }

      final center = Point<double>(bestX, bestY);

      // Rayon typique du macaron central (label) : environ 30% à 35% du rayon total
      final labelRadius = bestRadius * 0.33;

      // 4. Analyse des sillons et des séparations de pistes
      final trackRadii = _detectGrooves(
        gray: gray,
        center: center,
        labelRadius: labelRadius,
        outerRadius: bestRadius,
      );

      return VinylDetectionResult(
        center: center,
        outerRadius: bestRadius,
        labelRadius: labelRadius,
        trackRadii: trackRadii,
      );
    } catch (e) {
      return VinylDetectionResult.failure("Erreur lors de l'analyse : $e");
    } finally {
      gray?.dispose();
      blurred?.dispose();
      circlesMat?.dispose();
    }
  }

  /// Détecte les transitions entre pistes en calculant le profil radial d'intensité.
  List<double> _detectGrooves({
    required cv.Mat gray,
    required Point<double> center,
    required double labelRadius,
    required double outerRadius,
  }) {
    final List<double> detectedTracks = [];

    // On explore la zone musicale : entre le label (~35% du rayon) et le bord extérieur (~95%)
    final startR = (labelRadius * 1.05).toInt();
    final endR = (outerRadius * 0.95).toInt();

    if (endR <= startR) return detectedTracks;

    const sampleAngles = 36; // Échantillonne tous les 10 degrés
    final radialIntensity = <int, double>{};
    final grayData = gray.data;
    final rowStride = gray.step.$1;
    final cols = gray.cols;
    final rows = gray.rows;

    for (int r = startR; r <= endR; r += 2) {
      double sum = 0;
      int validSamples = 0;

      for (int a = 0; a < sampleAngles; a++) {
        final theta = (a * 2 * pi) / sampleAngles;
        final px = (center.x + r * cos(theta)).round();
        final py = (center.y + r * sin(theta)).round();

        if (px >= 0 && px < cols && py >= 0 && py < rows) {
          sum += grayData[py * rowStride + px];
          validSamples++;
        }
      }

      if (validSamples > 0) {
        radialIntensity[r] = sum / validSamples;
      }
    }

    // Détection des pics / creux représentant les bandes inter-pistes (silences)
    final radii = radialIntensity.keys.toList()..sort();
    if (radii.length < 5) return detectedTracks;

    // Calcul du gradient (dérivée première) pour trouver les changements de texture
    final minDistanceBetweenTracks = (outerRadius - labelRadius) * 0.08;
    double lastTrackRadius = 0;

    for (int i = 2; i < radii.length - 2; i++) {
      final r = radii[i];
      final val = radialIntensity[r]!;
      final prevVal = radialIntensity[radii[i - 1]]!;
      final nextVal = radialIntensity[radii[i + 1]]!;

      // Recherche d'un creux local ou pic local d'intensité caractéristique
      final isLocalMin = val < prevVal && val < nextVal;
      final isSignificant = (prevVal - val).abs() > 2.0 || (nextVal - val).abs() > 2.0;

      if (isLocalMin && isSignificant) {
        if (lastTrackRadius == 0 || (r - lastTrackRadius) > minDistanceBetweenTracks) {
          detectedTracks.add(r.toDouble());
          lastTrackRadius = r.toDouble();
        }
      }
    }

    return detectedTracks;
  }
}
