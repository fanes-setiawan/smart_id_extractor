import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/kartu_keluarga_model.dart';
import '../models/kartu_keluarga_validation.dart';
import 'ext.dart';

/// Helper utility for validating and extracting data from Indonesian Kartu Keluarga (KK).
class KkExtractorHelper {
  /// Standard keywords that characterize an authentic Indonesian Kartu Keluarga.
  static const List<String> standardKkKeywords = [
    'KARTU KELUARGA',
    'KEPALA KELUARGA',
    'HUBUNGAN DALAM KELUARGA',
    'STATUS HUBUNGAN',
    'ANGGOTA KELUARGA',
    'ALAMAT',
    'RT/RW',
    'DESA',
    'KELURAHAN',
    'KECAMATAN',
    'KABUPATEN',
    'KOTA',
    'PROVINSI',
    'KODE POS',
    'PENDIDIKAN',
    'JENIS PEKERJAAN',
    'STATUS PERKAWINAN',
    'STATUS PERNIKAHAN',
    'NAMA LENGKAP',
    'TEMPAT LAHIR',
    'TANGGAL LAHIR',
    'AGAMA',
    'KEWARGANEGARAAN',
    'NAMA ORANG TUA',
    'DOKUMEN IMIGRASI',
    'REPUBLIK INDONESIA',
  ];

  /// Valid Indonesian Province prefixes (11 to 96).
  static final Set<int> _validProvincePrefixes = {
    11, 12, 13, 14, 15, 16, 17, 18, 19, // Sumatra
    21, // Kepri
    31, 32, 33, 34, 35, 36, // Jawa
    51, 52, 53, // Bali & Nusa Tenggara
    61, 62, 63, 64, 65, // Kalimantan
    71, 72, 73, 74, 75, 76, // Sulawesi
    81, 82, // Maluku
    91, 92, 93, 94, 95, 96, // Papua
  };

  /// Validates raw OCR text against Kartu Keluarga criteria.
  static KartuKeluargaValidationResult validateFromText(
    String rawText, {
    KartuKeluargaValidationOptions options =
        const KartuKeluargaValidationOptions(),
    RecognizedText? recognizedText,
  }) {
    final String upper = rawText.toUpperCase();
    final List<String> missingRequirements = [];

    // 1. Header Validation
    final bool hasHeader = upper.contains('KARTU KELUARGA') ||
        (upper.contains('KELUARGA') && upper.contains('REPUBLIK INDONESIA'));

    if (options.requireHeader && !hasHeader) {
      missingRequirements.add("Header 'KARTU KELUARGA' tidak ditemukan.");
    }

    // 2. Nomor KK Detection
    final String? nomorKk = _findNomorKk(rawText, recognizedText);
    final bool hasNomorKk = nomorKk != null && nomorKk.length == 16;

    if (options.requireNomorKk && !hasNomorKk) {
      missingRequirements.add(
          "Nomor Kartu Keluarga (16 digit) wajib ada tetapi tidak ditemukan.");
    }

    // 3. Kepala Keluarga Detection
    final bool hasKepalaKeluarga = upper.contains('KEPALA KELUARGA') ||
        upper.contains('NAMA KEPALA') ||
        upper.contains('KEP. KELUARGA');

    if (options.requireKepalaKeluarga && !hasKepalaKeluarga) {
      missingRequirements
          .add("Bagian 'Nama Kepala Keluarga' tidak ditemukan.");
    }

    // 4. Address Section Detection
    int addressKeywordMatches = 0;
    const List<String> addressKeywords = [
      'ALAMAT',
      'RT/RW',
      'DESA',
      'KELURAHAN',
      'KECAMATAN',
      'KABUPATEN',
      'KOTA',
      'KODE POS',
      'PROVINSI',
    ];
    for (final kw in addressKeywords) {
      if (upper.contains(kw)) addressKeywordMatches++;
    }
    final bool hasAddress = addressKeywordMatches >= 2;

    if (options.requireAddress && !hasAddress) {
      missingRequirements
          .add("Informasi Alamat / Wilayah Kartu Keluarga tidak lengkap.");
    }

    // 5. Keyword Matches
    final List<String> matchedKeywords = [];
    for (final kw in standardKkKeywords) {
      if (upper.contains(kw)) {
        matchedKeywords.add(kw);
      }
    }

    for (final customKw in options.customKeywords) {
      final customUpper = customKw.toUpperCase().trim();
      if (customUpper.isNotEmpty && upper.contains(customUpper)) {
        if (!matchedKeywords.contains(customUpper)) {
          matchedKeywords.add(customUpper);
        }
      }
    }

    if (matchedKeywords.length < options.minKeywordMatches) {
      missingRequirements.add(
        'Kata kunci Kartu Keluarga tidak mencukupi (ditemukan ${matchedKeywords.length}, minimal ${options.minKeywordMatches}).',
      );
    }

    // 6. Custom Keywords Mandatory Check
    for (final customKw in options.customKeywords) {
      final customUpper = customKw.toUpperCase().trim();
      if (customUpper.isNotEmpty && !upper.contains(customUpper)) {
        missingRequirements.add("Kata kunci wajib '$customKw' tidak ditemukan.");
      }
    }

    // 7. Calculate Confidence Score
    double confidence = 0.0;
    if (hasHeader) confidence += 0.30;
    if (hasNomorKk) confidence += 0.30;
    if (hasKepalaKeluarga) confidence += 0.15;
    if (hasAddress) confidence += 0.15;
    final double keywordDensity =
        (matchedKeywords.length / standardKkKeywords.length).clamp(0.0, 1.0);
    confidence += (keywordDensity * 0.10);
    confidence = confidence.clamp(0.0, 1.0);

    final bool isValid = missingRequirements.isEmpty;

    // 8. Extract Model Data
    final KartuKeluargaModel data = _extractModel(rawText, recognizedText, nomorKk);

    return KartuKeluargaValidationResult(
      isValid: isValid,
      nomorKk: nomorKk,
      hasHeader: hasHeader,
      hasNomorKk: hasNomorKk,
      hasKepalaKeluarga: hasKepalaKeluarga,
      hasAddress: hasAddress,
      matchedKeywords: matchedKeywords,
      matchedKeywordCount: matchedKeywords.length,
      confidence: confidence,
      missingRequirements: missingRequirements,
      data: data,
      rawText: rawText,
    );
  }

