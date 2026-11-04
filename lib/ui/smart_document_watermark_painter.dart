// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../models/smart_document_type.dart';

/// Custom painter for document viewfinders (KTP, KK, Surat Sehat).
/// Renders:
/// - Rounded card boundary
/// - Orange corner brackets (#FD990F)
/// - Document-specific watermarks (KTP photo frame, KK document table, Surat Sehat medical certificate)
/// - Scanning laser animation line
class SmartDocumentWatermarkPainter extends CustomPainter {
  final SmartDocumentType documentType;
  final double laserProgress;
  final bool showWatermark;
  final bool showLaser;
  final double cornerRadius;

  SmartDocumentWatermarkPainter({
    required this.documentType,
    required this.laserProgress,
    this.showWatermark = true,
    this.showLaser = true,
    this.cornerRadius = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect cardRect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(cardRect, Radius.circular(cornerRadius));

    // Outer subtle border
    final Paint borderPaint = Paint()
      ..color = const Color(0xFF002245).withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, borderPaint);

    // Document-specific background watermark
    if (showWatermark) {
      switch (documentType) {
        case SmartDocumentType.ktp:
          _drawKtpWatermark(canvas, size, rrect);
          break;
        case SmartDocumentType.kartuKeluarga:
          _drawKkWatermark(canvas, size, rrect);
          break;
        case SmartDocumentType.suratSehat:
          _drawSuratSehatWatermark(canvas, size, rrect);
          break;
      }
    }

    // Scanning laser
    if (showLaser) {
      _drawLaserLine(canvas, size);
    }

    // High visibility glowing orange corner brackets
    _drawOrangeCornerBrackets(canvas, size);
  }

  void _drawKtpWatermark(Canvas canvas, Size size, RRect rrect) {
    // 1. Semi-translucent card body tint
    final Paint cardBgPaint = Paint()
      ..color = const Color(0xFF90B5D8).withOpacity(0.40)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, cardBgPaint);

