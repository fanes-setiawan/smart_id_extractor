import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/surat_sehat_model.dart';
import '../models/surat_sehat_validation.dart';

/// Comprehensive extractor and validator for Indonesian Medical Certificates
/// (Surat Keterangan Dokter / Surat Keterangan Sehat).
class SuratSehatExtractorHelper {
  SuratSehatExtractorHelper._();

  /// Distinctive keywords commonly found in authentic Indonesian medical certificates.
  static const List<String> medicalKeywords = [
    'SURAT KETERANGAN DOKTER',
    'SURAT KETERANGAN SEHAT',
    'SURAT KETERANGAN KESEHATAN',
    'SURAT KESEHATAN',
    'KETERANGAN SEHAT',
    'HASIL PEMERIKSAAN',
    'PEMERIKSAAN FISIK',
    'DOKTER PEMERIKSA',
    'RUMAH SAKIT',
    'PUSKESMAS',
    'KLINIK',
    'DINAS KESEHATAN',
    'UPTD PUSKESMAS',
    'LABORATORIUM',
    'TENSI',
    'TEKANAN DARAH',
    'BERAT BADAN',
    'TINGGI BADAN',
    'GOLONGAN DARAH',
    'GOL. DARAH',
    'DENYUT NADI',
    'BUTA WARNA',
    'VISUS',
    'KESEHATAN BADAN',
    'SEHAT BADAN',
    'SEHAT JASMANI',
    'SEHAT FISIK',
    'ROHANI',
    'LAYAK',
    'MENYATAKAN BAHWA',
    'BERDASARKAN HASIL',
    'DOKTER',
    'SIP',
    'NIP',
    'TANDA TANGAN',
    'STEMPEL',
    'CAP',
  ];

  /// Validates raw OCR text against Surat Keterangan Sehat criteria.
  static SuratSehatValidationResult validateFromText(
    String rawText, {
    SuratSehatValidationOptions options = const SuratSehatValidationOptions(),
    RecognizedText? recognizedText,
  }) {
    final String upper = rawText.toUpperCase();
    final List<String> missingRequirements = [];

    // 1. Header Validation
    final bool hasHeader = upper.contains('SURAT KETERANGAN') ||
        upper.contains('KETERANGAN SEHAT') ||
        upper.contains('KETERANGAN DOKTER') ||
        upper.contains('KETERANGAN KESEHATAN') ||
        upper.contains('PEMERIKSAAN FISIK') ||
        (upper.contains('SURAT') && upper.contains('SEHAT'));

    if (options.requireHeader && !hasHeader) {
      missingRequirements.add("Header 'Surat Keterangan Sehat/Dokter' tidak ditemukan.");
    }

    // 2. Doctor / Examiner Detection
    final bool hasDokter = upper.contains('DOKTER') ||
        upper.contains('DR.') ||
        upper.contains('PEMERIKSA') ||
        upper.contains('SIP') ||
        upper.contains('NIP');

    if (options.requireDokter && !hasDokter) {
      missingRequirements.add("Informasi dokter pemeriksa / NIP / SIP tidak ditemukan.");
    }

    // 3. Health Facility Detection
    final bool hasFaskes = upper.contains('RUMAH SAKIT') ||
        upper.contains('PUSKESMAS') ||
        upper.contains('KLINIK') ||
        upper.contains('DINAS KESEHATAN') ||
        upper.contains('PRAKTIK DOKTER') ||
        upper.contains('BALAI PENGOBATAN') ||
        upper.contains('LABORATORIUM');

    if (options.requireFaskes && !hasFaskes) {
      missingRequirements.add("Identitas fasilitas kesehatan (RS / Puskesmas / Klinik) tidak ditemukan.");
    }

    // 4. Physical Examination Metrics Detection
    final bool hasPemeriksaanFisik = upper.contains('BERAT BADAN') ||
        upper.contains('TINGGI BADAN') ||
        upper.contains('TENSI') ||
        upper.contains('TEKANAN DARAH') ||
        upper.contains('GOLONGAN DARAH') ||
        upper.contains('GOL. DARAH') ||
        upper.contains('BUTA WARNA') ||
        upper.contains('PEMERIKSAAN FISIK');

    if (options.requirePemeriksaanFisik && !hasPemeriksaanFisik) {
      missingRequirements.add("Rincian pemeriksaan fisik (Tinggi/Berat/Tensi) tidak ditemukan.");
    }

    // 5. Keyword Matching
    final List<String> matchedKeywords = [];
    for (final kw in medicalKeywords) {
      if (upper.contains(kw)) {
        matchedKeywords.add(kw);
      }
    }
    for (final customKw in options.customKeywords) {
      if (upper.contains(customKw.toUpperCase()) &&
          !matchedKeywords.contains(customKw.toUpperCase())) {
        matchedKeywords.add(customKw.toUpperCase());
      }
    }

    if (matchedKeywords.length < options.minKeywordMatches) {
      missingRequirements.add(
        "Kurang kata kunci khas Surat Sehat: ditemukan ${matchedKeywords.length}, minimal ${options.minKeywordMatches}.",
      );
    }

    // 6. Confidence Scoring
    double confidence = 0.0;
    if (hasHeader) confidence += 0.35;
    if (hasDokter) confidence += 0.20;
    if (hasFaskes) confidence += 0.20;
    if (hasPemeriksaanFisik) confidence += 0.15;
    final double kwBonus = (matchedKeywords.length / 10.0).clamp(0.0, 0.10);
    confidence = (confidence + kwBonus).clamp(0.0, 1.0);

    final bool isValid = missingRequirements.isEmpty;

    // 7. Parse Data Model
    final SuratSehatModel model = parseFromText(rawText);

    return SuratSehatValidationResult(
      isValid: isValid,
      hasHeader: hasHeader,
      hasDokter: hasDokter,
      hasFaskes: hasFaskes,
      hasPemeriksaanFisik: hasPemeriksaanFisik,
      matchedKeywords: matchedKeywords,
      matchedKeywordCount: matchedKeywords.length,
      confidence: confidence,
      missingRequirements: missingRequirements,
      data: model,
      rawText: rawText,
    );
  }

