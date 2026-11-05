import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/smart_document_type.dart';
import 'utils.dart';

/// Intelligent document auto-cropper and deskewer for all document types:
/// - KTP (ID-1 aspect ratio 1.5858)
/// - Kartu Keluarga (Landscape A4/Folio aspect ratio ~1.414)
/// - Surat Keterangan Sehat (Portrait A4 aspect ratio ~0.707)
class DocumentCropper {
  DocumentCropper._();

  /// Crops any document based on [SmartDocumentType].
  static Future<File?> cropDocument(
    File imageFile,
    SmartDocumentType type,
  ) async {
    try {
      final TextRecognizer recognizer = TextRecognizer();
      final InputImage inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);
      await recognizer.close();

      if (recognizedText.blocks.isEmpty) return null;

      // 1. Calculate dominant document skew/tilt angle from text line orientations
      final List<double> angles = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          if (line.cornerPoints.length >= 2) {
            final p0 = line.cornerPoints[0];
            final p1 = line.cornerPoints[1];
            final dx = (p1.x - p0.x).toDouble();
            final dy = (p1.y - p0.y).toDouble();
            if (dx.abs() >= 25) {
              final a = atan2(dy, dx) * 180.0 / pi;
              if (a.abs() <= 35.0) {
                angles.add(a);
              }
            }
          }
        }
      }

      double tiltAngle = 0.0;
      if (angles.isNotEmpty) {
        angles.sort();
        tiltAngle = angles[angles.length ~/ 2];
      }

      final double rad = tiltAngle * pi / 180.0;
      final double cosT = cos(rad);
      final double sinT = sin(rad);

      double minU = double.infinity;
      double maxU = -double.infinity;
      double minV = double.infinity;
      double maxV = -double.infinity;

      void updateUV(double x, double y) {
        final double u = x * cosT + y * sinT;
        final double v = -x * sinT + y * cosT;
        if (u < minU) minU = u;
        if (u > maxU) maxU = u;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }

      // Collect bounding coordinates from relevant text blocks
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          if (line.cornerPoints.isNotEmpty) {
            for (final p in line.cornerPoints) {
              updateUV(p.x.toDouble(), p.y.toDouble());
            }
          } else {
            final r = line.boundingBox;
            updateUV(r.left, r.top);
            updateUV(r.right, r.top);
            updateUV(r.right, r.bottom);
            updateUV(r.left, r.bottom);
          }
        }
      }

      if (minU >= maxU || minV >= maxV) return null;

      final double textW = maxU - minU;
      final double textH = maxV - minV;
      if (textW < 40 || textH < 40) return null;

      // Add appropriate margins around text bounding box according to document type
      double padX;
      double padY;

      switch (type) {
        case SmartDocumentType.ktp:
          // KTP has profile photo on the right: text spans ~85% of height and ~75% of width
          padX = textW * 0.18;
          padY = textH * 0.14;
          break;
        case SmartDocumentType.kartuKeluarga:
          // KK is wide A4 sheet with borders around family tables: add 5-8% padding
          padX = textW * 0.06;
          padY = textH * 0.08;
          break;
        case SmartDocumentType.suratSehat:
          // Medical certificate is portrait A4: add margins for headers and stamps/signatures
          padX = textW * 0.08;
          padY = textH * 0.10;
          break;
      }

      final double docULeft = minU - padX;
      final double docUTop = minV - padY;
      final double docW = textW + (padX * 2);
      final double docH = textH + (padY * 2);

      final double docUCenter = docULeft + (docW / 2.0);
      final double docVCenter = docUTop + (docH / 2.0);

      // Back-project center to original image coordinates
      final double docCenterX = docUCenter * cosT - docVCenter * sinT;
      final double docCenterY = docUCenter * sinT + docVCenter * cosT;

      return await cropAndDeskewImage(
        imageFile,
        Rect.fromCenter(
          center: Offset(docCenterX, docCenterY),
          width: docW,
          height: docH,
        ),
        angleDegrees: tiltAngle,
      );
    } catch (_) {
      return null;
    }
  }
}
