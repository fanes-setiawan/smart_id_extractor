import 'package:equatable/equatable.dart';
import 'surat_sehat_model.dart';

/// Configuration options for validating whether a document is an authentic Surat Sehat / Medical Certificate.
class SuratSehatValidationOptions extends Equatable {
  /// Whether a recognized doctor or medical header is required.
  /// (e.g. SURAT KETERANGAN DOKTER / SURAT KETERANGAN SEHAT).
  /// Defaults to true.
  final bool requireHeader;

  /// Whether doctor keywords (DOKTER, DOKTER PEMERIKSA, DR., NIP, SIP) are required.
  /// Defaults to false.
  final bool requireDokter;

  /// Whether health facility keywords (RUMAH SAKIT, KLINIK, PUSKESMAS, DINAS KESEHATAN, APOTEK, LABORATORIUM) are required.
  /// Defaults to false.
  final bool requireFaskes;

  /// Whether physical examination metrics (BERAT BADAN, TINGGI BADAN, TENSI, TEKANAN DARAH, GOLONGAN DARAH, NADI) are required.
  /// Defaults to false.
  final bool requirePemeriksaanFisik;

  /// Minimum number of distinctive medical/certificate keywords that must match.
  /// Defaults to 2.
  final int minKeywordMatches;

  /// Additional custom keywords specified by the library user.
  final List<String> customKeywords;

  const SuratSehatValidationOptions({
    this.requireHeader = true,
    this.requireDokter = false,
    this.requireFaskes = false,
    this.requirePemeriksaanFisik = false,
    this.minKeywordMatches = 2,
    this.customKeywords = const [],
  });

  @override
  List<Object?> get props => [
        requireHeader,
        requireDokter,
        requireFaskes,
        requirePemeriksaanFisik,
        minKeywordMatches,
        customKeywords,
      ];
}

/// The result of validating a document against Surat Keterangan Sehat criteria.
class SuratSehatValidationResult extends Equatable {
  /// Whether the document satisfies all mandatory Surat Sehat requirements.
  final bool isValid;

  /// Whether a recognized header title was found.
  final bool hasHeader;

  /// Whether doctor information or signature line was detected.
  final bool hasDokter;

  /// Whether a health facility (RS/Klinik/Puskesmas) was detected.
  final bool hasFaskes;

  /// Whether physical examination metrics were detected.
  final bool hasPemeriksaanFisik;

  /// Distinctive medical certificate keywords detected in the document.
  final List<String> matchedKeywords;

  /// Total count of distinctive keywords matched.
  final int matchedKeywordCount;

  /// Estimated confidence score (0.0 to 1.0).
  final double confidence;

  /// Explanatory list of requirements that failed when [isValid] is false.
  final List<String> missingRequirements;

  /// Parsed model, if any.
  final SuratSehatModel? data;

  /// Alias for [data].
  SuratSehatModel? get model => data;

  /// Full raw OCR text processed from the document.
  final String? rawText;

  const SuratSehatValidationResult({
    required this.isValid,
    required this.hasHeader,
    required this.hasDokter,
    required this.hasFaskes,
    required this.hasPemeriksaanFisik,
    required this.matchedKeywords,
    required this.matchedKeywordCount,
    required this.confidence,
    required this.missingRequirements,
    this.data,
    this.rawText,
  });

  @override
  List<Object?> get props => [
        isValid,
        hasHeader,
        hasDokter,
        hasFaskes,
        hasPemeriksaanFisik,
        matchedKeywords,
        matchedKeywordCount,
        confidence,
        missingRequirements,
        data,
        rawText,
      ];

  @override
  String toString() {
    return 'SuratSehatValidationResult(isValid: $isValid, confidence: ${(confidence * 100).toStringAsFixed(1)}%, keywords: $matchedKeywordCount)';
  }
}