    // 2. KTP Header
    final TextPainter headerPainter = TextPainter(
      text: const TextSpan(
        text: 'REPUBLIK INDONESIA\n',
        style: TextStyle(
          color: Color(0xFF1E3A5F),
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          height: 1.2,
        ),
        children: [
          TextSpan(
            text: 'PROVINSI DKI JAKARTA',
            style: TextStyle(
              color: Color(0xFF2C4A6F),
              fontSize: 7.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    headerPainter.paint(
      canvas,
      Offset((size.width - headerPainter.width) / 2, size.height * 0.08),
    );

    // 3. Text lines
    final Paint linePaint = Paint()
      ..color = const Color(0xFF6B8BAA).withOpacity(0.60)
      ..style = PaintingStyle.fill;

    final double leftMargin = size.width * 0.07;
    final double textStartY = size.height * 0.36;
    final double lineHeight = size.height * 0.035;
    final double lineSpacing = size.height * 0.07;
    final List<double> lineWidths = [
      size.width * 0.32,
      size.width * 0.42,
      size.width * 0.36,
      size.width * 0.26,
    ];

    for (int i = 0; i < lineWidths.length; i++) {
      final lineRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          leftMargin,
          textStartY + (i * lineSpacing),
          lineWidths[i],
          lineHeight,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(lineRect, linePaint);
    }

    // 4. Center chip / watermark icon
    final Paint chipPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.50, size.height * 0.48),
          width: 22,
          height: 22,
        ),
        const Radius.circular(4),
      ),
      chipPaint,
    );

    // 5. Right Photo Box
    final double photoWidth = size.width * 0.20;
    final double photoHeight = size.height * 0.42;
    final double photoLeft = size.width - photoWidth - (size.width * 0.08);
    final double photoTop = size.height * 0.32;

    final RRect photoRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(photoLeft, photoTop, photoWidth, photoHeight),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      photoRRect,
      Paint()
        ..color = const Color(0xFF6B8BAA).withOpacity(0.35)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      photoRRect,
      Paint()
        ..color = const Color(0xFF6B8BAA).withOpacity(0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // User photo icon & "FOTO KTP" text
    final TextPainter photoText = TextPainter(
      text: const TextSpan(
        text: 'FOTO KTP',
        style: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 7.0,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    photoText.paint(
      canvas,
      Offset(
        photoLeft + (photoWidth - photoText.width) / 2,
        photoTop + (photoHeight * 0.68),
      ),
    );

    // Photo avatar outline
    final Paint avatarPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(
      Offset(photoLeft + photoWidth / 2, photoTop + photoHeight * 0.35),
      7.0,
      avatarPaint,
    );

    // 6. Bottom text ("BERLAKU SEUMUR HIDUP" & "JAKARTA")
    final TextPainter bottomL = TextPainter(
      text: const TextSpan(
        text: 'BERLAKU SEUMUR HIDUP',
        style: TextStyle(
          color: Color(0xFF2C4A6F),
          fontSize: 6.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    bottomL.paint(canvas, Offset(leftMargin, size.height * 0.86));

    final TextPainter bottomR = TextPainter(
      text: const TextSpan(
        text: 'JAKARTA, 12-04-2018',
        style: TextStyle(
          color: Color(0xFF2C4A6F),
          fontSize: 6.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    bottomR.paint(
      canvas,
      Offset(size.width - bottomR.width - (size.width * 0.08), size.height * 0.86),
    );
  }

  void _drawKkWatermark(Canvas canvas, Size size, RRect rrect) {
    // 1. Semi-translucent wide document tint
    final Paint bgPaint = Paint()
      ..color = const Color(0xFF8BA7C4).withOpacity(0.35)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // 2. KK Header: "REPUBLIK INDONESIA" & "KARTU KELUARGA" & "No. 3171************"
    final TextPainter headerPainter = TextPainter(
      text: const TextSpan(
        text: 'REPUBLIK INDONESIA\n',
        style: TextStyle(
          color: Color(0xFF1E3A5F),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          height: 1.25,
        ),
        children: [
          TextSpan(
            text: 'KARTU KELUARGA\n',
            style: TextStyle(
              color: Color(0xFF0B3866),
              fontSize: 12.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          TextSpan(
            text: 'No. 3171************',
            style: TextStyle(
              color: Color(0xFF2C4A6F),
              fontSize: 7.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    headerPainter.paint(
      canvas,
      Offset((size.width - headerPainter.width) / 2, size.height * 0.08),
    );

    // 3. Center Document watermark icon
    final double iconCenterX = size.width * 0.5;
    final double iconCenterY = size.height * 0.48;
    final Paint docIconPaint = Paint()
      ..color = Colors.white.withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(iconCenterX, iconCenterY),
          width: size.width * 0.16,
          height: size.height * 0.28,
        ),
        const Radius.circular(6),
      ),
      docIconPaint,
    );

    // 4. KK Table Watermark Rows
    final double tableTop = size.height * 0.38;
    final double tableWidth = size.width * 0.84;
    final double tableLeft = (size.width - tableWidth) / 2;

    // Table Header Bar (Yellow/Amber tint)
    final RRect tableHeaderRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tableLeft, tableTop, tableWidth, size.height * 0.04),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      tableHeaderRRect,
      Paint()
        ..color = const Color(0xFFFD990F).withOpacity(0.50)
        ..style = PaintingStyle.fill,
    );

    // Table Data Rows
    final Paint rowPaint = Paint()
      ..color = const Color(0xFF6B8BAA).withOpacity(0.40)
      ..style = PaintingStyle.fill;

    for (int r = 1; r <= 3; r++) {
      final double rowY = tableTop + (r * (size.height * 0.07));
      // Draw 3 row segments per line
      final double segWidth = (tableWidth - 12) / 3;
      for (int c = 0; c < 3; c++) {
        final lineRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            tableLeft + (c * (segWidth + 6)),
            rowY,
            segWidth,
            size.height * 0.035,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(lineRect, rowPaint);
      }
    }

    // 5. KK Footer: "KEPALA KELUARGA" & "DITETAPKAN DI JAKARTA"
    final TextPainter footerL = TextPainter(
      text: const TextSpan(
        text: 'KEPALA KELUARGA',
        style: TextStyle(
          color: Color(0xFF2C4A6F),
          fontSize: 6.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    footerL.paint(canvas, Offset(tableLeft, size.height * 0.86));

    final TextPainter footerR = TextPainter(
      text: const TextSpan(
        text: 'DITETAPKAN DI JAKARTA',
        style: TextStyle(
          color: Color(0xFF2C4A6F),
          fontSize: 6.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    footerR.paint(
      canvas,
      Offset(tableLeft + tableWidth - footerR.width, size.height * 0.86),
    );
  }

  void _drawSuratSehatWatermark(Canvas canvas, Size size, RRect rrect) {
    // 1. Semi-translucent portrait card body tint
    final Paint bgPaint = Paint()
      ..color = const Color(0xFF2A3644).withOpacity(0.70)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // 2. Medical Cross Badge at top
    final double crossCenterX = size.width * 0.5;
    final double crossCenterY = size.height * 0.10;
    final Paint badgeBgPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(crossCenterX, crossCenterY), 14, badgeBgPaint);

    final Paint crossPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(crossCenterX - 6, crossCenterY),
      Offset(crossCenterX + 6, crossCenterY),
      crossPaint,
    );
    canvas.drawLine(
      Offset(crossCenterX, crossCenterY - 6),
      Offset(crossCenterX, crossCenterY + 6),
      crossPaint,
    );

    // 3. Header: "SURAT KETERANGAN DOKTER\nRUMAH SAKIT / KLINIK RESMI PEMERINTAH"
    final TextPainter headerPainter = TextPainter(
      text: const TextSpan(
        text: 'SURAT KETERANGAN DOKTER\n',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          height: 1.3,
        ),
        children: [
          TextSpan(
            text: 'RUMAH SAKIT / KLINIK RESMI PEMERINTAH',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 7.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);

    headerPainter.paint(
      canvas,
      Offset((size.width - headerPainter.width) / 2, size.height * 0.16),
    );

    // 4. Physical Examination Box: "HASIL PEMERIKSAAN FISIK & KESEHATAN"
    final double examBoxTop = size.height * 0.30;
    final double examBoxWidth = size.width * 0.82;
    final double examBoxLeft = (size.width - examBoxWidth) / 2;

    final RRect examBoxRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(examBoxLeft, examBoxTop, examBoxWidth, size.height * 0.06),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      examBoxRRect,
      Paint()
        ..color = Colors.white.withOpacity(0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      examBoxRRect,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final TextPainter examText = TextPainter(
      text: const TextSpan(
        text: 'HASIL PEMERIKSAAN FISIK & KESEHATAN',
        style: TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 8.0,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    examText.paint(
      canvas,
      Offset(
        examBoxLeft + (examBoxWidth - examText.width) / 2,
        examBoxTop + (size.height * 0.06 - examText.height) / 2,
      ),
    );

    // 5. Medical Form Content Lines
    final Paint linePaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final double lineStartY = size.height * 0.40;
    final double lineSpacing = size.height * 0.045;
    final List<double> lineWidths = [
      examBoxWidth * 0.95,
      examBoxWidth * 0.85,
      examBoxWidth * 0.70,
      examBoxWidth * 0.90,
    ];

    for (int i = 0; i < lineWidths.length; i++) {
      final lineRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          examBoxLeft,
          lineStartY + (i * lineSpacing),
          lineWidths[i],
          size.height * 0.015,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(lineRect, linePaint);
    }

    // 6. Bottom Stamp / Cap & Doctor Signature Placeholders (from Figma)
    final double badgeY = size.height * 0.72;

    // Cap / Stempel Badge on Left
    final double stampCenterX = size.width * 0.28;
    final Paint stampBg = Paint()
      ..color = const Color(0xFFFD990F).withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final Paint stampBorder = Paint()
      ..color = const Color(0xFFFD990F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(Offset(stampCenterX, badgeY), 18, stampBg);
    canvas.drawCircle(Offset(stampCenterX, badgeY), 18, stampBorder);

    final TextPainter stampText = TextPainter(
      text: const TextSpan(
        text: 'Cap / Stempel',
        style: TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 7.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stampText.paint(
      canvas,
      Offset(stampCenterX - stampText.width / 2, badgeY + 24),
    );

    // Tanda Tangan Dokter on Right
    final double signCenterX = size.width * 0.72;
    final Paint signPaint = Paint()
      ..color = Colors.white.withOpacity(0.50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    // Signature scribble
    final Path signPath = Path()
      ..moveTo(signCenterX - 14, badgeY + 4)
      ..quadraticBezierTo(signCenterX - 6, badgeY - 10, signCenterX, badgeY)
      ..quadraticBezierTo(signCenterX + 6, badgeY + 8, signCenterX + 14, badgeY - 6);
    canvas.drawPath(signPath, signPaint);

    final TextPainter signText = TextPainter(
      text: const TextSpan(
        text: 'Tanda Tangan Dokter',
        style: TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 7.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    signText.paint(
      canvas,
      Offset(signCenterX - signText.width / 2, badgeY + 24),
    );
  }

  void _drawLaserLine(Canvas canvas, Size size) {
    final double laserY = size.height * (0.12 + (laserProgress * 0.76));
    final Paint laserLinePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0x99FD990F),
          Color(0xCCFBBF24),
          Color(0x99FD990F),
          Colors.transparent,
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, laserY, size.width, 2.0))
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final Paint laserGlowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFFD990F).withOpacity(0.12),
          const Color(0xFFFD990F).withOpacity(0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, laserY - 4, size.width, 8))
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(12, laserY), Offset(size.width - 12, laserY), laserGlowPaint);
    canvas.drawLine(Offset(12, laserY), Offset(size.width - 12, laserY), laserLinePaint);
  }

  void _drawOrangeCornerBrackets(Canvas canvas, Size size) {
    final double padding = 12.0 * (cornerRadius / 20.0);
    final double bracketLength = 24.0 * (cornerRadius / 20.0);
    final double strokeW = 4.0 * (cornerRadius / 20.0);
    final double r = 14.0 * (cornerRadius / 20.0);
    final double offset = padding + (strokeW / 2);
    final double arcR = r - (strokeW / 2);
    const Color orangeColor = Color(0xFFFD990F);

    final Paint glowPaint = Paint()
      ..color = orangeColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW + 4.0
      ..strokeCap = StrokeCap.round;

    final Paint cornerPaint = Paint()
      ..color = orangeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    void drawCorner(Path path) {
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, cornerPaint);
    }

    // Top-Left corner:
    final Path tl = Path()
      ..moveTo(offset, offset + r + bracketLength)
      ..lineTo(offset, offset + r)
      ..arcToPoint(
        Offset(offset + r, offset),
        radius: Radius.circular(arcR),
        clockwise: true,
      )
      ..lineTo(offset + r + bracketLength, offset);
    drawCorner(tl);

    // Top-Right corner:
    final Path tr = Path()
      ..moveTo(size.width - offset - r - bracketLength, offset)
      ..lineTo(size.width - offset - r, offset)
      ..arcToPoint(
        Offset(size.width - offset, offset + r),
        radius: Radius.circular(arcR),
        clockwise: true,
      )
      ..lineTo(size.width - offset, offset + r + bracketLength);
    drawCorner(tr);

    // Bottom-Left corner:
    final Path bl = Path()
      ..moveTo(offset, size.height - offset - r - bracketLength)
      ..lineTo(offset, size.height - offset - r)
      ..arcToPoint(
        Offset(offset + r, size.height - offset),
        radius: Radius.circular(arcR),
        clockwise: false,
      )
      ..lineTo(offset + r + bracketLength, size.height - offset);
    drawCorner(bl);

    // Bottom-Right corner:
    final Path br = Path()
      ..moveTo(size.width - offset - r - bracketLength, size.height - offset)
      ..lineTo(size.width - offset - r, size.height - offset)
      ..arcToPoint(
        Offset(size.width - offset, size.height - offset - r),
        radius: Radius.circular(arcR),
        clockwise: false,
      )
      ..lineTo(size.width - offset, size.height - offset - r - bracketLength);
    drawCorner(br);
  }

  @override
  bool shouldRepaint(covariant SmartDocumentWatermarkPainter oldDelegate) {
    return oldDelegate.documentType != documentType ||
        oldDelegate.laserProgress != laserProgress ||
        oldDelegate.showWatermark != showWatermark ||
        oldDelegate.showLaser != showLaser;
  }
}
