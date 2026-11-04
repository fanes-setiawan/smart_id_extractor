import 'dart:io';
import 'dart:math';

import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'ext.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

Future<String> getAssetPath(String asset) async {
  final path = await getLocalPath(asset);
  await Directory(dirname(path)).create(recursive: true);
  final file = File(path);
  if (!await file.exists()) {
    final byteData = await rootBundle.load(asset);
    await file.writeAsBytes(byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
  }
  return file.path;
}

Future<String> getLocalPath(String path) async {
  return '${(await getApplicationSupportDirectory()).path}/$path';
}

/// Crops the exact card viewfinder viewport region from the full camera capture image.
///
/// Since the user aligns the KTP right into the viewfinder frame on screen,
/// this guarantees a clean, rectangular, unrotated card crop matching the viewfinder.
Future<File?> cropCameraViewport({
  required File imageFile,
  required Size screenSize,
  required Rect viewportRect,
}) async {
  try {
    var parse = await img.decodeImageFile(imageFile.absolute.path);
    if (parse == null) return null;
    parse = img.bakeOrientation(parse);

    final double imgW = parse.width.toDouble();
    final double imgH = parse.height.toDouble();

    // The camera preview in KtpCameraScreen is displayed with BoxFit.cover:
    final double scale = max(screenSize.width / imgW, screenSize.height / imgH);
    final double displayedW = imgW * scale;
    final double displayedH = imgH * scale;

    final double offsetX = (displayedW - screenSize.width) / 2.0;
    final double offsetY = (displayedH - screenSize.height) / 2.0;

    // Map screen viewportRect to image pixel coordinates
    int cropX = ((viewportRect.left + offsetX) / scale).round();
    int cropY = ((viewportRect.top + offsetY) / scale).round();
    int cropW = (viewportRect.width / scale).round();
    int cropH = (viewportRect.height / scale).round();

    // Safe bounds clamping
    cropX = cropX.clamp(0, parse.width - 1);
    cropY = cropY.clamp(0, parse.height - 1);
    cropW = cropW.clamp(1, parse.width - cropX);
    cropH = cropH.clamp(1, parse.height - cropY);

    final cropped = img.copyCrop(
      parse,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    final List<int> cropByte = img.encodeJpg(cropped, quality: 95);
    final String tempPath =
        '${imageFile.parent.path}/ktp_frame_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await File(tempPath).writeAsBytes(cropByte);
  } catch (e) {
    return null;
  }
}
class CardCorners {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;

  const CardCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  /// Center point of the 4 corners.
  Offset get center => Offset(
        (topLeft.dx + topRight.dx + bottomLeft.dx + bottomRight.dx) / 4.0,
        (topLeft.dy + topRight.dy + bottomLeft.dy + bottomRight.dy) / 4.0,
      );

  /// Average width across top and bottom edges.
  double get width =>
      ((topRight - topLeft).distance + (bottomRight - bottomLeft).distance) /
      2.0;

  /// Average height across left and right edges.
  double get height =>
      ((bottomLeft - topLeft).distance + (bottomRight - topRight).distance) /
      2.0;

  /// Orientation angle of the card in degrees (-180 to 180).
  double get angleDegrees {
    final dx = topRight.dx - topLeft.dx;
    final dy = topRight.dy - topLeft.dy;
    return atan2(dy, dx) * 180.0 / pi;
  }

  /// Bounding box enclosing all 4 points.
  Rect get boundingBox {
    final minX = min(min(topLeft.dx, topRight.dx), min(bottomLeft.dx, bottomRight.dx));
    final maxX = max(max(topLeft.dx, topRight.dx), max(bottomLeft.dx, bottomRight.dx));
    final minY = min(min(topLeft.dy, topRight.dy), min(bottomLeft.dy, bottomRight.dy));
    final maxY = max(max(topLeft.dy, topRight.dy), max(bottomLeft.dy, bottomRight.dy));
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Converts the 4 corners into a closed quadrilateral [Path].
  Path toPath() {
    return Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();
  }

  /// Linearly interpolates between two [CardCorners] with parameter [t].
  static CardCorners lerp(CardCorners a, CardCorners b, double t) {
    return CardCorners(
      topLeft: Offset.lerp(a.topLeft, b.topLeft, t)!,
      topRight: Offset.lerp(a.topRight, b.topRight, t)!,
      bottomLeft: Offset.lerp(a.bottomLeft, b.bottomLeft, t)!,
      bottomRight: Offset.lerp(a.bottomRight, b.bottomRight, t)!,
    );
  }

  @override
  String toString() =>
      'CardCorners(TL:(${topLeft.dx.toStringAsFixed(1)},${topLeft.dy.toStringAsFixed(1)}) TR:(${topRight.dx.toStringAsFixed(1)},${topRight.dy.toStringAsFixed(1)}) BR:(${bottomRight.dx.toStringAsFixed(1)},${bottomRight.dy.toStringAsFixed(1)}) BL:(${bottomLeft.dx.toStringAsFixed(1)},${bottomLeft.dy.toStringAsFixed(1)}) w:${width.toStringAsFixed(1)} h:${height.toStringAsFixed(1)} a:${angleDegrees.toStringAsFixed(1)})';

  /// Creates a [CardCorners] instance from an axis-aligned or rotated [Rect].
  static CardCorners fromRect(Rect rect, [double angleDegrees = 0.0]) {
    if (angleDegrees.abs() < 0.1) {
      return CardCorners(
        topLeft: rect.topLeft,
        topRight: rect.topRight,
        bottomLeft: rect.bottomLeft,
        bottomRight: rect.bottomRight,
      );
    }
    final rad = angleDegrees * pi / 180.0;
    final cosT = cos(rad);
    final sinT = sin(rad);
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final hw = rect.width / 2.0;
    final hh = rect.height / 2.0;

    Offset rot(double dx, double dy) {
      return Offset(
        cx + (dx * cosT - dy * sinT),
        cy + (dx * sinT + dy * cosT),
      );
    }

    return CardCorners(
      topLeft: rot(-hw, -hh),
      topRight: rot(hw, -hh),
      bottomLeft: rot(-hw, hh),
      bottomRight: rot(hw, hh),
    );
  }
}

/// Detects real-time flexible 4 corner points of a KTP card from recognized text,
/// supporting Normal, Left/Right Tilt, 3D Perspective Trapezoid, and Free Rotation.
CardCorners? detectFlexibleKtpCorners(
  RecognizedText recognized,
  Size imageSize, {
  InputImageRotation rotation = InputImageRotation.rotation0deg,
  Size? rawImageSize,
}) {
  Offset transformPoint(Point<int> p) {
    if (rotation == InputImageRotation.rotation0deg || rawImageSize == null) {
      return Offset(p.x.toDouble(), p.y.toDouble());
    }
    final double bx = p.x.toDouble();
    final double by = p.y.toDouble();
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Offset(rawImageSize.height - by, bx);
      case InputImageRotation.rotation270deg:
        return Offset(by, rawImageSize.width - bx);
      case InputImageRotation.rotation180deg:
        return Offset(rawImageSize.width - bx, rawImageSize.height - by);
      case InputImageRotation.rotation0deg:
        return Offset(bx, by);
    }
  }

  Offset transformOffset(Offset p) {
    if (rotation == InputImageRotation.rotation0deg || rawImageSize == null) {
      return p;
    }
    final double bx = p.dx;
    final double by = p.dy;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Offset(rawImageSize.height - by, bx);
      case InputImageRotation.rotation270deg:
        return Offset(by, rawImageSize.width - bx);
      case InputImageRotation.rotation180deg:
        return Offset(rawImageSize.width - bx, rawImageSize.height - by);
      case InputImageRotation.rotation0deg:
        return p;
    }
  }

  const List<String> ktpKeywords = [
    'PROVINSI',
    'KABUPATEN',
    'KOTA',
    'NIK',
    'AGAMA',
    'STATUS',
    'PERKAWINAN',
    'KAWIN',
    'DARAH',
    'GOL',
    'INDONESIA',
    'TEMPAT',
    'LAHIR',
    'ALAMAT',
    'ISLAM',
    'KRISTEN',
    'KATHOLIK',
    'HINDU',
    'BUDDHA',
    'PEKERJAAN',
    'BERLAKU',
    'SEUMUR',
    'HIDUP',
    'WARGANEGARA',
    'WNI',
    'KELAMIN',
    'RT/RW',
    'KEL/DESA',
    'KECAMATAN',
    'REPUBLIK',
    'DAERAH',
    'ISTIMEWA',
    'NAMA',
  ];

  final String fullText = recognized.text.toUpperCase();
  int matchedKeywords = 0;
  for (final kw in ktpKeywords) {
    if (fullText.contains(kw)) matchedKeywords++;
  }

  bool isNikLine(String text) {
    final clean = text.toUpperCase().replaceAll(' ', '');
    if (clean.contains('NIK')) return true;

    final digits = text.filterNumbersOnly();
    if (digits.length >= 14 && digits.length <= 18) return true;

    // Check tokens for OCR-B character confusions (3->E/t/B, 0->O/D, 1->I/L/l, 4->h/A, 7->T)
    const digitLikeChars = '0123456789OoDIlLiTtEAhSsbGBZz';
    for (final token in clean.split(RegExp(r'[^A-Z0-9]'))) {
      if (token.length >= 14 && token.length <= 18) {
        int matchCount = 0;
        for (int i = 0; i < token.length; i++) {
          if (digitLikeChars.contains(token[i])) matchCount++;
        }
        if (matchCount / token.length >= 0.75) {
          return true;
        }
      }
    }
    return false;
  }

  bool hasNik = false;
  for (final block in recognized.blocks) {
    for (final line in block.lines) {
      if (isNikLine(line.text)) {
        hasNik = true;
        break;
      }
    }
    if (hasNik) break;
  }

  if (!hasNik) {
    final reg16 = RegExp(r'\b\d{14,18}\b');
    if (reg16.hasMatch(fullText.replaceAll(' ', ''))) {
      hasNik = true;
    }
  }

  final bool isKtpDetected =
      hasNik || matchedKeywords >= 1 || (fullText.length >= 25 && matchedKeywords >= 1);
  if (!isKtpDetected) {
    return null;
  }

  // 1. Calculate orientation angle from detected text lines (in display space)
  final List<double> angles = [];
  for (final block in recognized.blocks) {
    final blockText = block.text.toUpperCase();
    bool isRelevantBlock = false;
    for (final kw in ktpKeywords) {
      if (blockText.contains(kw)) {
        isRelevantBlock = true;
        break;
      }
    }
    if (!isRelevantBlock) {
      for (final line in block.lines) {
        if (isNikLine(line.text) || line.text.filterNumbersOnly().length >= 6) {
          isRelevantBlock = true;
          break;
        }
      }
    }

    if (isRelevantBlock) {
      for (final line in block.lines) {
        if (line.cornerPoints.length >= 2) {
          final p0 = transformPoint(line.cornerPoints[0]);
          final p1 = transformPoint(line.cornerPoints[1]);
          final dx = p1.dx - p0.dx;
          final dy = p1.dy - p0.dy;
          if (dx.abs() >= 25) {
            final a = atan2(dy, dx) * 180.0 / pi;
            if (a.abs() <= 45.0) {
              angles.add(a);
            }
          }
        }
      }
    }
  }

  double cardAngle = 0.0;
  if (angles.isNotEmpty) {
    angles.sort();
    cardAngle = angles[angles.length ~/ 2];
  }

  final double rad = cardAngle * pi / 180.0;
  final double cosT = cos(rad);
  final double sinT = sin(rad);

  // 2. Project points into card coordinate space (u, v) in display space
  double minU = double.infinity;
  double maxU = double.negativeInfinity;
  double minV = double.infinity;
  double maxV = double.negativeInfinity;

  final List<Offset> relevantPoints = [];

  for (final block in recognized.blocks) {
    final blockText = block.text.toUpperCase();
    bool isRelevant = false;
    for (final kw in ktpKeywords) {
      if (blockText.contains(kw)) {
        isRelevant = true;
        break;
      }
    }
    if (!isRelevant) {
      for (final line in block.lines) {
        if (isNikLine(line.text) || line.text.filterNumbersOnly().length >= 6) {
          isRelevant = true;
          break;
        }
      }
    }

    if (isRelevant) {
      for (final line in block.lines) {
        if (line.cornerPoints.isNotEmpty) {
          for (final p in line.cornerPoints) {
            final pt = transformPoint(p);
            relevantPoints.add(pt);
            final double u = pt.dx * cosT + pt.dy * sinT;
            final double v = -pt.dx * sinT + pt.dy * cosT;
            if (u < minU) minU = u;
            if (u > maxU) maxU = u;
            if (v < minV) minV = v;
            if (v > maxV) maxV = v;
          }
        } else {
          final r = line.boundingBox;
          for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
            final pt = transformOffset(p);
            relevantPoints.add(pt);
            final double u = pt.dx * cosT + pt.dy * sinT;
            final double v = -pt.dx * sinT + pt.dy * cosT;
            if (u < minU) minU = u;
            if (u > maxU) maxU = u;
            if (v < minV) minV = v;
            if (v > maxV) maxV = v;
          }
        }
      }
    }
  }

  if (minU >= maxU || minV >= maxV || relevantPoints.length < 2) {
    return null;
  }

  // Include nearby signature / photo text
  for (final block in recognized.blocks) {
    final r = block.boundingBox;
    final centerPt =
        transformOffset(Offset(r.left + r.width / 2, r.top + r.height / 2));
    final double cu = centerPt.dx * cosT + centerPt.dy * sinT;
    final double cv = -centerPt.dx * sinT + centerPt.dy * cosT;
    if (cv >= minV - 40 &&
        cv <= maxV + 60 &&
        cu >= minU - 50 &&
        cu <= maxU + 280) {
      for (final line in block.lines) {
        for (final p in line.cornerPoints) {
          final pt = transformPoint(p);
          relevantPoints.add(pt);
          final double u = pt.dx * cosT + pt.dy * sinT;
          final double v = -pt.dx * sinT + pt.dy * cosT;
          if (u < minU) minU = u;
          if (u > maxU) maxU = u;
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
    }
  }

  final double textHeight = maxV - minV;
  final double textWidth = maxU - minU;

  // Determine which sections of the KTP were captured
  final bool hasHeader = fullText.contains('PROVINSI') ||
      fullText.contains('KABUPATEN') ||
      fullText.contains('KOTA');
  final bool hasFooter = fullText.contains('BERLAKU') ||
      fullText.contains('SEUMUR') ||
      fullText.contains('HIDUP') ||
      fullText.contains('PEKERJAAN') ||
      fullText.contains('GOL');

  // Standard ID-1 card dimensions (85.6mm x 53.98mm = 1.5858 ratio)
  double cardHeight;
  double cardWidth;
  double cardTopV;

  if (hasHeader && hasFooter) {
    // Both top and bottom text detected: text span covers ~88% of physical card height
    cardHeight = textHeight * 1.136;
    cardWidth = cardHeight * 1.5858;
    // "PROVINSI" is ~3.0mm from top plastic edge (3.0 / 53.98 = ~5.5%)
    cardTopV = minV - (cardHeight * 0.055);
  } else if (hasHeader) {
    // Header only: text width gives card width
    cardWidth = max(textWidth * 1.25, 180.0);
    cardHeight = cardWidth / 1.5858;
    cardTopV = minV - (cardHeight * 0.055);
  } else if (hasNik) {
    // NIK line is at ~28% from top edge of card
    cardWidth = max(textWidth * 1.45, 180.0);
    cardHeight = cardWidth / 1.5858;
    cardTopV = minV - (cardHeight * 0.28);
  } else if (hasFooter) {
    // Footer is at ~88% from top edge of card
    cardWidth = max(textWidth * 1.30, 180.0);
    cardHeight = cardWidth / 1.5858;
    cardTopV = maxV - (cardHeight * 0.88);
  } else {
    // General case
    cardHeight = max(textHeight * 1.14, textWidth / 1.5858);
    cardWidth = cardHeight * 1.5858;
    cardTopV = minV - (cardHeight * 0.06);
  }

  // Ensure card width covers full width of text + right photo margin
  if (textWidth > cardWidth * 0.88) {
    cardWidth = textWidth * 1.14;
    cardHeight = cardWidth / 1.5858;
  }

  final double cardBotV = cardTopV + cardHeight;

  // Text margin from left plastic edge is ~5.0% (4.3mm / 85.6mm)
  final double leftU = minU - (cardWidth * 0.050);
  final double rightU = leftU + cardWidth;

  // Convert (u, v) back to original camera (x, y) coordinates
  Offset toXY(double u, double v) {
    return Offset(
      u * cosT - v * sinT,
      u * sinT + v * cosT,
    );
  }

  final tl = toXY(leftU, cardTopV);
  final tr = toXY(rightU, cardTopV);
  final br = toXY(rightU, cardBotV);
  final bl = toXY(leftU, cardBotV);

  return CardCorners(
    topLeft: tl,
    topRight: tr,
    bottomRight: br,
    bottomLeft: bl,
  );
}

/// Helper function to perform robust linear regression y = m*x + c
/// with outlier rejection.
MapEntry<double, double>? _fitLine(List<Offset> points, {bool vertical = false}) {
  if (points.length < 3) return null;

  double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
  final int n = points.length;

  for (final p in points) {
    final double x = vertical ? p.dy : p.dx;
    final double y = vertical ? p.dx : p.dy;
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumX2 += x * x;
  }

  final double denom = n * sumX2 - sumX * sumX;
  if (denom.abs() < 1e-6) return null;

  double m = (n * sumXY - sumX * sumY) / denom;
  double c = (sumY - m * sumX) / n;

  // Filter outliers (> 2.5 residual standard deviation)
  final residuals = <double>[];
  for (final p in points) {
    final double x = vertical ? p.dy : p.dx;
    final double y = vertical ? p.dx : p.dy;
    final double pred = m * x + c;
    residuals.add((y - pred).abs());
  }
  residuals.sort();
  final double medianRes = residuals[residuals.length ~/ 2];
  final double threshold = max(2.5, medianRes * 2.5);

  final filtered = <Offset>[];
  for (int i = 0; i < points.length; i++) {
    if (residuals[i] <= threshold) {
      filtered.add(points[i]);
    }
  }

  if (filtered.length < 3) {
    return MapEntry(m, c);
  }

  // Refit with inliers
  sumX = 0;
  sumY = 0;
  sumXY = 0;
  sumX2 = 0;
  final int fn = filtered.length;
  for (final p in filtered) {
    final double x = vertical ? p.dy : p.dx;
    final double y = vertical ? p.dx : p.dy;
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumX2 += x * x;
  }

  final double fdenom = fn * sumX2 - sumX * sumX;
  if (fdenom.abs() < 1e-6) return MapEntry(m, c);

  m = (fn * sumXY - sumX * sumY) / fdenom;
  c = (sumY - m * sumX) / fn;

  return MapEntry(m, c);
}

bool _isCardPixel(img.Pixel pixel) {
  final int r = pixel.r.toInt();
  final int g = pixel.g.toInt();
  final int b = pixel.b.toInt();

  final int diff = b - r;
  // Indonesian KTP card has cyan-blue security background
  final bool isBlue = diff >= 8;
  // Photo areas have red (odd birth years) or blue (even birth years) backgrounds
  final bool isRedPhoto = (r >= 120) && (r - g >= 25) && (r - b >= 25);
  final bool isBluePhoto = (b >= 120) && (b - r >= 25) && (b - g >= 15);

  return isBlue || isRedPhoto || isBluePhoto;
}

CardCorners _detectCardCorners(
  img.Image image,
  Rect rect,
  double angleDegrees,
) {
  final int imgW = image.width;
  final int imgH = image.height;

  final double cx = rect.center.dx;
  final double cy = rect.center.dy;
  final double cardW = rect.width.clamp(100.0, (imgW - 1).toDouble());
  final double cardH = rect.height.clamp(60.0, (imgH - 1).toDouble());

  final double rad = angleDegrees * pi / 180.0;
  final double cosT = cos(rad);
  final double sinT = sin(rad);

  // Unit vector u along card width (left to right)
  final double ux = cosT;
  final double uy = sinT;

  // Unit vector v along card height (top to bottom)
  final double vx = -sinT;
  final double vy = cosT;

  // 1. Top Edge: scan along rays pointing from outside (+v inward towards center)
  final topPts = <Offset>[];
  const int numTopSamples = 25;
  final double tStepTop = (cardW * 0.76) / (numTopSamples - 1);
  final int maxStepV = (cardH * 0.32).toInt();

  for (int i = 0; i < numTopSamples; i++) {
    final double t = -0.38 * cardW + i * tStepTop;
    final double px = cx + t * ux - (cardH / 2.0) * vx;
    final double py = cy + t * uy - (cardH / 2.0) * vy;

    final double sx = px - (0.16 * cardH) * vx;
    final double sy = py - (0.16 * cardH) * vy;

    for (int step = 0; step < maxStepV; step++) {
      final int rx = (sx + step * vx).round();
      final int ry = (sy + step * vy).round();
      if (rx >= 0 && rx < imgW && ry >= 0 && ry < imgH - 2) {
        if (_isCardPixel(image.getPixel(rx, ry)) &&
            _isCardPixel(image.getPixel(rx, ry + 1)) &&
            _isCardPixel(image.getPixel(rx, ry + 2))) {
          topPts.add(Offset(rx.toDouble(), ry.toDouble()));
          break;
        }
      }
    }
  }

  // 2. Bottom Edge: scan along rays pointing from outside (-v inward towards center)
  final botPts = <Offset>[];
  for (int i = 0; i < numTopSamples; i++) {
    final double t = -0.38 * cardW + i * tStepTop;
    final double px = cx + t * ux + (cardH / 2.0) * vx;
    final double py = cy + t * uy + (cardH / 2.0) * vy;

    final double sx = px + (0.16 * cardH) * vx;
    final double sy = py + (0.16 * cardH) * vy;

    for (int step = 0; step < maxStepV; step++) {
      final int rx = (sx - step * vx).round();
      final int ry = (sy - step * vy).round();
      if (rx >= 0 && rx < imgW && ry >= 2 && ry < imgH) {
        if (_isCardPixel(image.getPixel(rx, ry)) &&
            _isCardPixel(image.getPixel(rx, ry - 1)) &&
            _isCardPixel(image.getPixel(rx, ry - 2))) {
          botPts.add(Offset(rx.toDouble(), ry.toDouble()));
          break;
        }
      }
    }
  }

  // 3. Left Edge: scan along rays pointing from outside (+u inward towards center)
  final leftPts = <Offset>[];
  const int numSideSamples = 25;
  final double sStepSide = (cardH * 0.76) / (numSideSamples - 1);
  final int maxStepU = (cardW * 0.32).toInt();

  for (int i = 0; i < numSideSamples; i++) {
    final double s = -0.38 * cardH + i * sStepSide;
    final double px = cx - (cardW / 2.0) * ux + s * vx;
    final double py = cy - (cardW / 2.0) * uy + s * vy;

    final double sx = px - (0.16 * cardW) * ux;
    final double sy = py - (0.16 * cardW) * uy;

    for (int step = 0; step < maxStepU; step++) {
      final int rx = (sx + step * ux).round();
      final int ry = (sy + step * uy).round();
      if (rx >= 0 && rx < imgW - 2 && ry >= 0 && ry < imgH) {
        if (_isCardPixel(image.getPixel(rx, ry)) &&
            _isCardPixel(image.getPixel(rx + 1, ry)) &&
            _isCardPixel(image.getPixel(rx + 2, ry))) {
          leftPts.add(Offset(rx.toDouble(), ry.toDouble()));
          break;
        }
      }
    }
  }

  // 4. Right Edge: scan along rays pointing from outside (-u inward towards center)
  final rightPts = <Offset>[];
  for (int i = 0; i < numSideSamples; i++) {
    final double s = -0.38 * cardH + i * sStepSide;
    final double px = cx + (cardW / 2.0) * ux + s * vx;
    final double py = cy + (cardW / 2.0) * uy + s * vy;

    final double sx = px + (0.16 * cardW) * ux;
    final double sy = py + (0.16 * cardW) * uy;

    for (int step = 0; step < maxStepU; step++) {
      final int rx = (sx - step * ux).round();
      final int ry = (sy - step * uy).round();
      if (rx >= 2 && rx < imgW && ry >= 0 && ry < imgH) {
        if (_isCardPixel(image.getPixel(rx, ry)) &&
            _isCardPixel(image.getPixel(rx - 1, ry)) &&
            _isCardPixel(image.getPixel(rx - 2, ry))) {
          rightPts.add(Offset(rx.toDouble(), ry.toDouble()));
          break;
        }
      }
    }
  }

  // Line fitting and intersection calculation
  if (topPts.length >= 5 &&
      botPts.length >= 5 &&
      leftPts.length >= 5 &&
      rightPts.length >= 5) {
    final topFit = _fitLine(topPts, vertical: false);
    final botFit = _fitLine(botPts, vertical: false);
    final leftFit = _fitLine(leftPts, vertical: true); // x = m*y + c
    final rightFit = _fitLine(rightPts, vertical: true); // x = m*y + c

    if (topFit != null && botFit != null && leftFit != null && rightFit != null) {
      final double mTop = topFit.key;
      final double cTop = topFit.value;
      final double mBot = botFit.key;
      final double cBot = botFit.value;
      final double mLeft = leftFit.key;
      final double cLeft = leftFit.value;
      final double mRight = rightFit.key;
      final double cRight = rightFit.value;

      final double denomTL = 1.0 - mTop * mLeft;
      final double denomTR = 1.0 - mTop * mRight;
      final double denomBL = 1.0 - mBot * mLeft;
      final double denomBR = 1.0 - mBot * mRight;

      if (denomTL.abs() > 0.01 &&
          denomTR.abs() > 0.01 &&
          denomBL.abs() > 0.01 &&
          denomBR.abs() > 0.01) {
        final double tlY = (mTop * cLeft + cTop) / denomTL;
        final double tlX = mLeft * tlY + cLeft;

        final double trY = (mTop * cRight + cTop) / denomTR;
        final double trX = mRight * trY + cRight;

        final double blY = (mBot * cLeft + cBot) / denomBL;
        final double blX = mLeft * blY + cLeft;

        final double brY = (mBot * cRight + cBot) / denomBR;
        final double brX = mRight * brY + cRight;

        // Verify quadrilateral aspect ratio & dimensions
        final double topW = sqrt(pow(trX - tlX, 2) + pow(trY - tlY, 2));
        final double botW = sqrt(pow(brX - blX, 2) + pow(brY - blY, 2));
        final double leftH = sqrt(pow(blX - tlX, 2) + pow(blY - tlY, 2));
        final double rightH = sqrt(pow(brX - trX, 2) + pow(brY - trY, 2));

        final double avgW = (topW + botW) / 2.0;
        final double avgH = (leftH + rightH) / 2.0;
        final double ratio = avgW / avgH;

        // Indonesian KTP ratio is 1.5858 (acceptable range: 1.35 to 1.85)
        if (ratio >= 1.35 && ratio <= 1.85 && avgW >= 150) {
          // Snug exact fit on the physical card boundary so no desk or notebook margins appear
          return CardCorners(
            topLeft: Offset(tlX, tlY),
            topRight: Offset(trX, trY),
            bottomLeft: Offset(blX, blY),
            bottomRight: Offset(brX, brY),
          );
        }
      }
    }
  }

  // Fallback: Geometric rotated corners from OCR bounding box
  final double hw = rect.width / 2.0;
  final double hh = rect.height / 2.0;

  Offset rot(double dx, double dy) {
    return Offset(
      cx + (dx * cosT - dy * sinT),
      cy + (dx * sinT + dy * cosT),
    );
  }

  return CardCorners(
    topLeft: rot(-hw, -hh),
    topRight: rot(hw, -hh),
    bottomLeft: rot(-hw, hh),
    bottomRight: rot(hw, hh),
  );
}

/// Crops and automatically deskews/rectifies 3D perspective (XYZ) of a KTP card.
/// Corrects roll (Z tilt), pitch (X tilt), and yaw (Y tilt), removing background
/// borders and producing a crisp, straight ID-1 card image.
Future<File?> cropAndDeskewImage(
  File imageFile,
  Rect rect, {
  double angleDegrees = 0.0,
}) async {
  var parse = await img.decodeImageFile(imageFile.absolute.path);
  if (parse == null) return null;
  parse = img.bakeOrientation(parse);

  final CardCorners corners = _detectCardCorners(parse, rect, angleDegrees);

  final double topW = sqrt(pow(corners.topRight.dx - corners.topLeft.dx, 2) +
      pow(corners.topRight.dy - corners.topLeft.dy, 2));
  final double botW = sqrt(pow(corners.bottomRight.dx - corners.bottomLeft.dx, 2) +
      pow(corners.bottomRight.dy - corners.bottomLeft.dy, 2));
  final double maxW = max(topW, botW);

  // Preserve high-definition sharpness: target width between 720 and 1200 px
  final double targetW = maxW.clamp(720.0, 1200.0);
  final double targetH = targetW / 1.5858;

  final rectified = img.copyRectify(
    parse,
    topLeft: img.Point(corners.topLeft.dx.round(), corners.topLeft.dy.round()),
    topRight: img.Point(corners.topRight.dx.round(), corners.topRight.dy.round()),
    bottomLeft: img.Point(corners.bottomLeft.dx.round(), corners.bottomLeft.dy.round()),
    bottomRight: img.Point(corners.bottomRight.dx.round(), corners.bottomRight.dy.round()),
    toImage: img.Image(width: targetW.round(), height: targetH.round()),
    interpolation: img.Interpolation.linear,
  );

  final List<int> cropByte = img.encodeJpg(rectified, quality: 95);
  final String tempPath =
      '${imageFile.parent.path}/ktp_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final File imageFileCrop = await File(tempPath).writeAsBytes(cropByte);
  return imageFileCrop;
}

Future<File?> cropImageRect(File imageFile, Rect rect) =>
    cropAndDeskewImage(imageFile, rect);

Future<File?> cropImage(File imageFile, DetectedObject object) async {
  var parse = await img.decodeImageFile(imageFile.absolute.path);
  if (parse == null) return null;
  parse = img.bakeOrientation(parse);

  final rawWidth = (object.boundingBox.right - object.boundingBox.left).toInt();
  final rawHeight = (object.boundingBox.bottom - object.boundingBox.top).toInt();

  // Snug fit: TFLite bounding box already encompasses the card boundaries
  final cropX = object.boundingBox.left.clamp(0, parse.width - 1).toInt();
  final cropY = object.boundingBox.top.clamp(0, parse.height - 1).toInt();
  final cropWidth = rawWidth.clamp(1, parse.width - cropX).toInt();
  final cropHeight = rawHeight.clamp(1, parse.height - cropY).toInt();

  final result = img.copyCrop(
    parse,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  final List<int> cropByte = img.encodeJpg(result, quality: 95);
  final String tempPath =
      '${imageFile.parent.path}/ktp_crop_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final File imageFileCrop = await File(tempPath).writeAsBytes(cropByte);
  return imageFileCrop;
}

Future<File?> cropPassportMrz(File imageFile, DetectedObject object) async {
  var parse = await img.decodeImageFile(imageFile.absolute.path);
  if (parse == null) return null;
  parse = img.bakeOrientation(parse);

  final passportCrop = img.copyCrop(
    parse,
    x: object.boundingBox.left.toInt(),
    y: object.boundingBox.top.toInt(),
    width: (object.boundingBox.right - object.boundingBox.left).toInt(),
    height: (object.boundingBox.bottom - object.boundingBox.top).toInt(),
  );

  final mrzHeight = (passportCrop.height * 0.25).toInt();
  final mrzY = passportCrop.height - mrzHeight;

  final mrzCrop = img.copyCrop(
    parse,
    x: 0,
    y: mrzY,
    width: passportCrop.width,
    height: mrzHeight,
  );

  final List<int> cropByte = img.encodeJpg(mrzCrop, quality: 95);
  final String tempPath =
      '${imageFile.parent.path}/mrz_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final File mrzFile = await File(tempPath).writeAsBytes(cropByte);
  return mrzFile;
}

/// Crops the face/profile photo area from a cropped KTP image.
///
/// In standard Indonesian e-KTP (ISO 7810 ID-1 standard):
/// - Photo box is on the right side (~64% to 96% from left edge).
/// - Photo box starts around 14% to 22% from top edge and spans ~60% to 68% height.
///
/// Returns the cropped [File] of the photo suitable for user profile images.
/// Crops the face/profile photo area from a KTP image using smart color boundary detection
/// (red/blue pasfoto background detection) with mathematical ID-1 fallback.
Future<File?> cropKtpPhoto(File ktpImageFile) async {
  try {
    var parse = await img.decodeImageFile(ktpImageFile.absolute.path);
    if (parse == null) return null;
    parse = img.bakeOrientation(parse);

    final int width = parse.width;
    final int height = parse.height;

    // Search window for photo on right side of KTP:
    // X: 64% to 95%, Y: 22% to 80%
    final int searchMinX = (width * 0.64).toInt();
    final int searchMaxX = (width * 0.96).toInt();
    final int searchMinY = (height * 0.22).toInt();
    final int searchMaxY = (height * 0.82).toInt();

    int foundMinX = width;
    int foundMaxX = 0;
    int foundMinY = height;
    int foundMaxY = 0;
    int coloredPixels = 0;

    // Check pixels for pasfoto solid red or blue background
    for (int y = searchMinY; y < searchMaxY; y += 3) {
      for (int x = searchMinX; x < searchMaxX; x += 3) {
        final pixel = parse.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // 1. Red background (Indonesian KTP for odd birth years, e.g. RGB around (160-220, 30-70, 30-70))
        final bool isRedBg = (r > 130 && r > g * 1.6 && r > b * 1.6);
        // 2. Blue background (Indonesian KTP for even birth years, deeper blue than card surface)
        final bool isDeepBlueBg = (b > 130 && b > r * 1.5 && b > g * 1.3);

        if (isRedBg || isDeepBlueBg) {
          coloredPixels++;
          if (x < foundMinX) foundMinX = x;
          if (x > foundMaxX) foundMaxX = x;
          if (y < foundMinY) foundMinY = y;
          if (y > foundMaxY) foundMaxY = y;
        }
      }
    }

    int photoLeft;
    int photoTop;
    int photoWidth;
    int photoHeight;

    // If a clear pasfoto color cluster is detected:
    final int detectedW = foundMaxX - foundMinX;
    final int detectedH = foundMaxY - foundMinY;
    if (coloredPixels > 40 &&
        detectedW >= (width * 0.14) &&
        detectedH >= (height * 0.25)) {
      photoLeft = foundMinX;
      photoTop = foundMinY;
      photoWidth = detectedW;
      photoHeight = detectedH;
    } else {
      // Robust standard mathematical fallback (3:4 ratio)
      photoLeft = (width * 0.700).toInt();
      photoTop = (height * 0.300).toInt();
      photoWidth = (width * 0.210).toInt();
      photoHeight = (height * 0.420).toInt();
    }

    // Clamp coordinates safely within image bounds
    if (photoLeft < 0) photoLeft = 0;
    if (photoTop < 0) photoTop = 0;
    if (photoLeft + photoWidth > width) {
      photoWidth = width - photoLeft;
    }
    if (photoTop + photoHeight > height) {
      photoHeight = height - photoTop;
    }

    if (photoWidth <= 10 || photoHeight <= 10) return null;

    final croppedPhoto = img.copyCrop(
      parse,
      x: photoLeft,
      y: photoTop,
      width: photoWidth,
      height: photoHeight,
    );

    final List<int> photoBytes = img.encodeJpg(croppedPhoto, quality: 95);
    final String photoPath =
        '${ktpImageFile.parent.path}/ktp_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File photoFile = await File(photoPath).writeAsBytes(photoBytes);
    return photoFile;
  } catch (e) {
    return null;
  }
}

String calculateCheckDigit(String input) {
  const weights = [7, 3, 1];
  int sum = 0;
  
  String cleanInput = input
      .replaceAll('«', '<')
      .replaceAll('»', '<')
      .replaceAll('‹', '<')
      .replaceAll('›', '<')
      .replaceAll('〈', '<')
      .replaceAll('〉', '<')
      .replaceAll('＜', '<')
      .replaceAll('＞', '<');

  for (int i = 0; i < cleanInput.length; i++) {
    final char = cleanInput[i];
    int value;

    if (char == '<') {
      value = 0;
    } else if (RegExp(r'\d').hasMatch(char)) {
      value = int.parse(char);
    } else {
      value = char.codeUnitAt(0) - 'A'.codeUnitAt(0) + 10;
    }

    sum += value * weights[i % 3];
  }

  return (sum % 10).toString();
}

bool validateMrzChecksum(String data, String checkDigit) {
  return calculateCheckDigit(data) == checkDigit;
}
