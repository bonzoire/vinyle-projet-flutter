import 'dart:math';

/// Représente le résultat de l'analyse d'un disque vinyle par OpenCV.
class VinylDetectionResult {
  /// Centre détecté du disque vinyle (en pixels).
  final Point<double> center;

  /// Rayon extérieur du disque vinyle (en pixels).
  final double outerRadius;

  /// Rayon approximatif de l'étiquette centrale (label).
  final double labelRadius;

  /// Liste des rayons correspondants aux sillons / séparations de pistes détectés.
  final List<double> trackRadii;

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
    required this.trackRadii,
    this.isSuccess = true,
    this.errorMessage,
  });

  factory VinylDetectionResult.failure(String message) {
    return VinylDetectionResult(
      center: const Point(0, 0),
      outerRadius: 0,
      labelRadius: 0,
      trackRadii: const [],
      isSuccess: false,
      errorMessage: message,
    );
  }

  @override
  String toString() {
    if (!isSuccess) return 'VinylDetectionResult(Failed: $errorMessage)';
    return 'VinylDetectionResult(center: ($center), outerRadius: ${outerRadius.toStringAsFixed(1)}, '
        'labelRadius: ${labelRadius.toStringAsFixed(1)}, tracks: ${trackRadii.length})';
  }
}
