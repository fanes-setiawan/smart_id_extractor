import 'package:equatable/equatable.dart';
import 'kartu_keluarga_model.dart';

/// Configuration options for validating whether a document is an authentic Kartu Keluarga.
class KartuKeluargaValidationOptions extends Equatable {
  /// Whether a valid 16-digit Nomor KK is mandatory.
  /// Defaults to true.
  final bool requireNomorKk;

  /// Whether the "KARTU KELUARGA" header title is mandatory.
  /// Defaults to true.
  final bool requireHeader;

  /// Minimum number of distinctive KK keywords that must be matched in the document.
  /// Defaults to 3.
  final int minKeywordMatches;

  /// Whether "KEPALA KELUARGA" or "NAMA KEPALA KELUARGA" is mandatory.
  /// Defaults to false.
  final bool requireKepalaKeluarga;

  /// Whether address section keywords (ALAMAT, RT/RW, DESA/KELURAHAN, KECAMATAN) are mandatory.
  /// Defaults to false.
  final bool requireAddress;

  /// Additional custom keywords specified by the library user to be validated.
  final List<String> customKeywords;

  const KartuKeluargaValidationOptions({
    this.requireNomorKk = true,
    this.requireHeader = true,
    this.minKeywordMatches = 3,
    this.requireKepalaKeluarga = false,
    this.requireAddress = false,
    this.customKeywords = const [],
  });

  @override
  List<Object?> get props => [
        requireNomorKk,
        requireHeader,
        minKeywordMatches,
        requireKepalaKeluarga,
        requireAddress,
        customKeywords,
      ];
}

/// The result of validating a document against Kartu Keluarga criteria.
class KartuKeluargaValidationResult extends Equatable {
  /// Whether the document satisfies all mandatory Kartu Keluarga requirements.
  final bool isValid;

  /// The extracted 16-digit Nomor KK, or null if not detected.
  final String? nomorKk;

  /// Whether the "KARTU KELUARGA" header was detected in the document.
  final bool hasHeader;

  /// Whether a valid 16-digit Nomor KK was successfully found.
  final bool hasNomorKk;

  /// Whether "KEPALA KELUARGA" or "NAMA KEPALA KELUARGA" was detected.
  final bool hasKepalaKeluarga;

  /// Whether address section keywords were detected.
  final bool hasAddress;

  /// List of specific distinctive Kartu Keluarga keywords detected in the document.
  final List<String> matchedKeywords;

  /// Total count of distinctive keywords matched.
  final int matchedKeywordCount;

  /// Estimated confidence score (0.0 to 1.0) that the document is a Kartu Keluarga.
  final double confidence;

  /// Explanatory list of requirements that failed when [isValid] is false.
  final List<String> missingRequirements;

  /// Optional extracted data model populated from the Kartu Keluarga.
  final KartuKeluargaModel? data;

  /// Alias for [data] matching [KtpModel] and [PassportModel] conventions.
  KartuKeluargaModel? get model => data;

  /// Full raw OCR text processed from the document.
  final String? rawText;

  const KartuKeluargaValidationResult({
    required this.isValid,
    this.nomorKk,
    required this.hasHeader,
    required this.hasNomorKk,
    required this.hasKepalaKeluarga,
    required this.hasAddress,
    required this.matchedKeywords,
    required this.matchedKeywordCount,
    required this.confidence,
    required this.missingRequirements,
    this.data,
    this.rawText,
  });

  Map<String, dynamic> toMap() {
    return {
      'isValid': isValid,
      'nomorKk': nomorKk,
      'hasHeader': hasHeader,
      'hasNomorKk': hasNomorKk,
      'hasKepalaKeluarga': hasKepalaKeluarga,
      'hasAddress': hasAddress,
      'matchedKeywords': matchedKeywords,
      'matchedKeywordCount': matchedKeywordCount,
      'confidence': confidence,
      'missingRequirements': missingRequirements,
      'data': data?.toMap(),
    };
  }

  @override
  List<Object?> get props => [
        isValid,
        nomorKk,
        hasHeader,
        hasNomorKk,
        hasKepalaKeluarga,
        hasAddress,
        matchedKeywords,
        matchedKeywordCount,
        confidence,
        missingRequirements,
        data,
        rawText,
      ];

  @override
  String toString() {
    return 'KartuKeluargaValidationResult('
        'isValid: $isValid, '
        'nomorKk: $nomorKk, '
        'confidence: ${(confidence * 100).toStringAsFixed(1)}%, '
        'matchedKeywords: ${matchedKeywords.length}, '
        'missing: $missingRequirements'
        ')';
  }
}
