import 'dart:math';
import 'package:flutter/material.dart';
import '../models/vinyl_detection_result.dart';

/// Dessine les contours du disque vinyle (cercle ou ellipse orientée)
/// et les sillons détectés par-dessus l'image.
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

    // Calcul du ratio d'échelle entre l'image source et la taille d'affichage
    final scaleX = size.width / originalImageSize.width;
    final scaleY = size.height / originalImageSize.height;
    final scale = (scaleX + scaleY) / 2.0;

    // Coordonnées du centre adapté à l'écran
    final centerOffset = Offset(
      result.center.x * scaleX,
      result.center.y * scaleY,
    );

    final majorRadius = result.ellipseMajorRadius * scale;
    final minorRadius = result.ellipseMinorRadius * scale;
    final angleRad = result.ellipseAngle * (pi / 180.0);

    // 1. Définition des styles graphiques
    final outerPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final labelPaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final groovePaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final centerPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    // 2. Tracé orienté dans le repère de l'ellipse
    canvas.save();
    canvas.translate(centerOffset.dx, centerOffset.dy);
    canvas.rotate(angleRad);

    // Contour externe (Cyan)
    final outerRect = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * majorRadius,
      height: 2 * minorRadius,
    );
    canvas.drawOval(outerRect, outerPaint);

    // Macaron central / label (Orange)
    final labelRatio = result.outerRadius > 0 ? result.labelRadius / result.outerRadius : 0.33;
    final labelRect = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * majorRadius * labelRatio,
      height: 2 * minorRadius * labelRatio,
    );
    canvas.drawOval(labelRect, labelPaint);

    // Tracé de chaque sillon et de son étiquette
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < result.trackRatios.length; i++) {
      final ratio = result.trackRatios[i];

      // Anneau du sillon
      final trackRect = Rect.fromCenter(
        center: Offset.zero,
        width: 2 * majorRadius * ratio,
        height: 2 * minorRadius * ratio,
      );
      canvas.drawOval(trackRect, groovePaint);

      // Étiquette de piste positionnée sur le grand axe, réalignée horizontalement
      final posX = majorRadius * ratio;
      canvas.save();
      canvas.translate(posX, 0);
      canvas.rotate(-angleRad); // Contre-rotation pour garder le texte droit

      textPainter.text = TextSpan(
        text: ' Piste ${i + 1} ',
        style: TextStyle(
          color: Colors.white,
          fontSize: (11 * scale).clamp(9.0, 14.0),
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withValues(alpha: 0.75),
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }

    canvas.restore();

    // 3. Point central du disque
    canvas.drawCircle(centerOffset, 6.0 * scale.clamp(0.8, 1.5), centerPaint);
  }

  @override
  bool shouldRepaint(covariant VinylOverlayPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.originalImageSize != originalImageSize;
  }
}
