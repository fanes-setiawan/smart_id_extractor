import 'dart:io';
import 'package:equatable/equatable.dart';

import 'kartu_keluarga_model.dart';
import 'kartu_keluarga_validation.dart';
import 'ktp_model.dart';
import 'surat_sehat_model.dart';
import 'surat_sehat_validation.dart';

/// Enum specifying which Indonesian document type to capture and validate.
enum SmartDocumentType {
  /// Kartu Tanda Penduduk (e-KTP)
  ktp,

  /// Kartu Keluarga (KK)
  kartuKeluarga,

  /// Surat Keterangan Dokter / Sehat
  suratSehat,
}

/// Helper extension on [SmartDocumentType] providing default titles, badges, and labels.
extension SmartDocumentTypeX on SmartDocumentType {
  /// Default screen header title (e.g. 'Upload Berkas KTP').
  String get defaultTitle {
    switch (this) {
      case SmartDocumentType.ktp:
        return 'Upload Berkas KTP';
      case SmartDocumentType.kartuKeluarga:
        return 'Upload Berkas (KK)';
      case SmartDocumentType.suratSehat:
        return 'Upload Surat Keterangan Sehat';
    }
  }

  /// Badge chip label displayed at the top right of the screen.
  String get badgeLabel {
    switch (this) {
      case SmartDocumentType.ktp:
        return 'Kartu Tanda Penduduk';
      case SmartDocumentType.kartuKeluarga:
        return 'Kartu Keluarga';
      case SmartDocumentType.suratSehat:
        return 'Surat Keterangan Sehat';
    }
  }

  /// Viewfinder instruction subtitle banner (at the bottom of the camera box).
  String get viewfinderHint {
    switch (this) {
      case SmartDocumentType.ktp:
        return 'Tepatkan seluruh kartu KTP di dalam bingkai';
      case SmartDocumentType.kartuKeluarga:
        return 'Tepatkan seluruh lembar Kartu Keluarga di dalam bingkai';
      case SmartDocumentType.suratSehat:
        return 'Tepatkan seluruh lembar Surat Sehat & cap basah di dalam bingkai';
    }
  }

  /// Shutter action button label below the camera button.
  String get shutterLabel {
    switch (this) {
      case SmartDocumentType.ktp:
        return 'Ambil Foto e-KTP';
      case SmartDocumentType.kartuKeluarga:
        return 'Ambil Foto KK Asli';
      case SmartDocumentType.suratSehat:
        return 'Ambil Foto Surat Sehat Asli';
    }
  }

  /// Default title for the guidelines card.
  String get guidanceTitle {
    switch (this) {
      case SmartDocumentType.ktp:
        return 'Panduan Pemindaian Cepat & Presisi';
      case SmartDocumentType.kartuKeluarga:
        return 'Panduan Pemindaian Lembar KK';
      case SmartDocumentType.suratSehat:
        return 'Panduan Pemindaian Surat Sehat';
    }
  }

  /// Default bullet tips for the guidelines card.
  List<String> get guidanceTips {
    switch (this) {
      case SmartDocumentType.ktp:
        return const [
          'Hindari pantulan cahaya langsung atau kilau flash pada permukaan e-KTP',
          'Letakkan kartu di atas permukaan datar berlatar belakang kontras/gelap',
        ];
      case SmartDocumentType.kartuKeluarga:
        return const [
          'Pastikan seluruh lembar fisik KK asli (bukan fotokopi) berada dalam bingkai foto.',
          'Nomor Kartu Keluarga (16 digit) dan nama seluruh anggota keluarga terbaca jelas tanpa blur.',
          'Gunakan pencahayaan yang cukup dan hindari bayangan tangan saat memotret dokumen.',
        ];
      case SmartDocumentType.suratSehat:
        return const [
          'Pastikan lembar fisik Surat Sehat asli (diterbitkan maksimal 1–3 bulan terakhir oleh Puskesmas/Klinik/RS).',
          'Tanda tangan dokter pemeriksa dan stempel basah instansi kesehatan terlihat jelas tanpa terpotong.',
          'Hindari pantulan cahaya silau dan pastikan kondisi fisik prima dinyatakan secara terbaca.',
        ];
    }
  }

  /// Aspect ratio (width / height) optimal for the viewfinder.
  double get aspectRatio {
    switch (this) {
      case SmartDocumentType.ktp:
        return 1.5858; // ID-1 standard landscape (85.6mm x 53.98mm)
      case SmartDocumentType.kartuKeluarga:
        return 1.4142; // Standard A4 landscape (~340w / 240h)
      case SmartDocumentType.suratSehat:
        return 0.7071; // Standard A4 portrait (210mm x 297mm)
    }
  }

  /// Default submit button label.
  String get submitButtonLabel {
    switch (this) {
      case SmartDocumentType.ktp:
      case SmartDocumentType.kartuKeluarga:
        return 'Kirim';
      case SmartDocumentType.suratSehat:
        return 'Kirim & Selesaikan Verifikasi';
    }
  }
}

/// Unified result object returned when a document is captured/picked and validated.
class SmartDocumentResult extends Equatable {
  /// The document type.
  final SmartDocumentType documentType;

  /// The captured or selected image file.
  final File imageFile;

  /// Whether the document passed validation.
  final bool isValid;

  /// Raw OCR text detected from the document.
  final String? rawText;

  /// Extracted KTP model (only present if [documentType] == [SmartDocumentType.ktp]).
  final KtpModel? ktpModel;

  /// Cropped pasfoto file (only present if [documentType] == [SmartDocumentType.ktp]).
  final File? ktpPhotoFile;

  /// Extracted KK model (only present if [documentType] == [SmartDocumentType.kartuKeluarga]).
  final KartuKeluargaModel? kkModel;

  /// Detailed KK validation result (only present if [documentType] == [SmartDocumentType.kartuKeluarga]).
  final KartuKeluargaValidationResult? kkValidation;

  /// Extracted Surat Sehat model (only present if [documentType] == [SmartDocumentType.suratSehat]).
  final SuratSehatModel? suratSehatModel;

  /// Detailed Surat Sehat validation result (only present if [documentType] == [SmartDocumentType.suratSehat]).
  final SuratSehatValidationResult? suratSehatValidation;

  /// Error or validation failure message, if any.
  final String? errorMessage;

  const SmartDocumentResult({
    required this.documentType,
    required this.imageFile,
    required this.isValid,
    this.rawText,
    this.ktpModel,
    this.ktpPhotoFile,
    this.kkModel,
    this.kkValidation,
    this.suratSehatModel,
    this.suratSehatValidation,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [
        documentType,
        imageFile.path,
        isValid,
        rawText,
        ktpModel,
        ktpPhotoFile?.path,
        kkModel,
        kkValidation,
        suratSehatModel,
        suratSehatValidation,
        errorMessage,
      ];
}
