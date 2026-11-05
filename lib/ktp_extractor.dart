import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'utils/ext.dart';
import 'utils/utils.dart';

import 'models/kartu_keluarga_model.dart';
import 'models/kartu_keluarga_validation.dart';
import 'models/ktp_model.dart';
import 'models/passport_model.dart';
import 'models/smart_document_type.dart';
import 'models/surat_sehat_model.dart';
import 'models/surat_sehat_validation.dart';
import 'utils/document_cropper.dart';
import 'utils/kk_extractor_helper.dart';
import 'utils/surat_sehat_extractor_helper.dart';

export 'models/kartu_keluarga_model.dart';
export 'models/kartu_keluarga_validation.dart';
export 'models/ktp_camera_result.dart';
export 'models/ktp_model.dart';
export 'models/passport_model.dart';
export 'models/smart_document_type.dart';
export 'models/surat_sehat_model.dart';
export 'models/surat_sehat_validation.dart';
export 'ui/ktp_camera_screen.dart';
export 'ui/smart_document_camera_screen.dart';
export 'ui/smart_document_stepper_header.dart';
export 'ui/smart_document_watermark_painter.dart';

/// A utility class for extracting information from KTP (Indonesian ID card) and Passport images.
class KtpExtractor {
  static const String _genderKey = 'gender';
  static const String _religionKey = 'religion';
  static const String _maritalKey = 'marital';
  static const String _nationalityKey = 'nationality';

  /// A map of expected words for certain fields to assist in data correction.
  static final Map<String, List<String>> _expectedWords = {
    _genderKey: ['LAKI-LAKI', 'PEREMPUAN'],
    _religionKey: [
      'ISLAM',
      'KRISTEN',
      'KATOLIK',
      'HINDU',
      'BUDDHA',
      'KHONGHUCU'
    ],
    _maritalKey: ['KAWIN', 'BELUM KAWIN'],
    _nationalityKey: ['WNI', 'WNA'],
  };

  /// Crops any document (KTP, Kartu Keluarga, Surat Sehat) neatly around its borders.
  static Future<File?> cropDocument(
    File imageFile,
    SmartDocumentType type,
  ) async {
    if (type == SmartDocumentType.ktp) {
      final ktpCrop = await cropImageForKtp(imageFile);
      if (ktpCrop != null) return ktpCrop;
    }
    return DocumentCropper.cropDocument(imageFile, type);
  }

