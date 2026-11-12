import 'package:equatable/equatable.dart';

/// Configuration options for validating whether a document is an authentic Surat Izin Mengemudi (SIM).
class SimValidationOptions extends Equatable {
  /// Whether the header title "SURAT IZIN MENGEMUDI" or "DRIVING LICENSE" is mandatory.
  /// Defaults to true.
  final bool requireHeader;

  /// Whether the SIM category / class (A, B I, B II, C, C1, C2, D) is mandatory.
  /// Defaults to false.
  final bool requireGolongan;

  /// Whether the SIM Number (No. SIM) is mandatory.
  /// Defaults to false.
  final bool requireNomorSim;

  /// Minimum number of distinctive SIM keywords that must match in the document.
  /// Defaults to 2.
  final int minKeywordMatches;

  /// Additional custom keywords specified by the library user.
  final List<String> customKeywords;

  const SimValidationOptions({
    this.requireHeader = true,
    this.requireGolongan = false,
    this.requireNomorSim = false,
    this.minKeywordMatches = 2,
    this.customKeywords = const [],
  });

  @override
  List<Object?> get props => [
        requireHeader,
        requireGolongan,
        requireNomorSim,
        minKeywordMatches,
        customKeywords,
      ];
}

/// The result of validating a document against SIM criteria.
class SimValidationResult extends Equatable {
  /// Whether the document satisfies all SIM criteria ("Foto ini adalah SIM").
  final bool isValid;

  /// Confidence score between 0.0 and 1.0.
  final double confidence;

  /// Whether the header title was found.
  final bool hasHeader;

  /// Whether a valid SIM category / class was detected.
  final bool hasGolongan;

  /// Detected SIM category (e.g. "A", "C", "B I"), if found.
  final String? golongan;

  /// Whether a valid SIM Number was detected.
  final bool hasNomorSim;

  /// Detected SIM Number, if found.
  final String? nomorSim;

  /// Number of matched SIM keywords.
  final int matchedKeywordsCount;

  /// List of matched keywords found in the document.
  final List<String> matchedKeywords;

  /// Requirements that failed validation, if any.
  final List<String> missingRequirements;

  /// Overall failure reason if [isValid] is false.
  final String? failureReason;

  const SimValidationResult({
    required this.isValid,
    required this.confidence,
    required this.hasHeader,
    required this.hasGolongan,
    this.golongan,
    required this.hasNomorSim,
    this.nomorSim,
    required this.matchedKeywordsCount,
    required this.matchedKeywords,
    required this.missingRequirements,
    this.failureReason,
  });

  @override
  List<Object?> get props => [
        isValid,
        confidence,
        hasHeader,
        hasGolongan,
        golongan,
        hasNomorSim,
        nomorSim,
        matchedKeywordsCount,
        matchedKeywords,
        missingRequirements,
        failureReason,
      ];
}