  /// Parses fields from the raw OCR text into a structured [SuratSehatModel].
  static SuratSehatModel parseFromText(String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String? nama;
    String? nik;
    String? umur;
    String? jenisKelamin;
    String? pekerjaan;
    String? alamat;
    String? tinggiBadan;
    String? beratBadan;
    String? tekananDarah;
    String? golonganDarah;
    String? denyutNadi;
    String? butaWarna;
    String? kesimpulan;
    String? namaDokter;
    String? nomorSip;
    String? namaFaskes;
    String? kota;
    String? tanggalSurat;

    final nikRegex = RegExp(r'\b[1-9]\d{15}\b');
    final bpRegex = RegExp(r'(\d{2,3}\s*\/\s*\d{2,3})\s*(mm\s*hg)?', caseSensitive: false);
    final tbRegex = RegExp(r'(?:tb|tinggi\s*badan)?\s*[:=]?\s*(\d{2,3})\s*(?:cm)?\b', caseSensitive: false);
    final bbRegex = RegExp(r'(?:bb|berat\s*badan)?\s*[:=]?\s*(\d{2,3}(?:[.,]\d)?)\s*(?:kg)?\b', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // NIK
      if (nik == null) {
        final match = nikRegex.firstMatch(line);
        if (match != null) {
          nik = match.group(0);
        }
      }

      // Faskes (usually at top headers)
      if (namaFaskes == null && i < 6) {
        if (upper.contains('PUSKESMAS') ||
            upper.contains('RUMAH SAKIT') ||
            upper.contains('RSUD') ||
            upper.contains('KLINIK') ||
            upper.contains('DINAS KESEHATAN')) {
          namaFaskes = line;
        }
      }

      // Nama Pasien
      if (nama == null && (upper.startsWith('NAMA') || upper.contains('NAMA :') || upper.contains('NAMA:'))) {
        final val = _extractValueAfterColon(line);
        if (val != null && !val.toUpperCase().contains('DOKTER')) {
          nama = val;
        } else if (i + 1 < lines.length && !lines[i + 1].contains(':')) {
          nama = lines[i + 1];
        }
      }

      // Umur
      if (umur == null && (upper.contains('UMUR') || upper.contains('USIA'))) {
        umur = _extractValueAfterColon(line);
      }

      // Jenis Kelamin
      if (jenisKelamin == null && (upper.contains('JENIS KELAMIN') || upper.contains('KELAMIN') || upper.contains('SEX'))) {
        if (upper.contains('LAKI') || upper.contains('PRIA') || upper.contains('(L)')) {
          jenisKelamin = 'Laki-laki';
        } else if (upper.contains('PEREMPUAN') || upper.contains('WANITA') || upper.contains('(P)')) {
          jenisKelamin = 'Perempuan';
        } else {
          jenisKelamin = _extractValueAfterColon(line);
        }
      }

      // Pekerjaan
      if (pekerjaan == null && upper.contains('PEKERJAAN')) {
        pekerjaan = _extractValueAfterColon(line);
      }

      // Alamat
      if (alamat == null && (upper.startsWith('ALAMAT') || upper.contains('ALAMAT :'))) {
        alamat = _extractValueAfterColon(line);
      }

      // Tekanan Darah / Tensi
      if (tekananDarah == null && (upper.contains('TENSI') || upper.contains('TEKANAN DARAH') || upper.contains('TD'))) {
        final match = bpRegex.firstMatch(line);
        if (match != null) {
          tekananDarah = '${match.group(1)} mmHg';
        } else {
          tekananDarah = _extractValueAfterColon(line);
        }
      }

      // Tinggi Badan
      if (tinggiBadan == null && (upper.contains('TINGGI BADAN') || upper.startsWith('TB'))) {
        final match = tbRegex.firstMatch(line);
        if (match != null && match.group(1) != null) {
          tinggiBadan = '${match.group(1)} cm';
        } else {
          tinggiBadan = _extractValueAfterColon(line);
        }
      }

      // Berat Badan
      if (beratBadan == null && (upper.contains('BERAT BADAN') || upper.startsWith('BB'))) {
        final match = bbRegex.firstMatch(line);
        if (match != null && match.group(1) != null) {
          beratBadan = '${match.group(1)} kg';
        } else {
          beratBadan = _extractValueAfterColon(line);
        }
      }

      // Golongan Darah
      if (golonganDarah == null && (upper.contains('GOLONGAN DARAH') || upper.contains('GOL. DARAH') || upper.contains('GOL DARAH'))) {
        final val = _extractValueAfterColon(line) ?? line;
        final golMatch = RegExp(r'\b(A|B|AB|O)\b', caseSensitive: false).firstMatch(val);
        if (golMatch != null) {
          golonganDarah = golMatch.group(1)?.toUpperCase();
        }
      }

      // Buta Warna
      if (butaWarna == null && upper.contains('BUTA WARNA')) {
        if (upper.contains('TIDAK') || upper.contains('NORMAL') || upper.contains('NEGATIF')) {
          butaWarna = 'Tidak Buta Warna (Normal)';
        } else if (upper.contains('PARSIAL') || upper.contains('TOTAL')) {
          butaWarna = 'Buta Warna';
        } else {
          butaWarna = _extractValueAfterColon(line);
        }
      }

      // Kesimpulan Sehat
      if (kesimpulan == null) {
        if (upper.contains('SEHAT BADAN') ||
            upper.contains('SEHAT JASMANI') ||
            upper.contains('SEHAT UNTUK BEKERJA') ||
            upper.contains('DINYATAKAN SEHAT') ||
            upper.contains('KEADAAN SEHAT')) {
          kesimpulan = 'SEHAT';
        }
      }

      // Dokter
      if (namaDokter == null && (upper.contains('DOKTER PEMERIKSA') || upper.contains('DR. '))) {
        if (upper.contains('DR. ')) {
          namaDokter = line;
        } else if (i + 1 < lines.length) {
          namaDokter = lines[i + 1];
        }
      }

      // SIP / NIP
      if (nomorSip == null && (upper.contains('SIP') || upper.contains('NIP'))) {
        nomorSip = _extractValueAfterColon(line) ?? line;
      }
    }

    return SuratSehatModel(
      nama: nama,
      nik: nik,
      umur: umur,
      jenisKelamin: jenisKelamin,
      pekerjaan: pekerjaan,
      alamat: alamat,
      tinggiBadan: tinggiBadan,
      beratBadan: beratBadan,
      tekananDarah: tekananDarah,
      golonganDarah: golonganDarah,
      denyutNadi: denyutNadi,
      butaWarna: butaWarna,
      kesimpulan: kesimpulan,
      namaDokter: namaDokter,
      nomorSip: nomorSip,
      namaFaskes: namaFaskes,
      kota: kota,
      tanggalSurat: tanggalSurat,
      rawText: rawText,
    );
  }

  static String? _extractValueAfterColon(String line) {
    if (!line.contains(':') && !line.contains('=')) return null;
    final delimiter = line.contains(':') ? ':' : '=';
    final parts = line.split(delimiter);
    if (parts.length > 1) {
      final res = parts.sublist(1).join(delimiter).trim();
      return res.isEmpty ? null : res;
    }
    return null;
  }
}
