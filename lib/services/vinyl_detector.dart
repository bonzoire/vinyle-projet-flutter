import 'dart:math';
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../models/vinyl_detection_result.dart';

/// Service responsable de la détection et de l'analyse visuelle des disques vinyles.
/// Supporte le cadrage avec perspective (détection d'ellipse et rectification canonique)
/// ainsi que l'extraction texturale robuste (Sobel polaire + médiane angulaire).
class VinylDetector {
  /// Taille de l'espace carré canonique pour le redressement de perspective.
  static const int _canonicalSize = 1000;

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
    if (src.isEmpty) {
      return VinylDetectionResult.failure("Image source vide.");
    }

    final origW = src.cols;
    final origH = src.rows;

    // ------------------------------------------------------------------------
    // Étape 1 : Localisation tolérante à l'angle (Détection d'ellipse)
    // ------------------------------------------------------------------------
    final maxDim = max(origW, origH);
    final double downscale = maxDim > 1024 ? 1024.0 / maxDim : 1.0;

    cv.Mat? workMat;
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? edges;
    cv.Mat? kernel;
    cv.Mat? closed;
    cv.VecVecPoint? contours;
    cv.VecVec4i? hierarchy;

    cv.RotatedRect? bestEllipse;
    double bestEllipseArea = 0;

