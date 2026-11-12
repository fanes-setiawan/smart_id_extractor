import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/sim_validation.dart';
import 'ext.dart';

/// Helper for validating whether an image / OCR text corresponds to an authentic Indonesian SIM.
class SimExtractorHelper {
  SimExtractorHelper._();

  /// Primary distinctive headers for Indonesian Driver's License
  static const List<String> simHeaderKeywords = [
    'SURAT IZIN MENGEMUDI',
    'SURAT IJIN MENGEMUDI',
    'DRIVING LICENSE',
    'KEPOLISIAN NEGARA REPUBLIK INDONESIA',
    'KEPOLISIAN DAERAH',
    'KORLANTAS',
    'POLRI',
  ];

  /// Core keywords commonly present in Indonesian SIM cards
  static const List<String> simKeywords = [
    'SURAT IZIN MENGEMUDI',
    'DRIVING LICENSE',
    'POLRI',
    'KORLANTAS',
    'KEPOLISIAN',
    'PRIA',
    'WANITA',
    'GOL. DARAH',
    'GOL DARAH',
    'BERLAKU S/D',
    'BERLAKU',
    'ALAMAT',
    'PEKERJAAN',
    'TEMPAT',
    'TGL. LAHIR',
    'TGL LAHIR',
    'SIM',
    'POLDA',
    'KAPOLDA',
    'SATLANTAS',
  ];

  /// SIM class/category patterns (A, B I, B II, C, C1, C2, D, D1)
  static final RegExp _simClassPattern = RegExp(
    r'(?:(?:GOLONGAN|GOL\.?|JENIS|SIM)\s*[:=]?\s*|^|\s)([ABCD])(?:\s*(?:I{1,2}|1|2))?(?:\s|$)',
    caseSensitive: false,
    multiLine: true,
  );

  /// Validates whether [rawText] represents a valid SIM.
  static SimValidationResult validateFromText(
    String rawText, {
    SimValidationOptions options = const SimValidationOptions(),
    RecognizedText? recognizedText,
  }) {
    final String cleanText = rawText.toUpperCase();

    // 1. Header detection
    bool hasHeader = false;
    for (final kw in simHeaderKeywords) {
      if (cleanText.contains(kw)) {
        hasHeader = true;
        break;
      }
    }

    // 2. Keyword matching
    final List<String> matchedKeywords = [];
    for (final kw in simKeywords) {
      if (cleanText.contains(kw) && !matchedKeywords.contains(kw)) {
        matchedKeywords.add(kw);
      }
    }
    for (final kw in options.customKeywords) {
      final upperKw = kw.toUpperCase();
      if (cleanText.contains(upperKw) && !matchedKeywords.contains(upperKw)) {
        matchedKeywords.add(upperKw);
      }
    }

    // 3. Detect SIM Class / Golongan (A, B, C, D)
    String? detectedGolongan;
    bool hasGolongan = false;
    // Check header lines first (often "SURAT IZIN MENGEMUDI A" or "C")
    if (recognizedText != null) {
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text.toUpperCase();
          if (t.contains('SURAT IZIN MENGEMUDI') || t.contains('SIM')) {
            final m = _simClassPattern.firstMatch(t);
            if (m != null) {
              detectedGolongan = m.group(0)?.replaceAll('SIM', '').trim();
              if (detectedGolongan != null && detectedGolongan.isNotEmpty) {
                hasGolongan = true;
                break;
              }
            }
          }
        }
        if (hasGolongan) break;
      }
    }

    if (!hasGolongan) {
      final m = _simClassPattern.firstMatch(cleanText);
      if (m != null) {
        detectedGolongan = m.group(0)?.replaceAll('SIM', '').trim();
        hasGolongan = detectedGolongan != null && detectedGolongan.isNotEmpty;
      }
    }

    // 4. Detect Nomor SIM (typically 12 - 14 digits)
    String? detectedNomorSim;
    bool hasNomorSim = false;
    final RegExp numPattern = RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4,6}\b');
    final numMatch = numPattern.firstMatch(rawText);
    if (numMatch != null) {
      detectedNomorSim = numMatch.group(0)?.replaceAll(RegExp(r'[-\s]'), '');
      hasNomorSim = true;
    } else {
      // Line containing NO. SIM / NO SIM
      if (recognizedText != null) {
        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            final t = line.text.toUpperCase();
            if (t.contains('NO.') || t.contains('NOMOR') || t.contains('NO ')) {
              final digits = line.text.filterNumbersOnly();
              if (digits.length >= 10 && digits.length <= 16) {
                detectedNomorSim = digits;
                hasNomorSim = true;
                break;
              }
            }
          }
          if (hasNomorSim) break;
        }
      }
    }

    // 5. Evaluate against requirements
    final List<String> missingRequirements = [];

    // Negative indicators checked first so failureReason accurately reports wrong document types
    final bool isLikelyKtp = cleanText.contains('KARTU TANDA PENDUDUK') ||
        (cleanText.contains('NIK') && cleanText.contains('PROVINSI') && !cleanText.contains('MENGEMUDI'));
    final bool isLikelyKk = cleanText.contains('KARTU KELUARGA');

    if (isLikelyKtp) {
      missingRequirements.add('Dokumen terdeteksi sebagai Kartu Tanda Penduduk (e-KTP), bukan SIM.');
    }
    if (isLikelyKk) {
      missingRequirements.add('Dokumen terdeteksi sebagai Kartu Keluarga (KK), bukan SIM.');
    }

    if (options.requireHeader && !hasHeader) {
      missingRequirements.add('Foto yang Anda unggah bukan dokumen SIM. Pastikan judul "SURAT IZIN MENGEMUDI" terbaca jelas di dalam bingkai.');
    }

    if (options.requireGolongan && !hasGolongan) {
      missingRequirements.add('Golongan SIM (A/B/C/D) tidak terdeteksi jelas pada kartu SIM.');
    }

    if (options.requireNomorSim && !hasNomorSim) {
      missingRequirements.add('Nomor SIM tidak terdeteksi. Pastikan fisik kartu SIM terbaca tajam tanpa blur.');
    }

    if (matchedKeywords.length < options.minKeywordMatches) {
      missingRequirements.add(
        'Foto yang Anda unggah bukan dokumen SIM yang valid. Pastikan fisik kartu SIM asli dan tidak terkena pantulan cahaya.',
      );
    }

    final bool isValid = missingRequirements.isEmpty;

    // Confidence scoring
    double score = 0.0;
    if (hasHeader) score += 0.40;
    if (hasGolongan) score += 0.20;
    if (hasNomorSim) score += 0.20;
    score += (matchedKeywords.length / 8.0).clamp(0.0, 0.20);
    if (!isValid) score = (score * 0.4).clamp(0.0, 0.49);

    final String? failureReason = isValid ? null : missingRequirements.first;

    return SimValidationResult(
      isValid: isValid,
      confidence: double.parse(score.toStringAsFixed(2)),
      hasHeader: hasHeader,
      hasGolongan: hasGolongan,
      golongan: detectedGolongan,
      hasNomorSim: hasNomorSim,
      nomorSim: detectedNomorSim,
      matchedKeywordsCount: matchedKeywords.length,
      matchedKeywords: matchedKeywords,
      missingRequirements: missingRequirements,
      failureReason: failureReason,
    );
  }
}