  /// Crops the KTP area from the provided image.
  ///
  /// Uses high-precision text-guided ID-1 boundary detection for a neat, snug crop
  /// around the physical KTP card, with fallback to TensorFlow Lite object detection.
  ///
  /// [imageFile]: The image file containing the KTP.
  static Future<File?> cropImageForKtp(File imageFile) async {
    // 1. High-precision text-guided card boundary detection
    try {
      final TextRecognizer recognizer = TextRecognizer();
      final InputImage inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);
      await recognizer.close();

      const List<String> ktpKeywords = [
        'PROVINSI',
        'KABUPATEN',
        'KOTA',
        'NIK',
        'AGAMA',
        'STATUS',
        'PERKAWINAN',
        'DARAH',
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
      ];

      final String fullText = recognizedText.text.toUpperCase();
      int matchedKeywords = 0;
      for (final kw in ktpKeywords) {
        if (fullText.contains(kw)) matchedKeywords++;
      }

      bool hasNik = false;
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final digits = line.text.filterNumbersOnly();
          if (digits.length == 16) {
            hasNik = true;
            break;
          }
        }
        if (hasNik) break;
      }

      if (!hasNik) {
        final reg16 = RegExp(r'\b\d{16}\b');
        if (reg16.hasMatch(fullText.replaceAll(' ', ''))) {
          hasNik = true;
        }
      }

      if (hasNik || (matchedKeywords >= 2 && fullText.length >= 20)) {
        // 1. Calculate skew/tilt angle of the KTP card from text line orientations
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

        // 2. Locate the primary KTP front card anchor (NIK or primary identity keywords)
        // This ensures that if the image contains both front and back cards, or multiple documents,
        // we only crop the FRONT card containing NIK and profile photo.
        TextLine? nikLine;
        double? nikV;
        double? nikU;

        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            final lineDigits = line.text.filterNumbersOnly();
            final upperLine = line.text.toUpperCase();
            if (lineDigits.length == 16 || upperLine.contains('NIK')) {
              nikLine = line;
              final r = line.boundingBox;
              nikU = (r.left + r.width / 2) * cosT + (r.top + r.height / 2) * sinT;
              nikV = -(r.left + r.width / 2) * sinT + (r.top + r.height / 2) * cosT;
              break;
            }
          }
          if (nikLine != null) break;
        }

        // 3. Project relevant front-card text into the card's rotated frame (u, v)
        // u = along text line (width), v = perpendicular to text line (height)
        double minU = double.infinity;
        double maxU = double.negativeInfinity;
        double minV = double.infinity;
        double maxV = double.negativeInfinity;

        void updateUV(double x, double y) {
          final double u = x * cosT + y * sinT;
          final double v = -x * sinT + y * cosT;
          if (u < minU) minU = u;
          if (u > maxU) maxU = u;
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }

        // Front-card specific keywords (exclude back card texts like "KARTU TANDA PENDUDUK")
        const List<String> frontCardExclusiveKeywords = [
          'NIK',
          'PROVINSI',
          'KABUPATEN',
          'KOTA',
          'AGAMA',
          'STATUS',
          'PERKAWINAN',
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
        ];

        for (final block in recognizedText.blocks) {
          final blockText = block.text.toUpperCase();

          // Reject blocks from back card
          if (blockText.contains('KARTU TANDA PENDUDUK') && !blockText.contains('NIK')) {
            continue;
          }

          // If NIK anchor was detected, enforce vertical proximity to the front card
          if (nikV != null && nikU != null) {
            final r = block.boundingBox;
            final double cv = -(r.left + r.width / 2) * sinT + (r.top + r.height / 2) * cosT;
            final double cu = (r.left + r.width / 2) * cosT + (r.top + r.height / 2) * sinT;
            // On a standard KTP, header is at most ~160px above NIK, footer is at most ~320px below NIK
            // Anything significantly below NIK + 350 is part of another card/page (e.g. back card)
            final double vDiff = cv - nikV;
            if (vDiff < -220 || vDiff > 320) {
              continue;
            }
            if ((cu - nikU).abs() > 800) {
              continue;
            }
          }

          bool isRelevant = false;
          for (final kw in frontCardExclusiveKeywords) {
            if (blockText.contains(kw)) {
              isRelevant = true;
              break;
            }
          }
          if (!isRelevant) {
            for (final line in block.lines) {
              if (line.text.filterNumbersOnly().length >= 8) {
                isRelevant = true;
                break;
              }
            }
          }

          if (isRelevant) {
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
        }

        if (minU < maxU && minV < maxV) {
          // Include nearby text (e.g. signature, date) strictly within the single front card area in (u, v) space
          for (final block in recognizedText.blocks) {
            final blockText = block.text.toUpperCase();
            if (blockText.contains('KARTU TANDA PENDUDUK') && !blockText.contains('NIK')) {
              continue;
            }

            final r = block.boundingBox;
            final double cu =
                (r.left + r.width / 2) * cosT + (r.top + r.height / 2) * sinT;
            final double cv =
                -(r.left + r.width / 2) * sinT + (r.top + r.height / 2) * cosT;
            if (cv >= minV - 25 &&
                cv <= maxV + 35 &&
                cu >= minU - 40 &&
                cu <= maxU + 260) {
              for (final line in block.lines) {
                if (line.cornerPoints.isNotEmpty) {
                  for (final p in line.cornerPoints) {
                    updateUV(p.x.toDouble(), p.y.toDouble());
                  }
                }
              }
            }
          }

          final double textHeight = maxV - minV;
          if (textHeight >= 35) {
            // Standard ID-1 KTP card: text spans ~84.7% of card height
            double cardHeight = textHeight * 1.186;
            double cardWidth = cardHeight * 1.5858;
            final double cardULeft = minU - (cardWidth * 0.047);
            final double cardVTop = minV - (textHeight * 0.077);

            // If signature/photo text on the right extends further within front card, accommodate it
            if (maxU > cardULeft + (cardWidth * 0.94)) {
              final double extendedWidth = (maxU - cardULeft) / 0.95;
              // Guard against abnormal ballooning
              if (extendedWidth <= cardWidth * 1.25) {
                cardWidth = extendedWidth;
                cardHeight = cardWidth / 1.5858;
              }
            }

            final double cardUCenter = cardULeft + (cardWidth / 2.0);
            final double cardVCenter = cardVTop + (cardHeight / 2.0);

            // Back-project card center into original image coordinates (x, y)
            final double cardCenterX = cardUCenter * cosT - cardVCenter * sinT;
            final double cardCenterY = cardUCenter * sinT + cardVCenter * cosT;

            final tightCrop = await cropAndDeskewImage(
              imageFile,
              Rect.fromCenter(
                center: Offset(cardCenterX, cardCenterY),
                width: cardWidth,
                height: cardHeight,
              ),
              angleDegrees: tiltAngle,
            );
            if (tightCrop != null) {
              return tightCrop;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Text-guided card detection error, fallback to TFLite: $e');
      }
    }

    // 2. Fallback to TFLite Object Detection
    final modelPath = await getAssetPath(
        'packages/smart_id_extractor/assets/custom_models/object_labeler.tflite');

    final options = LocalObjectDetectorOptions(
      mode: DetectionMode.single,
      modelPath: modelPath,
      classifyObjects: true,
      multipleObjects: true,
    );

    final ObjectDetector detector = ObjectDetector(options: options);
    final InputImage inputImage = InputImage.fromFile(imageFile);
    final result = await detector.processImage(inputImage);

    File? imageCropped;

    // Iterate over detected objects to find the KTP.
    for (final object in result) {
      if (kDebugMode) {
        print('Object found: ${object.labels.map((e) => e.text)}');
      }
      if (object.labels.firstOrNull?.text == "Driver's license") {
        // Crop the image to the detected KTP area.
        imageCropped = await cropImage(File(inputImage.filePath!), object);
        break;
      }
    }

    await detector.close();
    return imageCropped;
  }

  /// Extracts/crops the profile photo area from a KTP image.
  ///
  /// Useful for populating the user's account profile picture from their e-KTP.
  /// [ktpImageFile]: Either the cropped KTP image or the full captured KTP image.
  static Future<File?> cropKtpPhotoFile(File ktpImageFile) async {
    return cropKtpPhoto(ktpImageFile);
  }

  /// Extracts KTP information from the provided image file.
  ///
  /// This method performs text recognition on the image to extract
  /// various fields from the KTP, such as NIK, name, birth date, etc.
  ///
  /// [imageFile]: The image file of the KTP.
  static Future<KtpModel> extractKtp(File imageFile) async {
    final TextRecognizer recognizer = TextRecognizer();
    final InputImage inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText =
        await recognizer.processImage(inputImage);
    await recognizer.close();

    return extractFromOcr(recognizedText);
  }

  /// Extracts KTP information from recognized text.
  ///
  /// This method parses the recognized text from OCR to extract
  /// KTP fields and returns a [KtpModel] containing the extracted data.
  ///
  /// [recognizedText]: The recognized text from OCR.
  static KtpModel extractFromOcr(RecognizedText recognizedText) {
    String? nik;
    String? name;
    String? placeBirth;
    String? birthDay;
    String? gender;
    String? address;
    String? rt;
    String? rw;
    String? subDistrict;
    String? district;
    String? province;
    String? city;
    String? religion;
    String? marital;
    String? occupation;
    String? nationality;
    String? validUntil;

    if (kDebugMode) {
      print('Result text: ${recognizedText.text}');
    }

    // Iterate over text blocks and lines to extract information.
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final String text = line.text;

        // Extract Province.
        if (text.toLowerCase().startsWith('provinsi')) {
          final lineText = text.cleanse('provinsi').filterNumberToAlphabet();
          province = lineText;
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }
        // Extract City.
        if (text.toLowerCase().startsWith('kota') ||
            text.toLowerCase().startsWith('kabupaten') ||
            text.toLowerCase().startsWith('jakarta')) {
          final lineText = text.filterNumberToAlphabet();
          city = lineText;
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract NIK (Identity Number).
        if (nik == null && text.filterNumbersOnly().length == 16) {
          nik = text.filterNumbersOnly();
          if (kDebugMode) {
            print('NIK Found: ${line.text}');
            print('NIK Filtered: $nik');
          }
        }
        if (nik == null && text.toLowerCase().startsWith('nik')) {
          final lineText = recognizedText.findAndClean(line, 'NIK');
          nik = lineText?.filterNumbersOnly().removeAlphabet();
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
            print('Line Text Filtered: $nik');
          }
        }

        // Extract Name.
        if (text.toLowerCase().startsWith('nama')) {
          final lineText = recognizedText
              .findAndClean(line, 'nama')
              ?.filterNumberToAlphabet();
          name = lineText;
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Place and Date of Birth.
        if (text.toLowerCase().contains(RegExp('tempat')) &&
            text.toLowerCase().contains(RegExp('lahir'))) {
          if (kDebugMode) {
            print('Text: $text');
          }
          String? lineText =
              recognizedText.findAndClean(line, 'tempat/tgl lahir') ??
                  recognizedText.findAndClean(line, 'tempat/tgl') ??
                  recognizedText.findAndClean(line, 'tempat tgl lahir') ??
                  recognizedText.findAndClean(line, 'tempat lahir');
          if (lineText != null) {
            lineText = lineText
                .cleanse('tempat/tgl lahir')
                .cleanse('tempat/tgl')
                .cleanse('tempat tgl lahir')
                .cleanse('tempat')
                .cleanse('tgl lahir')
                .cleanse('tgl')
                .cleanse('lahir');
            if (lineText.contains('/')) {
              lineText = lineText.replaceAll('/', '');
            }
          }
          final List<String> splitBirth = lineText?.split(',') ?? [];
          if (kDebugMode) {
            print('Split Place of Birth: $splitBirth');
          }
          if (splitBirth.isNotEmpty) {
            String pBirth = splitBirth[0].filterNumberToAlphabet().trim();
            // Bersihkan sisa-sisa label OCR typo seperti "Tgl Lahir", "Tgi Lahir", "Lahir"
            pBirth = pBirth
                .replaceFirst(
                    RegExp(r'^(tempat|tgl|tgi|lahir)+', caseSensitive: false),
                    '')
                .trim();
            placeBirth = pBirth.isNotEmpty ? pBirth : null;
            if (splitBirth.length > 1) {
              birthDay = splitBirth[1].filterAlphabetToNumber().trim();
            }
          }
          if (kDebugMode) {
            print('Line Text: $lineText');
          }
        }

        // Extract Gender.
        if (text.toLowerCase().contains('jenis kelamin') ||
            (text.toLowerCase().contains('jenis') &&
                text.toLowerCase().contains('kelamin'))) {
          String? lineText = recognizedText.findAndClean(line, 'jenis kelamin');
          if (lineText != null) {
            // Hilangkan "Gol. Darah" jika ikut tertangkap dalam satu baris
            lineText = lineText
                .split(RegExp(r'gol\.?\s*darah', caseSensitive: false))
                .first
                .trim();
            lineText = lineText.filterNumberToAlphabet();
            gender = lineText.correctWord(_expectedWords[_genderKey]!);
          }
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Address.
        if (text.toLowerCase().startsWith('alamat')) {
          final lineText = recognizedText.findAndClean(line, 'alamat');
          address = lineText;
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract RT/RW (Neighborhood and Hamlet numbers).
        if (text.toLowerCase().contains(RegExp(r'r[ti]')) &&
            text.toLowerCase().contains(RegExp(r'rw'))) {
          if (kDebugMode) {
            print('Text: $text');
          }
          String? lineText = recognizedText.findAndClean(line, 'RTRW') ??
              recognizedText.findAndClean(line, 'RT/RW');
          if (lineText != null) {
            lineText = lineText.cleanse('rtrw').cleanse('rt').cleanse('rw');
          }
          final List<String> splitRtRw =
              lineText?.filterAlphabetToNumber().removeAlphabet().split('/') ??
                  [];
          if (splitRtRw.isEmpty ||
              (splitRtRw.length == 1 && splitRtRw[0].isEmpty)) {
            // Coba cari pola angka 001/007 langsung dari teks baris
            final match = RegExp(r'(\d{2,3})\s*[\/\|\s]\s*(\d{2,3})')
                .firstMatch(lineText?.filterAlphabetToNumber() ??
                    text.filterAlphabetToNumber());
            if (match != null) {
              rt = match.group(1);
              rw = match.group(2);
            }
          } else {
            rt = splitRtRw[0];
            if (splitRtRw.length > 1) {
              rw = splitRtRw[1];
            } else if (rt.length >= 4) {
              rw = rt.substring(rt.length ~/ 2);
              rt = rt.substring(0, rt.length ~/ 2);
            }
          }
          if (kDebugMode) {
            print('Line Text: $lineText');
          }
        }

        // Extract Sub-District (Kel/Desa).
        if (text.toLowerCase().contains('desa') ||
            text.toLowerCase().contains('kel')) {
          final lineText = recognizedText.findAndClean(line, 'kel/desa') ??
              recognizedText.findAndClean(line, 'keldesa') ??
              recognizedText.findAndClean(line, 'desa');
          if (lineText != null) {
            subDistrict = lineText
                .cleanse('kel/desa')
                .cleanse('keldesa')
                .cleanse('desa')
                .filterNumberToAlphabet()
                .trim();
          }
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract District (Kecamatan).
        if (district == null &&
            (text.toLowerCase().contains('kecamatan') ||
                text.toLowerCase().contains('kecamalan') ||
                text.toLowerCase().trim().startsWith('kec.') ||
                text.toLowerCase().trim().startsWith('kec '))) {
          final lineText = recognizedText.findAndClean(line, 'kecamatan') ??
              recognizedText.findAndClean(line, 'kecamalan') ??
              recognizedText.findAndClean(line, 'kec.');
          if (lineText != null) {
            district = lineText
                .cleanse('kecamatan')
                .cleanse('kecamalan')
                .cleanse('kec.')
                .filterNumberToAlphabet()
                .trim();
          }
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Religion.
        if (religion == null &&
            (text.toLowerCase().contains('agama') ||
                text.toLowerCase().contains('gama'))) {
          final lineText = recognizedText.findAndClean(line, 'agama');
          religion = lineText
              ?.filterNumberToAlphabet()
              .correctWord(_expectedWords[_religionKey]!);
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Marital Status.
        if (marital == null &&
            (text.toLowerCase().contains('perkawinan') ||
                text.toLowerCase().contains('status'))) {
          final lineText =
              recognizedText.findAndClean(line, 'status perkawinan') ??
                  recognizedText.findAndClean(line, 'perkawinan');
          marital = lineText
              ?.filterNumberToAlphabet()
              .correctWord(_expectedWords[_maritalKey]!);
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Occupation.
        if (occupation == null &&
            (text.toLowerCase().contains('pekerjaan') ||
                text.toLowerCase().contains('pekeriaan') ||
                text.toLowerCase().contains('kerjaan'))) {
          final lineText = recognizedText.findAndClean(line, 'pekerjaan') ??
              recognizedText.findAndClean(line, 'pekeriaan') ??
              recognizedText.findAndClean(line, 'kerjaan');
          occupation = lineText?.filterNumberToAlphabet().trim();
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Nationality.
        if (nationality == null &&
            (text.toLowerCase().contains('kewarganegaraan') ||
                text.toLowerCase().contains('kewarga') ||
                text.toLowerCase().contains('warganegara'))) {
          final lineText =
              recognizedText.findAndClean(line, 'kewarganegaraan') ??
                  recognizedText.findAndClean(line, 'kewarga');
          nationality = lineText
              ?.filterNumberToAlphabet()
              .correctWord(_expectedWords[_nationalityKey]!);
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }

        // Extract Valid Until date.
        if (validUntil == null &&
            (text.toLowerCase().contains('berlaku') ||
                text.toLowerCase().contains('hingga'))) {
          final lineText =
              recognizedText.findAndClean(line, 'berlaku hingga') ??
                  recognizedText.findAndClean(line, 'berlaku');
          validUntil = lineText?.filterNumberToAlphabet().trim();
          if (kDebugMode) {
            print('Text: $text');
            print('Line Text: $lineText');
          }
        }
      }
    }

    // Heuristic fallbacks if label detection missed values present in the text
    if (validUntil == null || validUntil.isEmpty) {
      if (recognizedText.text.toUpperCase().contains('SEUMUR HIDUP') ||
          recognizedText.text.toUpperCase().contains('SEUMUR')) {
        validUntil = 'SEUMUR HIDUP';
      }
    }

    if (nationality == null || nationality.isEmpty) {
      final upperText = recognizedText.text.toUpperCase();
      if (upperText.contains('WNI') || upperText.contains('INDONESIA')) {
        nationality = 'WNI';
      } else if (upperText.contains('WNA')) {
        nationality = 'WNA';
      }
    }

    if (gender == null || gender.isEmpty) {
      final upperText = recognizedText.text.toUpperCase();
      if (upperText.contains('LAKI-LAKI') ||
          upperText.contains('LAKI - LAKI') ||
          upperText.contains('LAKI') ||
          upperText.contains('LAK-LAKI') ||
          upperText.contains('LAKHLAK') ||
          upperText.contains('HAKEAK')) {
        gender = 'LAKI-LAKI';
      } else if (upperText.contains('PEREMPUAN') ||
          upperText.contains('REMPUAN')) {
        gender = 'PEREMPUAN';
      }
    }

    if (religion == null || religion.isEmpty) {
      final upperText = recognizedText.text.toUpperCase();
      for (final rel in _expectedWords[_religionKey]!) {
        if (upperText.contains(rel)) {
          religion = rel;
          break;
        }
      }
      if (religion == null) {
        // Deteksi typo OCR umum untuk agama
        if (RegExp(r'\b(1SLAM|ISTAM|SLAM|SEAM|ŞEAM|ISLA)\b')
                .hasMatch(upperText) ||
            upperText.contains('1SLAM') ||
            upperText.contains('ISTAME') ||
            upperText.contains('ŞEAM') ||
            upperText.contains('1SAM')) {
          religion = 'ISLAM';
        } else if (upperText.contains('KRIS') || upperText.contains('TEN')) {
          religion = 'KRISTEN';
        } else if (upperText.contains('KAT') || upperText.contains('TOLIK')) {
          religion = 'KATOLIK';
        } else if (upperText.contains('HIN') || upperText.contains('NDU')) {
          religion = 'HINDU';
        } else if (upperText.contains('BUD') || upperText.contains('DDHA')) {
          religion = 'BUDDHA';
        }
      }
    }

    if (occupation == null || occupation.isEmpty) {
      final upperText = recognizedText.text.toUpperCase();
      const commonOccupations = [
        'BELUM/TIDAK BEKERJA',
        'MENGURUS RUMAH TANGGA',
        'PELAJAR/MAHASISWA',
        'PEGAWAI NEGERI SIPIL',
        'TENTARA NASIONAL INDONESIA',
        'KEPOLISIAN RI',
        'PERDAGANGAN',
        'PETANI/PEKEBUN',
        'PETERNAK',
        'NELAYAN/PERIKANAN',
        'INDUSTRI',
        'KONSTRUKSI',
        'TRANSPORTASI',
        'KARYAWAN SWASTA',
        'KARYAWAN BUMN',
        'KARYAWAN BUMD',
        'KARYAWAN HONORER',
        'BURUH HARIAN LEPAS',
        'BURUH TANI/PERKEBUNAN',
        'BURUH NELAYAN/PERIKANAN',
        'BURUH PETERNAKAN',
        'PEMBANTU RUMAH TANGGA',
        'TUKANG CUKUR',
        'TUKANG LISTRIK',
        'TUKANG BATU',
        'TUKANG KAYU',
        'TUKANG LAS/PANDAI BESI',
        'TUKANG JAHIT',
        'TUKANG GIGI',
        'PENATA RIAS',
        'PENATA BUSANA',
        'PENATA RAMBUT',
        'MEKANIK',
        'SENIMAN',
        'TABIB',
        'PARAJI',
        'PERANCANG BUSANA',
        'PENTERJEMAH',
        'IMAM MASJID',
        'PENDETA',
        'PASTOR',
        'WARTAWAN',
        'USTADZ/MUBALIGH',
        'JURU MASAK',
        'PROMOTOR ACARA',
        'ANGGOTA DPR-RI',
        'ANGGOTA DPD',
        'ANGGOTA BPK',
        'PRESIDEN',
        'WAKIL PRESIDEN',
        'ANGGOTA MAHKAMAH KONSTITUSI',
        'ANGGOTA KABINET/MENTERI',
        'DUTA BESAR',
        'GUBERNUR',
        'WAKIL GUBERNUR',
        'BUPATI',
        'WAKIL BUPATI',
        'WALIKOTA',
        'WAKIL WALIKOTA',
        'ANGGOTA DPRD PROVINSI',
        'ANGGOTA DPRD KABUPATEN/KOTA',
        'DOSEN',
        'GURU',
        'PILOT',
        'PENGACARA',
        'NOTARIS',
        'ARSITEK',
        'AKUNTAN',
        'KONSULTAN',
        'DOKTER',
        'BIDAN',
        'PERAWAT',
        'APOTEKER',
        'PSIKIATER/PSIKOLOG',
        'PENYIAR TELEVISI',
        'PENYIAR RADIO',
        'PELAUT',
        'PENELITI',
        'SOPIR',
        'PIALANG',
        'PARANORMAL',
        'PEDAGANG',
        'PERANGKAT DESA',
        'KEPALA DESA',
        'BIARAWATI',
        'WIRASWASTA',
      ];
      for (final occ in commonOccupations) {
        if (upperText.contains(occ)) {
          occupation = occ;
          break;
        }
      }
      if (occupation == null) {
        if (upperText.contains('PELAJAR') ||
            upperText.contains('MAHASISWA') ||
            upperText.contains('PELA') ||
            upperText.contains('LAJAR')) {
          occupation = 'PELAJAR/MAHASISWA';
        } else if (upperText.contains('WIRASWASTA')) {
          occupation = 'WIRASWASTA';
        } else if (upperText.contains('KARYAWAN')) {
          occupation = 'KARYAWAN SWASTA';
        }
      }
    }

    if (rt == null || rw == null) {
      final upperText = recognizedText.text.toUpperCase();
      final match = RegExp(
              r'\b([0-9OIlBZzDeLT]{2,3})\s*[\/\|\s]\s*([0-9OIlBZzDeLT]{2,3})\b')
          .firstMatch(upperText);
      if (match != null) {
        rt ??= match.group(1)?.filterAlphabetToNumber();
        rw ??= match.group(2)?.filterAlphabetToNumber();
      }
    }

    if (marital == null || marital.isEmpty) {
      final upperText = recognizedText.text.toUpperCase();
      if (upperText.contains('BELUM KAWIN')) {
        marital = 'BELUM KAWIN';
      } else if (upperText.contains('CERAI MATI')) {
        marital = 'CERAI MATI';
      } else if (upperText.contains('CERAI HIDUP')) {
        marital = 'CERAI HIDUP';
      } else if (upperText.contains('KAWIN')) {
        marital = 'KAWIN';
      }
    }

    if (kDebugMode) {
      print('========================================');
      print('=============== RESULT =================');
      print('NIK: $nik');
      print('Name: $name');
      print('Birth Day: $birthDay');
      print('Place of Birth: $placeBirth');
      print('Gender: $gender');
      print('Address: $address');
      print('RT/RW: $rt / $rw');
      print('Sub-District: $subDistrict');
      print('District: $district');
      print('Province: $province');
      print('City: $city');
      print('Religion: $religion');
      print('Marital Status: $marital');
      print('Occupation: $occupation');
      print('Nationality: $nationality');
      print('Valid Until: $validUntil');
      print('============= END RESULT ===============');
      print('========================================');
    }

    // Return a KtpModel containing the extracted information.
    return KtpModel(
      address: address,
      district: district,
      gender: gender,
      marital: marital,
      name: name,
      birthDay: birthDay,
      placeBirth: placeBirth,
      nationality: nationality,
      nik: nik,
      occupation: occupation,
      religion: religion,
      rt: rt,
      rw: rw,
      subDistrict: subDistrict,
      province: province,
      city: city,
      validUntil: validUntil,
    );
  }

  /// Crops the passport area from the provided image using object detection.
  ///
  /// This method uses ML Kit object detection to detect and crop the passport
  /// area, specifically focusing on the MRZ (Machine Readable Zone) at the bottom.
  ///
  /// [imageFile]: The image file containing the passport.
  static Future<File?> cropImageForPassport(File imageFile) async {
    final modelPath = await getAssetPath(
        'packages/smart_id_extractor/assets/custom_models/object_labeler.tflite');
    final options = LocalObjectDetectorOptions(
      modelPath: modelPath,
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    );

    final ObjectDetector detector = ObjectDetector(options: options);
    final InputImage inputImage = InputImage.fromFile(imageFile);
    final result = await detector.processImage(inputImage);

    File? mrzCropped;

    for (final object in result) {
      if (kDebugMode) {
        print('Object found for passport: ${object.boundingBox}');
      }

      if (object.labels.firstOrNull?.text == "Driver's license") {
        final aspectRatio =
            (object.boundingBox.right - object.boundingBox.left) /
                (object.boundingBox.bottom - object.boundingBox.top);

        if (aspectRatio > 1.2 && aspectRatio < 2.0) {
          mrzCropped =
              await cropPassportMrz(File(inputImage.filePath!), object);
          break;
        }
      }
    }

    await detector.close();
    return mrzCropped;
  }

  /// Extracts passport MRZ information from the provided image file.
  ///
  /// This method performs text recognition on the MRZ area to extract
  /// passport fields according to ICAO standards.
  ///
  /// [imageFile]: The image file of the passport MRZ.
  static Future<PassportModel> extractPassport(File imageFile) async {
    final TextRecognizer recognizer = TextRecognizer();
    final InputImage inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText =
        await recognizer.processImage(inputImage);
    await recognizer.close();

    return extractMrzFromOcr(recognizedText);
  }

  /// Extracts passport MRZ information from recognized text.
  ///
  /// This method parses the recognized text from OCR according to ICAO
  /// MRZ standards and returns a [PassportModel] containing the extracted data.
  ///
  /// [recognizedText]: The recognized text from OCR.
  static PassportModel extractMrzFromOcr(RecognizedText recognizedText) {
    if (kDebugMode) {
      print('MRZ Result text: ${recognizedText.text}');
    }

    final List<String> mrzLines =
        recognizedText.text.extractMrzLines(recognizedText.text);

    if (mrzLines.length < 2) {
      if (kDebugMode) {
        print('Insufficient MRZ lines found: ${mrzLines.length}');
      }
      return const PassportModel();
    }

    final String line1 = mrzLines[0];
    final String line2 = mrzLines[1];

    if (kDebugMode) {
      print('MRZ Line 1: $line1');
      print('MRZ Line 2: $line2');
    }

    String? documentType;
    String? issuingCountry;
    String? surname;
    String? givenNames;
    String? passportNumber;
    String? nationality;
    String? birthDate;
    String? gender;
    String? expiryDate;
    String? personalNumber;
    String? compositeCheckDigit;

    if (line1.startsWith('P<')) {
      documentType = 'P';
      issuingCountry = line1.substring(2, 5).replaceAll('<', '');

      final nameSection = line1.substring(5);
      final nameParts = nameSection.split('<<');

      if (nameParts.isNotEmpty) {
        surname = nameParts[0].replaceAll('<', ' ').trim();
      }

      if (nameParts.length > 1) {
        givenNames = nameParts[1].replaceAll('<', ' ').trim();
      }
    }

    if (line2.length >= 44) {
      final passportSection = line2.substring(0, 9);
      passportNumber = passportSection.replaceAll('<', '').trim();
      if (passportNumber.isEmpty) passportNumber = null;

      final passportCheckDigit = line2.substring(9, 10);
      if (passportNumber != null) {
        final isValidPassport =
            validateMrzChecksum(passportNumber, passportCheckDigit);
        if (kDebugMode) {
          print('Passport number validation: $isValidPassport');
        }
      }

      nationality = line2.substring(10, 13).replaceAll('<', '');
      if (nationality.isEmpty) nationality = null;

      final birthDateRaw = line2.substring(13, 19);
      if (birthDateRaw.replaceAll('<', '').length == 6) {
        birthDate = birthDateRaw;
        final birthCheckDigit = line2.substring(19, 20);
        final isValidBirth = validateMrzChecksum(birthDateRaw, birthCheckDigit);
        if (kDebugMode) {
          print('Birth date validation: $isValidBirth');
        }
      }

      gender = line2.substring(20, 21);
      if (gender == '<') gender = null;

      final expiryDateRaw = line2.substring(21, 27);
      if (expiryDateRaw.replaceAll('<', '').length == 6) {
        expiryDate = expiryDateRaw;
        final expiryCheckDigit = line2.substring(27, 28);
        final isValidExpiry =
            validateMrzChecksum(expiryDateRaw, expiryCheckDigit);
        if (kDebugMode) {
          print('Expiry date validation: $isValidExpiry');
        }
      }

      if (line2.length > 28) {
        personalNumber = line2.substring(28, 42).replaceAll('<', '');
        if (personalNumber.isEmpty) personalNumber = null;

        compositeCheckDigit = line2.substring(43, 44);
      }
    }

    if (kDebugMode) {
      print('========================================');
      print('============ MRZ RESULT ================');
      print('Document Type: $documentType');
      print('Issuing Country: $issuingCountry');
      print('Surname: $surname');
      print('Given Names: $givenNames');
      print('Passport Number: $passportNumber');
      print('Nationality: $nationality');
      print('Birth Date: $birthDate');
      print('Gender: $gender');
      print('Expiry Date: $expiryDate');
      print('Personal Number: $personalNumber');
      print('Composite Check Digit: $compositeCheckDigit');
      print('=========== END MRZ RESULT =============');
      print('========================================');
    }

    return PassportModel(
      documentType: documentType,
      issuingCountry: issuingCountry,
      surname: surname,
      givenNames: givenNames,
      passportNumber: passportNumber,
      nationality: nationality,
      birthDate: birthDate,
      gender: gender,
      expiryDate: expiryDate,
      personalNumber: personalNumber,
      compositeCheckDigit: compositeCheckDigit,
      mrz1: line1,
      mrz2: line2,
    );
  }

  /// Validates whether the provided image file is an authentic Indonesian Kartu Keluarga (KK).
  ///
  /// Evaluates document structure against [options] (e.g. 16-digit Nomor KK requirement,
  /// header detection, and characteristic keyword density).
  ///
  /// [imageFile]: The image file containing the Kartu Keluarga document.
  /// [options]: Validation criteria to apply (e.g. requireNomorKk, requireHeader, minKeywordMatches).
  static Future<KartuKeluargaValidationResult> validateKartuKeluarga(
    File imageFile, {
    KartuKeluargaValidationOptions options =
        const KartuKeluargaValidationOptions(),
  }) async {
    final TextRecognizer recognizer = TextRecognizer();
    try {
      final InputImage inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);

      return KkExtractorHelper.validateFromText(
        recognizedText.text,
        options: options,
        recognizedText: recognizedText,
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Validates whether raw OCR text represents an authentic Kartu Keluarga.
  ///
  /// Useful for offline or test evaluations without reprocessing images.
  ///
  /// [rawText]: Raw text output from OCR.
  /// [options]: Validation criteria to apply.
  static KartuKeluargaValidationResult validateKartuKeluargaFromText(
    String rawText, {
    KartuKeluargaValidationOptions options =
        const KartuKeluargaValidationOptions(),
  }) {
    return KkExtractorHelper.validateFromText(rawText, options: options);
  }

  /// Convenience boolean check to quickly verify if an image is a Kartu Keluarga.
  ///
  /// Returns `true` if all default mandatory criteria (16-digit No KK, header, keywords) pass.
  static Future<bool> isKartuKeluarga(
    File imageFile, {
    bool requireNomorKk = true,
    int minKeywordMatches = 3,
  }) async {
    final result = await validateKartuKeluarga(
      imageFile,
      options: KartuKeluargaValidationOptions(
        requireNomorKk: requireNomorKk,
        minKeywordMatches: minKeywordMatches,
      ),
    );
    return result.isValid;
  }

  /// Extracts structured data from a Kartu Keluarga image.
  static Future<KartuKeluargaModel> extractKartuKeluarga(File imageFile) async {
    final validation = await validateKartuKeluarga(
      imageFile,
      options: const KartuKeluargaValidationOptions(
        requireNomorKk: false,
        requireHeader: false,
        minKeywordMatches: 1,
      ),
    );
    return validation.data ?? const KartuKeluargaModel();
  }

  /// Extracts structured data from raw Kartu Keluarga OCR text.
  static KartuKeluargaModel extractKartuKeluargaFromText(String rawText) {
    final validation = validateKartuKeluargaFromText(
      rawText,
      options: const KartuKeluargaValidationOptions(
        requireNomorKk: false,
        requireHeader: false,
        minKeywordMatches: 1,
      ),
    );
    return validation.data ?? const KartuKeluargaModel();
  }

  // ---------------------------------------------------------------------------
  // Surat Keterangan Sehat / Dokter Verification & Extraction
  // ---------------------------------------------------------------------------

  /// Validates an image against authentic Indonesian Surat Keterangan Sehat/Dokter criteria.
  static Future<SuratSehatValidationResult> validateSuratSehat(
    File imageFile, {
    SuratSehatValidationOptions options = const SuratSehatValidationOptions(),
  }) async {
    final TextRecognizer recognizer = TextRecognizer();
    try {
      final InputImage inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);

      return SuratSehatExtractorHelper.validateFromText(
        recognizedText.text,
        options: options,
        recognizedText: recognizedText,
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Validates whether raw OCR text represents an authentic Surat Keterangan Sehat.
  static SuratSehatValidationResult validateSuratSehatFromText(
    String rawText, {
    SuratSehatValidationOptions options = const SuratSehatValidationOptions(),
  }) {
    return SuratSehatExtractorHelper.validateFromText(rawText, options: options);
  }

  /// Convenience boolean check to quickly verify if an image is a Surat Keterangan Sehat.
  static Future<bool> isSuratSehat(
    File imageFile, {
    bool requireHeader = true,
    int minKeywordMatches = 2,
  }) async {
    final result = await validateSuratSehat(
      imageFile,
      options: SuratSehatValidationOptions(
        requireHeader: requireHeader,
        minKeywordMatches: minKeywordMatches,
      ),
    );
    return result.isValid;
  }

  /// Extracts structured data from a Surat Keterangan Sehat image.
  static Future<SuratSehatModel> extractSuratSehat(File imageFile) async {
    final validation = await validateSuratSehat(
      imageFile,
      options: const SuratSehatValidationOptions(
        requireHeader: false,
        minKeywordMatches: 1,
      ),
    );
    return validation.data ?? const SuratSehatModel();
  }

  /// Extracts structured data from raw Surat Keterangan Sehat OCR text.
  static SuratSehatModel extractSuratSehatFromText(String rawText) {
    return SuratSehatExtractorHelper.parseFromText(rawText);
  }
}

/// Primary alias for [KtpExtractor] representing smart multi-document extraction.
typedef SmartIdExtractor = KtpExtractor;

/// Backward-compatible alias for existing implementations.
typedef SmartExtractorPro = KtpExtractor;

/// Alias for [KtpExtractor] representing the unified KTP & Kartu Keluarga extractor.
typedef KtpKkExtractor = KtpExtractor;
