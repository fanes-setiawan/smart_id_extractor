import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_id_extractor/smart_id_extractor.dart';
import 'package:smart_id_extractor/utils/utils.dart';

void main() {
  group('CardCorners Flexible Frame Tests', () {
    test('Calculates center, dimensions, and bounding box correctly', () {
      const corners = CardCorners(
        topLeft: Offset(10, 10),
        topRight: Offset(110, 10),
        bottomRight: Offset(110, 60),
        bottomLeft: Offset(10, 60),
      );

      expect(corners.center, equals(const Offset(60, 35)));
      expect(corners.width, equals(100.0));
      expect(corners.height, equals(50.0));
      expect(corners.angleDegrees, equals(0.0));
      expect(corners.boundingBox, equals(const Rect.fromLTRB(10, 10, 110, 60)));
    });

    test('Creates closed quadrilateral Path correctly', () {
      const corners = CardCorners(
        topLeft: Offset(20, 20),
        topRight: Offset(120, 25),
        bottomRight: Offset(115, 85),
        bottomLeft: Offset(15, 80),
      );

      final path = corners.toPath();
      expect(path, isA<Path>());
      expect(path.getBounds(), equals(corners.boundingBox));
    });

    test('Performs smooth linear interpolation (lerp) without jitter', () {
      const a = CardCorners(
        topLeft: Offset(0, 0),
        topRight: Offset(100, 0),
        bottomRight: Offset(100, 50),
        bottomLeft: Offset(0, 50),
      );

      const b = CardCorners(
        topLeft: Offset(10, 20),
        topRight: Offset(110, 20),
        bottomRight: Offset(110, 70),
        bottomLeft: Offset(10, 70),
      );

      final mid = CardCorners.lerp(a, b, 0.5);
      expect(mid.topLeft, equals(const Offset(5, 10)));
      expect(mid.topRight, equals(const Offset(105, 10)));
      expect(mid.bottomRight, equals(const Offset(105, 60)));
      expect(mid.bottomLeft, equals(const Offset(5, 60)));
    });

    test('Creates corners from Rect with rotation angle (Posisi 2 & 4)', () {
      const rect = Rect.fromLTWH(100, 100, 200, 100);
      final corners0 = CardCorners.fromRect(rect, 0.0);
      expect(corners0.topLeft, equals(rect.topLeft));
      expect(corners0.topRight, equals(rect.topRight));

      // 90 degree clockwise rotation around center (200, 150)
      final corners90 = CardCorners.fromRect(rect, 90.0);
      expect(corners90.center.dx, closeTo(200.0, 0.01));
      expect(corners90.center.dy, closeTo(150.0, 0.01));
      expect(corners90.angleDegrees, closeTo(90.0, 0.01));
    });
  });

  group('KtpCameraScreen Configuration Tests', () {
    test('KtpCameraScreen has configurable focusHoldDurationMs, enableGallery, and loadingColor', () {
      const screenDefault = KtpCameraScreen();
      expect(screenDefault.autoCapture, isTrue);
      expect(screenDefault.focusHoldDurationMs, equals(1300));
      expect(screenDefault.enableGallery, isTrue);
      expect(screenDefault.loadingColor, equals(const Color(0xFFF59E0B)));

      const screenCustom = KtpCameraScreen(
        autoCapture: true,
        focusHoldDurationMs: 1500,
        title: 'Custom Focus Delay',
        enableGallery: false,
        loadingColor: Color(0xFF8B5CF6),
      );
      expect(screenCustom.focusHoldDurationMs, equals(1500));
      expect(screenCustom.title, equals('Custom Focus Delay'));
      expect(screenCustom.enableGallery, isFalse);
      expect(screenCustom.loadingColor, equals(const Color(0xFF8B5CF6)));
    });
  });
}
