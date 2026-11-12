import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../models/smart_document_type.dart';

/// Intelligent document auto-cropper, deskewer, and image enhancer for all document types:
/// - KTP (ID-1 aspect ratio 1.5858)
/// - SIM (ID-1 aspect ratio 1.5858)
/// - Kartu Keluarga (Landscape A4/Folio aspect ratio ~1.414)
/// - Surat Keterangan Sehat (Portrait A4 aspect ratio ~0.707)
class DocumentCropper {
  DocumentCropper._();

  /// Crops, deskews, and sharpens any document based on [SmartDocumentType].
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

      // Collect bounding coordinates from all recognized lines
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
      double padLeft;
      double padRight;
      double padTop;
      double padBottom;
      double targetRatio;

      switch (type) {
        case SmartDocumentType.ktp:
        case SmartDocumentType.sim:
          // ID-1 standard cards (85.6mm x 53.98mm = ~1.5858 ratio)
          // Profile photo sits on the right side (~30% of card width)
          targetRatio = 1.5858;
          padLeft = textW * 0.06;
          padRight = textW * 0.32; // Give ample room for the photo on the right
          padTop = textH * 0.10;
          padBottom = textH * 0.12;
          break;

        case SmartDocumentType.kartuKeluarga:
          // KK is wide A4 sheet (landscape ~1.414 ratio)
          // Table layout has borders, signatures at bottom, headers at top
          targetRatio = 1.4142;
          padLeft = textW * 0.05;
          padRight = textW * 0.05;
          padTop = textH * 0.08;
          padBottom = textH * 0.10;
          break;

        case SmartDocumentType.suratSehat:
          // Medical certificate is portrait A4 sheet (~0.7071 ratio)
          // Header kop at top, stamps & signatures at bottom
          targetRatio = 0.7071;
          padLeft = textW * 0.08;
          padRight = textW * 0.08;
          padTop = textH * 0.12;
          padBottom = textH * 0.15;
          break;
      }

      double docULeft = minU - padLeft;
      double docURight = maxU + padRight;
      double docUTop = minV - padTop;
      double docUBottom = maxV + padBottom;

      double docW = docURight - docULeft;
      double docH = docUBottom - docUTop;

      // Conform to the natural aspect ratio of the document
      final double currentRatio = docW / docH;
      if (currentRatio < targetRatio) {
        // Too tall: expand width symmetrically
        final double neededW = docH * targetRatio;
        final double extraW = (neededW - docW) / 2.0;
        docULeft -= extraW;
        docURight += extraW;
        docW = neededW;
      } else {
        // Too wide: expand height symmetrically
        final double neededH = docW / targetRatio;
        final double extraH = (neededH - docH) / 2.0;
        docUTop -= extraH;
        docUBottom += extraH;
        docH = neededH;
      }

      // Convert back to original 4 corners in image coordinates
      Offset toXY(double u, double v) {
        return Offset(
          u * cosT - v * sinT,
          u * sinT + v * cosT,
        );
      }

      final tl = toXY(docULeft, docUTop);
      final tr = toXY(docURight, docUTop);
      final bl = toXY(docULeft, docUBottom);
      final br = toXY(docURight, docUBottom);

      return await _cropDeskewAndEnhance(
        imageFile: imageFile,
        tl: tl,
        tr: tr,
        bl: bl,
        br: br,
        targetWidth: type == SmartDocumentType.suratSehat ? 1000 : 1280,
        targetRatio: targetRatio,
      );
    } catch (_) {
      return null;
    }
  }

  /// Rectifies perspective, crops, enhances contrast, and applies unsharp mask
  /// to make text and document details razor-sharp.
  static Future<File?> _cropDeskewAndEnhance({
    required File imageFile,
    required Offset tl,
    required Offset tr,
    required Offset bl,
    required Offset br,
    required int targetWidth,
    required double targetRatio,
  }) async {
    var image = await img.decodeImageFile(imageFile.absolute.path);
    if (image == null) return null;
    image = img.bakeOrientation(image);

    final int imgW = image.width;
    final int imgH = image.height;

    // Clamp corner points to image boundaries
    int cx(double v) => v.round().clamp(0, imgW - 1);
    int cy(double v) => v.round().clamp(0, imgH - 1);

    final int outW = targetWidth;
    final int outH = (targetWidth / targetRatio).round();

    // 1. Perspective Rectification (straighten skew, roll & tilt)
    final rectified = img.copyRectify(
      image,
      topLeft: img.Point(cx(tl.dx), cy(tl.dy)),
      topRight: img.Point(cx(tr.dx), cy(tr.dy)),
      bottomLeft: img.Point(cx(bl.dx), cy(bl.dy)),
      bottomRight: img.Point(cx(br.dx), cy(br.dy)),
      toImage: img.Image(width: outW, height: outH),
      interpolation: img.Interpolation.linear,
    );

    // 2. Enhance image: Contrast stretch & sharpening convolution for crisp text
    img.Image enhanced = rectified;
    try {
      // Adjust contrast (+12%) to make dark text stand out against light paper/plastic
      enhanced = img.contrast(enhanced, contrast: 112);

      // Apply 3x3 sharpening convolution kernel
      // [ 0, -1,  0]
      // [-1,  5, -1]
      // [ 0, -1,  0]
      enhanced = img.convolution(
        enhanced,
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
        div: 1,
        offset: 0,
      );
    } catch (_) {
      enhanced = rectified;
    }

    final List<int> encoded = img.encodeJpg(enhanced, quality: 96);
    final String outputPath =
        '${imageFile.parent.path}/doc_enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File resultFile = File(outputPath);
    await resultFile.writeAsBytes(encoded);
    return resultFile;
  }
}
