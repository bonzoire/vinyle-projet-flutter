import 'dart:math';

/// Représente le résultat de l'analyse d'un disque vinyle par OpenCV.
class VinylDetectionResult {
  /// Centre détecté du disque vinyle (en pixels dans l'image source).
  final Point<double> center;

  /// Rayon extérieur principal du disque vinyle (grand demi-axe en pixels).
  final double outerRadius;

  /// Rayon approximatif de l'étiquette centrale (label).
  final double labelRadius;

  /// Demi-grand axe de l'ellipse (équivalent à outerRadius).
  final double ellipseMajorRadius;

  /// Demi-petit axe de l'ellipse (en pixels).
  final double ellipseMinorRadius;

  /// Angle d'orientation de l'ellipse (en degrés).
  final double ellipseAngle;

  /// Indique si la détection provient d'une ellipse inclinée (true) ou d'un fallback circulaire (false).
  final bool isEllipse;

  /// Liste des rayons correspondants aux sillons / séparations de pistes détectés (sur le grand axe).
  final List<double> trackRadii;

  /// Ratios normalisés de chaque sillon par rapport au grand rayon [0.0 - 1.0].
  final List<double> trackRatios;

  /// Nombre de pistes détectées.
  int get trackCount => trackRadii.isEmpty ? 0 : trackRadii.length + 1;

  /// Indique si la détection a réussi à localiser un vinyle.
  final bool isSuccess;

  /// Message d'erreur éventuel en cas d'échec.
  final String? errorMessage;

  const VinylDetectionResult({
    required this.center,
    required this.outerRadius,
    required this.labelRadius,
    required this.ellipseMajorRadius,
    required this.ellipseMinorRadius,
    this.ellipseAngle = 0.0,
    this.isEllipse = false,
    required this.trackRadii,
    required this.trackRatios,
    this.isSuccess = true,
    this.errorMessage,
  });

  /// Constructeur de secours pour cercle strict ou fallback.
  factory VinylDetectionResult.circular({
    required Point<double> center,
    required double radius,
    required double labelRadius,
    required List<double> trackRadii,
    required List<double> trackRatios,
  }) {
    return VinylDetectionResult(
      center: center,
      outerRadius: radius,
      labelRadius: labelRadius,
      ellipseMajorRadius: radius,
      ellipseMinorRadius: radius,
      ellipseAngle: 0.0,
      isEllipse: false,
      trackRadii: trackRadii,
      trackRatios: trackRatios,
      isSuccess: true,
    );
  }

  /// Constructeur pour détection d'ellipse (tolérante à l'inclinaison).
  factory VinylDetectionResult.elliptical({
    required Point<double> center,
    required double majorRadius,
    required double minorRadius,
    required double angle,
    required double labelRadius,
    required List<double> trackRadii,
    required List<double> trackRatios,
  }) {
    return VinylDetectionResult(
      center: center,
      outerRadius: majorRadius,
      labelRadius: labelRadius,
      ellipseMajorRadius: majorRadius,
      ellipseMinorRadius: minorRadius,
      ellipseAngle: angle,
      isEllipse: true,
      trackRadii: trackRadii,
      trackRatios: trackRatios,
      isSuccess: true,
    );
  }

  factory VinylDetectionResult.failure(String message) {
    return VinylDetectionResult(
      center: const Point(0, 0),
      outerRadius: 0,
      labelRadius: 0,
      ellipseMajorRadius: 0,
      ellipseMinorRadius: 0,
      ellipseAngle: 0,
      isEllipse: false,
      trackRadii: const [],
      trackRatios: const [],
      isSuccess: false,
      errorMessage: message,
    );
  }

  @override
  String toString() {
    if (!isSuccess) return 'VinylDetectionResult(Failed: $errorMessage)';
    return 'VinylDetectionResult(center: ($center), a: ${ellipseMajorRadius.toStringAsFixed(1)}, '
        'b: ${ellipseMinorRadius.toStringAsFixed(1)}, angle: ${ellipseAngle.toStringAsFixed(1)}°, '
        'tracks: ${trackRadii.length})';
  }
}
