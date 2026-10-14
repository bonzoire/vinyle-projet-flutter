import 'package:flutter/material.dart';
import '../models/vinyl_detection_result.dart';

/// Dessine les cercles du vinyle et les sillons détectés par-dessus l'image.
class VinylOverlayPainter extends CustomPainter {
  final VinylDetectionResult result;
  final Size originalImageSize;

  VinylOverlayPainter({
    required this.result,
    required this.originalImageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!result.isSuccess || result.outerRadius <= 0) return;

    // Calcul du ratio d'échelle entre l'image source et la taille d'affichage à l'écran
    final scaleX = size.width / originalImageSize.width;
    final scaleY = size.height / originalImageSize.height;

    // Adapter le centre
    final centerOffset = Offset(
      result.center.x * scaleX,
      result.center.y * scaleY,
    );

    // Moyenne d'échelle pour les rayons
    final scaleRadius = (scaleX + scaleY) / 2.0;

    // 1. Cercle extérieur du vinyle (Cyan)
    final outerPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(centerOffset, result.outerRadius * scaleRadius, outerPaint);

    // 2. Cercle du macaron central / label (Orange)
    final labelPaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(centerOffset, result.labelRadius * scaleRadius, labelPaint);

    // 3. Point central du disque (Rouge / Jaune)
    final centerPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(centerOffset, 6.0, centerPaint);

    // 4. Sillons / pistes détectés (Vert fluo / Bleu clair)
    final groovePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < result.trackRadii.length; i++) {
      final r = result.trackRadii[i] * scaleRadius;
      canvas.drawCircle(centerOffset, r, groovePaint);

      // Label de piste (ex: "Piste 1", "Piste 2", ...)
      textPainter.text = TextSpan(
        text: ' Piste ${i + 1} ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.7),
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(centerOffset.dx + r - (textPainter.width / 2), centerOffset.dy - 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant VinylOverlayPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.originalImageSize != originalImageSize;
  }
}
