import 'dart:io';
import 'package:equatable/equatable.dart';
import 'ktp_model.dart';

/// Result object returned by [KtpCameraScreen].
class KtpCameraResult extends Equatable {
  /// The extracted KTP data model.
  final KtpModel model;

  /// The captured (and cropped if detected) image file.
  final File imageFile;

  /// The cropped face/profile photo from the KTP card.
  final File? photoFile;

  const KtpCameraResult({
    required this.model,
    required this.imageFile,
    this.photoFile,
  });

  @override
  List<Object?> get props => [model, imageFile.path, photoFile?.path];
}