  /// Identifies the 16-digit Nomor KK from the recognized text or raw string.
  static String? _findNomorKk(String rawText, RecognizedText? recognizedText) {
    // 1. Try finding by structure in RecognizedText if available
    if (recognizedText != null) {
      // Search lines near "No." or "No. KK" or "KARTU KELUARGA"
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final upper = line.text.toUpperCase();
          if (upper.contains('NO') ||
              upper.contains('NOMOR') ||
              upper.contains('KK')) {
            final digits = line.text.filterNumbersOnly();
            if (digits.length >= 16) {
              final candidate = digits.substring(0, 16);
              if (_isValidKkPrefix(candidate)) {
                return candidate;
              }
            }
          }
        }
      }

      // If not labeled on the same line, check line right below "KARTU KELUARGA"
      for (final block in recognizedText.blocks) {
        for (int i = 0; i < block.lines.length; i++) {
          final upper = block.lines[i].text.toUpperCase();
          if (upper.contains('KARTU KELUARGA')) {
            // Check next lines within the block
            for (int j = i + 1; j < block.lines.length && j <= i + 3; j++) {
              final digits = block.lines[j].text.filterNumbersOnly();
              if (digits.length >= 16) {
                final candidate = digits.substring(0, 16);
                if (_isValidKkPrefix(candidate)) {
                  return candidate;
                }
              }
            }
          }
        }
      }
    }

    // 2. Regex search in full raw text
    final lines = rawText.split('\n');
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('NO') ||
          upper.contains('KK') ||
          upper.contains('NOMOR')) {
        final digits = line.filterNumbersOnly();
        if (digits.length >= 16) {
          final candidate = digits.substring(0, 16);
          if (_isValidKkPrefix(candidate)) {
            return candidate;
          }
        }
      }
    }

    // 3. Fallback: Find any 16-digit sequence with valid province prefix
    final reg16 = RegExp(r'\b\d{16}\b');
    final matches = reg16.allMatches(rawText);
    for (final match in matches) {
      final candidate = match.group(0)!;
      if (_isValidKkPrefix(candidate)) {
        return candidate;
      }
    }

    // 4. Fallback: Clean line by line
    for (final line in lines) {
      final digits = line.filterNumbersOnly();
      if (digits.length == 16 && _isValidKkPrefix(digits)) {
        return digits;
      }
    }

    return null;
  }

  /// Verifies whether the first two digits represent a valid Indonesian province.
  static bool _isValidKkPrefix(String digits) {
    if (digits.length < 2) return false;
    final prefix = int.tryParse(digits.substring(0, 2));
    if (prefix == null) return false;
    return _validProvincePrefixes.contains(prefix);
  }

  /// Extracts structured Kartu Keluarga fields from raw text and recognized blocks.
  static KartuKeluargaModel _extractModel(
    String rawText,
    RecognizedText? recognizedText,
    String? detectedNomorKk,
  ) {
    String? namaKepalaKeluarga;
    String? alamat;
    String? rt;
    String? rw;
    String? kodePos;
    String? desaKelurahan;
    String? kecamatan;
    String? kabupatenKota;
    String? provinsi;
    final List<KartuKeluargaAnggotaModel> anggotaList = [];

    final lines = rawText.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // Nama Kepala Keluarga
      if (namaKepalaKeluarga == null &&
          (upper.contains('KEPALA KELUARGA') || upper.contains('NAMA KEPALA'))) {
        namaKepalaKeluarga = _cleanValue(line, ['NAMA KEPALA KELUARGA', 'KEPALA KELUARGA', 'NAMA KEPALA']);
        if ((namaKepalaKeluarga == null || namaKepalaKeluarga.isEmpty) && i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          if (!_isKeywordLine(next)) {
            namaKepalaKeluarga = _cleanValue(next, []);
          }
        }
      }

      // Alamat
      if (alamat == null && upper.contains('ALAMAT') && !upper.contains('EMAIL')) {
        alamat = _cleanValue(line, ['ALAMAT']);
      }

      // RT / RW
      if ((rt == null || rw == null) && (upper.contains('RT/RW') || upper.contains('RT / RW') || upper.contains('RT'))) {
        final match = RegExp(r'(\d{1,3})\s*[/]\s*(\d{1,3})').firstMatch(line);
        if (match != null) {
          rt = match.group(1);
          rw = match.group(2);
        }
      }

      // Desa / Kelurahan
      if (desaKelurahan == null && (upper.contains('DESA') || upper.contains('KELURAHAN'))) {
        desaKelurahan = _cleanValue(line, ['DESA/KELURAHAN', 'KELURAHAN/DESA', 'DESA', 'KELURAHAN']);
      }

      // Kecamatan
      if (kecamatan == null && upper.contains('KECAMATAN')) {
        kecamatan = _cleanValue(line, ['KECAMATAN', 'KEC.']);
      }

      // Kabupaten / Kota
      if (kabupatenKota == null && (upper.contains('KABUPATEN') || upper.contains('KOTA'))) {
        kabupatenKota = _cleanValue(line, ['KABUPATEN/KOTA', 'KABUPATEN', 'KOTA', 'KAB.']);
      }

      // Provinsi
      if (provinsi == null && upper.contains('PROVINSI')) {
        provinsi = _cleanValue(line, ['PROVINSI', 'PROP.']);
      }

      // Kode Pos
      if (kodePos == null && upper.contains('KODE POS')) {
        final match = RegExp(r'\b\d{5}\b').firstMatch(line);
        if (match != null) {
          kodePos = match.group(0);
        }
      }
    }

    // Extract table rows for family members (look for 16-digit NIKs that are not the Nomor KK)
    final Set<String> foundNiks = {};
    final reg16 = RegExp(r'\d{16}');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final matches = reg16.allMatches(line);

      for (final match in matches) {
        final nik = match.group(0)!;

        if (nik != detectedNomorKk && _isValidKkPrefix(nik)) {
          if (!foundNiks.contains(nik)) {
            foundNiks.add(nik);

            // Find candidate member name from the current line or adjacent line
            String? memberName;
            // Remove the NIK from the line to parse the name
            final withoutNik = line.replaceAll(nik, '');
            final words = withoutNik
                .replaceAll(RegExp(r'^\s*\d+[\s.]*'), '') // remove row number
                .replaceAll(RegExp(r'LAKI-LAKI|PEREMPUAN|ISLAM|KRISTEN|KATOLIK|HINDU|BUDDHA', caseSensitive: false), '')
                .replaceAll(RegExp(r'[:=/\-]'), ' ')
                .trim();

            if (words.length >= 3 && !_isKeywordLine(words)) {
              memberName = words.replaceAll(RegExp(r'\s+'), ' ');
            } else if (i > 0) {
              final prevWords = lines[i - 1].replaceAll(RegExp(r'\d'), '').replaceAll(RegExp(r'[:=/\-]'), '').trim();
              if (prevWords.length >= 3 && !_isKeywordLine(prevWords)) {
                memberName = prevWords;
              }
            }

            // Extract relationship status if present in context
            String? relationship;
            const relationships = [
              'KEPALA KELUARGA',
              'SUAMI',
              'ISTERI',
              'ISTRI',
              'ANAK',
              'MENANTU',
              'CUCU',
              'ORANGTUA',
              'MERTUA',
              'FAMILI LAIN',
              'PEMBANTU',
              'LAINNYA',
            ];
            for (final rel in relationships) {
              if (rawText.toUpperCase().contains(rel)) {
                relationship = rel;
                break;
              }
            }

            anggotaList.add(KartuKeluargaAnggotaModel(
              nik: nik,
              nama: memberName,
              statusHubungan: relationship,
            ));
          }
        }
      }
    }

    return KartuKeluargaModel(
      nomorKk: detectedNomorKk,
      namaKepalaKeluarga: namaKepalaKeluarga,
      alamat: alamat,
      rt: rt,
      rw: rw,
      kodePos: kodePos,
      desaKelurahan: desaKelurahan,
      kecamatan: kecamatan,
      kabupatenKota: kabupatenKota,
      provinsi: provinsi,
      anggotaKeluarga: anggotaList,
      rawText: rawText,
    );
  }

  static String? _cleanValue(String line, List<String> labels) {
    String cleaned = line;
    for (final label in labels) {
      cleaned = cleaned.replaceAll(RegExp(RegExp.escape(label), caseSensitive: false), '');
    }
    cleaned = cleaned.replaceAll(RegExp(r'^[:\-=.\s]+'), '').replaceAll(RegExp(r'[:\-=.\s]+$'), '').trim();
    return cleaned.isNotEmpty ? cleaned : null;
  }

  static bool _isKeywordLine(String text) {
    final upper = text.toUpperCase();
    for (final kw in standardKkKeywords) {
      if (upper == kw || upper == '$kw:' || upper == '$kw :') return true;
    }
    return false;
  }
}