    try {
      if (downscale < 1.0) {
        workMat = cv.resize(
          src,
          ((origW * downscale).round(), (origH * downscale).round()),
          interpolation: cv.INTER_AREA,
        );
      } else {
        workMat = src.clone();
      }

      // Conversion en niveaux de gris
      if (workMat.channels == 3 || workMat.channels == 4) {
        gray = cv.cvtColor(workMat, cv.COLOR_BGR2GRAY);
      } else {
        gray = workMat.clone();
      }

      // Léger flou gaussien pour lisser le bruit
      blurred = cv.gaussianBlur(gray, (5, 5), 1.5);

      // Détection de contours via Canny + fermeture morphologique
      edges = cv.canny(blurred, 30, 100);
      kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (7, 7));
      closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);

      final contoursRes = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = contoursRes.$1;
      hierarchy = contoursRes.$2;

      final minContourArea = (workMat.cols * workMat.rows) * 0.08;

      for (int i = 0; i < contours.length; i++) {
        final c = contours[i];
        if (c.length < 5) continue;

        final area = cv.contourArea(c);
        if (area < minContourArea) continue;

        final rotRect = cv.fitEllipse(c);
        final w = rotRect.size.width;
        final h = rotRect.size.height;
        if (w <= 0 || h <= 0) continue;

        final majorAxis = max(w, h);
        final minorAxis = min(w, h);
        final axisRatio = minorAxis / majorAxis;

        // Tolérance d'inclinaison : ratio petit_axe / grand_axe >= 0.45 (inclinaison jusqu'à ~63°)
        if (axisRatio >= 0.45) {
          final ellipseArea = pi * (majorAxis / 2) * (minorAxis / 2);
          if (ellipseArea > bestEllipseArea) {
            bestEllipseArea = ellipseArea;
            bestEllipse = rotRect;
          }
        }
      }
    } catch (_) {
      // En cas d'erreur sur l'extraction d'ellipse, on tente le fallback
    } finally {
      workMat?.dispose();
      gray?.dispose();
      blurred?.dispose();
      edges?.dispose();
      kernel?.dispose();
      closed?.dispose();
      contours?.dispose();
      hierarchy?.dispose();
    }

    // Fallback circulaire si fitEllipse n'a rien trouvé de probant
    cv.RotatedRect resolvedEllipse;
    bool isEllipseMode = true;

    if (bestEllipse != null) {
      // Remise à l'échelle de l'ellipse sur les dimensions originales
      final scaleFactor = 1.0 / downscale;
      final cx = bestEllipse.center.x * scaleFactor;
      final cy = bestEllipse.center.y * scaleFactor;
      final w = bestEllipse.size.width * scaleFactor;
      final h = bestEllipse.size.height * scaleFactor;
      final angle = bestEllipse.angle;

      resolvedEllipse = cv.RotatedRect(
        cv.Point2f(cx, cy),
        (w, h),
        angle,
      );
    } else {
      // Repli sur HoughCircles
      final fallbackResult = _fallbackHoughCircles(src);
      if (fallbackResult == null) {
        return VinylDetectionResult.failure("Aucun disque vinyle détecté.");
      }
      resolvedEllipse = fallbackResult;
      isEllipseMode = false;
    }

    // Paramètres finaux du disque
    final origMajorRadius = max(resolvedEllipse.size.width, resolvedEllipse.size.height) / 2.0;
    final origMinorRadius = min(resolvedEllipse.size.width, resolvedEllipse.size.height) / 2.0;
    final origCenter = Point<double>(resolvedEllipse.center.x, resolvedEllipse.center.y);
    final origAngle = resolvedEllipse.angle;

    if (origMajorRadius <= 0) {
      return VinylDetectionResult.failure("Rayon du disque non valide.");
    }

    // ------------------------------------------------------------------------
    // Étape 2 : Rectification de perspective vers espace canonique
    // ------------------------------------------------------------------------
    cv.Mat? warpedMat;
    cv.Mat? polarMat;
    cv.VecPoint2f? boxPts;
    cv.VecPoint2f? srcPts;
    cv.VecPoint2f? dstPts;
    cv.Mat? hMat;

    List<double> trackRatios = [];

    try {
      boxPts = cv.boxPoints(resolvedEllipse);
      final orderedCorners = _orderBoxPoints(boxPts);

      srcPts = cv.VecPoint2f.fromList(orderedCorners);
      dstPts = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(_canonicalSize.toDouble(), 0),
        cv.Point2f(_canonicalSize.toDouble(), _canonicalSize.toDouble()),
        cv.Point2f(0, _canonicalSize.toDouble()),
      ]);

      hMat = cv.getPerspectiveTransform2f(srcPts, dstPts);
      warpedMat = cv.warpPerspective(src, hMat, (_canonicalSize, _canonicalSize));

      // ------------------------------------------------------------------------
      // Étape 3 : Déroulement Polaire natif OpenCV (cv.linearPolar)
      // ------------------------------------------------------------------------
      const halfSize = _canonicalSize / 2.0;
      polarMat = cv.linearPolar(
        warpedMat,
        cv.Point2f(halfSize, halfSize),
        halfSize,
        cv.INTER_LINEAR,
      );

      // ------------------------------------------------------------------------
      // Étape 4 : Extraction des sillons texturale & robuste (Sobel + Médiane)
      // ------------------------------------------------------------------------
      trackRatios = _detectGroovesFromPolar(polarMat);
    } catch (e) {
      return VinylDetectionResult.failure("Erreur lors de l'analyse polaire : $e");
    } finally {
      boxPts?.dispose();
      srcPts?.dispose();
      dstPts?.dispose();
      hMat?.dispose();
      warpedMat?.dispose();
      polarMat?.dispose();
    }

    // Calcul des rayons de chaque piste pour l'image d'origine
    final trackRadii = trackRatios.map((r) => r * origMajorRadius).toList();
    final labelRadius = origMajorRadius * 0.33;

    if (isEllipseMode) {
      return VinylDetectionResult.elliptical(
        center: origCenter,
        majorRadius: origMajorRadius,
        minorRadius: origMinorRadius,
        angle: origAngle,
        labelRadius: labelRadius,
        trackRadii: trackRadii,
        trackRatios: trackRatios,
      );
    } else {
      return VinylDetectionResult.circular(
        center: origCenter,
        radius: origMajorRadius,
        labelRadius: labelRadius,
        trackRadii: trackRadii,
        trackRatios: trackRatios,
      );
    }
  }

  /// Repli de secours via HoughCircles si la détection d'ellipse échoue.
  cv.RotatedRect? _fallbackHoughCircles(cv.Mat src) {
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? circlesMat;

    try {
      if (src.channels == 3 || src.channels == 4) {
        gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
      } else {
        gray = src.clone();
      }

      blurred = cv.gaussianBlur(gray, (9, 9), 2.0);

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
        return null;
      }

      final imgCenterX = src.cols / 2.0;
      final imgCenterY = src.rows / 2.0;
      double minCenterDistance = double.infinity;
      double bestX = 0;
      double bestY = 0;
      double bestRadius = 0;

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

      if (bestRadius <= 0) return null;

      return cv.RotatedRect(
        cv.Point2f(bestX, bestY),
        (bestRadius * 2, bestRadius * 2),
        0.0,
      );
    } catch (_) {
      return null;
    } finally {
      gray?.dispose();
      blurred?.dispose();
      circlesMat?.dispose();
    }
  }

  /// Ordonne les 4 sommets d'un rectangle orienté : Top-Left, Top-Right, Bottom-Right, Bottom-Left.
  List<cv.Point2f> _orderBoxPoints(cv.VecPoint2f boxPts) {
    final pts = [boxPts[0], boxPts[1], boxPts[2], boxPts[3]];

    // Tri selon la somme (x + y) : le plus petit est Top-Left, le plus grand est Bottom-Right
    pts.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = pts[0];
    final br = pts[3];

    // Les deux autres sommets correspondent à Top-Right et Bottom-Left
    final remaining = [pts[1], pts[2]];
    // Tri selon la différence (y - x) : le plus petit est Top-Right, le plus grand est Bottom-Left
    remaining.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final tr = remaining[0];
    final bl = remaining[1];

    return [tl, tr, br, bl];
  }

  /// Analyse la texture des sillons sur l'image déroulée polaire (axe X = rayon r, axe Y = angle θ).
  /// Utilise le canal L de Lab + CLAHE + filtre Sobel horizontal + médiane angulaire.
  List<double> _detectGroovesFromPolar(cv.Mat polar) {
    final cols = polar.cols;
    final rows = polar.rows;

    cv.Mat? lab;
    cv.VecMat? channels;
    cv.Mat? lChannel;
    cv.CLAHE? clahe;
    cv.Mat? enhancedL;
    cv.Mat? sobelX;
    cv.Mat? absSobel;

    try {
      // 1. Conversion en Lab et extraction du canal Luminance L
      lab = cv.cvtColor(polar, cv.COLOR_BGR2Lab);
      channels = cv.split(lab);
      lChannel = channels[0];

      // 2. Égalisation adaptative de contraste CLAHE (atténue les forts gradients d'éclairage)
      clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
      enhancedL = clahe.apply(lChannel);

      // 3. Dérivée horizontale Sobel (dx=1, dy=0) : mesure directe de la variation texturale radiale
      sobelX = cv.sobel(enhancedL, cv.MatType.CV_16S, 1, 0, ksize: 3);
      absSobel = cv.convertScaleAbs(sobelX);

      // 4. Délimitation de la zone musicale utile (du macaron ~33% au bord externe ~96%)
      final startX = (cols * 0.33).toInt();
      final endX = (cols * 0.96).toInt();
      if (endX <= startX) return [];

      final usefulWidth = endX - startX;
      final rawProfile = List<double>.filled(usefulWidth, 0.0);

      final absData = absSobel.data;
      final rowStride = absSobel.step.$1;

      // 5. Agrégation angulaire robuste par MÉDIANE (rejet à 100% du cône de flash et des splatters)
      // On sous-échantillonne 180 angles réguliers sur les 360°
      const sampleAngleCount = 180;
      final stepY = rows / sampleAngleCount;
      final counts = Int32List(256);

      for (int i = 0; i < usefulWidth; i++) {
        final x = startX + i;
        counts.fillRange(0, 256, 0);

        for (int a = 0; a < sampleAngleCount; a++) {
          final y = (a * stepY).toInt();
          final val = absData[y * rowStride + x];
          counts[val]++;
        }

        // Calcul de la médiane via l'histogramme de comptage (O(N))
        int cumulative = 0;
        int medianVal = 0;
        const halfSamples = sampleAngleCount ~/ 2;
        for (int v = 0; v < 256; v++) {
          cumulative += counts[v];
          if (cumulative >= halfSamples) {
            medianVal = v;
            break;
          }
        }
        rawProfile[i] = medianVal.toDouble();
      }

      // 6. Lissage léger du profil 1D (moyenne mobile 5 points)
      final smoothed = List<double>.filled(usefulWidth, 0.0);
      for (int i = 0; i < usefulWidth; i++) {
        double sum = 0;
        int count = 0;
        for (int k = -2; k <= 2; k++) {
          final idx = i + k;
          if (idx >= 0 && idx < usefulWidth) {
            sum += rawProfile[idx];
            count++;
          }
        }
        smoothed[i] = sum / count;
      }

      // 7. Calcul de la tendance de fond / baseline (moyenne mobile large sur 35 points)
      final baseline = List<double>.filled(usefulWidth, 0.0);
      const baselineHalfWin = 17;
      for (int i = 0; i < usefulWidth; i++) {
        double sum = 0;
        int count = 0;
        for (int k = -baselineHalfWin; k <= baselineHalfWin; k++) {
          final idx = i + k;
          if (idx >= 0 && idx < usefulWidth) {
            sum += smoothed[idx];
            count++;
          }
        }
        baseline[i] = sum / count;
      }

      // 8. Détection adaptative des creux d'énergie texturale (zones de silence lisses)
      // Écartement minimal entre pistes : au moins 3.5% de la largeur musicale
      final minDistance = usefulWidth * 0.035;
      final List<double> detectedRatios = [];
      double lastX = -minDistance;

      for (int i = 2; i < usefulWidth - 2; i++) {
        final delta = smoothed[i] - baseline[i];
        final prevDelta = smoothed[i - 1] - baseline[i - 1];
        final nextDelta = smoothed[i + 1] - baseline[i + 1];

        // Creux local significatif
        final isLocalMin = smoothed[i] <= smoothed[i - 1] &&
            smoothed[i] <= smoothed[i + 1] &&
            smoothed[i] <= smoothed[i - 2] &&
            smoothed[i] <= smoothed[i + 2];

        // Le creux doit être nettement en dessous de la baseline
        final isDrop = delta < -1.2 && delta < prevDelta && delta < nextDelta;

        if (isLocalMin && isDrop) {
          final currentX = (startX + i).toDouble();
          if ((currentX - lastX) >= minDistance) {
            final ratio = currentX / cols;
            detectedRatios.add(ratio);
            lastX = currentX;
          }
        }
      }

      return detectedRatios;
    } finally {
      lab?.dispose();
      channels?.dispose();
      lChannel?.dispose();
      clahe?.dispose();
      enhancedL?.dispose();
      sobelX?.dispose();
      absSobel?.dispose();
    }
  }
}
