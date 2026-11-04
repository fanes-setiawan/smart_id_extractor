// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../ktp_extractor.dart';
import '../utils/kk_extractor_helper.dart';
import '../utils/surat_sehat_extractor_helper.dart';

/// Comprehensive multi-document camera verification screen matching the Figma designs.
///
/// Supports:
/// - Any [SmartDocumentType]: [SmartDocumentType.ktp], [SmartDocumentType.kartuKeluarga], or [SmartDocumentType.suratSehat].
/// - Unique dynamic OCR validation per document type.
/// - Document-specific viewfinders, watermarks, aspect ratios, subtitles, and guidelines.
/// - Top Stepper header bar (`TAHAPAN BERKAS`) with optional step completion indicators.
/// - Gallery picker button (can be toggled or customized).
/// - Bottom submit button ("Kirim" / "Kirim & Selesaikan Verifikasi"), configurable via [showSubmitButton].
/// - Live camera preview, flash toggle, and camera lens switcher.
class SmartDocumentCameraScreen extends StatefulWidget {
  /// The document type to be scanned and validated.
  final SmartDocumentType documentType;

  /// Custom screen header title. Defaults to [documentType.defaultTitle].
  final String? headerTitle;

  /// Whether to show the top stepper progress header.
  /// Defaults to true (matches Figma design).
  final bool showStepper;

  /// Current step number (1, 2, or 3). If omitted, inferred from [documentType].
  final int? currentStep;

  /// Set of completed steps for the stepper (e.g. `{1}` or `{1, 2}`).
  final Set<int> completedSteps;

  /// Whether to show the gallery picker button. Defaults to true.
  final bool enableGallery;

  /// Whether to show the bottom "Kirim" / submit button. Defaults to true.
  final bool showSubmitButton;

  /// Custom label for the bottom submit button. If omitted, uses [documentType.submitButtonLabel].
  final String? submitButtonLabel;

  /// Callback when user taps the bottom submit button.
  /// If provided, this callback is invoked. If null, the screen automatically returns the [SmartDocumentResult].
  final void Function(SmartDocumentResult result)? onSubmit;

  /// Custom guidelines title.
  final String? guidanceTitle;

  /// Custom guidelines bullet tips.
  final List<String>? guidanceTips;

  /// Custom Kartu Keluarga validation options (used only if [documentType] is [SmartDocumentType.kartuKeluarga]).
  final KartuKeluargaValidationOptions kkOptions;

  /// Custom Surat Sehat validation options (used only if [documentType] is [SmartDocumentType.suratSehat]).
  final SuratSehatValidationOptions suratSehatOptions;

  /// Custom loading / accent color. Defaults to #FD990F (orange).
  final Color accentColor;

  const SmartDocumentCameraScreen({
    super.key,
    required this.documentType,
    this.headerTitle,
    this.showStepper = true,
    this.currentStep,
    this.completedSteps = const {},
    this.enableGallery = true,
    this.showSubmitButton = true,
    this.submitButtonLabel,
    this.onSubmit,
    this.guidanceTitle,
    this.guidanceTips,
    this.kkOptions = const KartuKeluargaValidationOptions(),
    this.suratSehatOptions = const SuratSehatValidationOptions(),
    this.accentColor = const Color(0xFFFD990F),
  });

  @override
  State<SmartDocumentCameraScreen> createState() => _SmartDocumentCameraScreenState();
}

class _SmartDocumentCameraScreenState extends State<SmartDocumentCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;
  FlashMode _flashMode = FlashMode.off;

  bool _isInitializingCamera = false;
  bool _isProcessing = false;
  bool _isDisposed = false;
  String _statusMessage = '';

  File? _capturedImageFile;
  SmartDocumentResult? _latestResult;

  late AnimationController _laserAnimationController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _laserAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _laserAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Kamera tidak ditemukan pada perangkat ini.';
          });
        }
        return;
      }

      int selectedIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (selectedIdx == -1) selectedIdx = 0;
      await _startCameraController(selectedIdx);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Gagal menginisialisasi kamera: $e';
        });
      }
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _startCameraController(int cameraIndex) async {
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      await oldController.dispose();
    }

    _cameraIndex = cameraIndex;
    final description = _cameras[cameraIndex];

    final controller = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      if (_isDisposed) {
        await controller.dispose();
        return;
      }
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _controller = controller;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Gagal memulai kamera: $e';
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final newMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      await _controller!.setFlashMode(newMode);
      if (mounted) {
        setState(() {
          _flashMode = newMode;
        });
      }
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1) return;
    final nextIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCameraController(nextIndex);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraIndex >= 0 && _cameraIndex < _cameras.length) {
        _startCameraController(_cameraIndex);
      } else {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _laserAnimationController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Document Processing & Distinct OCR Validation
  // ---------------------------------------------------------------------------

  Future<void> _captureFromCamera() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Mengambil gambar & memindai berkas...';
      });

      final XFile xFile = await _controller!.takePicture();
      final File imageFile = File(xFile.path);

      if (mounted) {
        setState(() {
          _capturedImageFile = imageFile;
        });
      }

      await _processImage(imageFile);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Gagal mengambil gambar: $e';
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return;

      final File imageFile = File(picked.path);
      if (mounted) {
        setState(() {
          _capturedImageFile = imageFile;
          _isProcessing = true;
          _statusMessage = 'Memproses berkas dari galeri...';
        });
      }

      await _processImage(imageFile);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Gagal memilih berkas dari galeri: $e';
        });
      }
    }
  }

  Future<void> _processImage(File imageFile) async {
    try {
      SmartDocumentResult result;

      switch (widget.documentType) {
        case SmartDocumentType.ktp:
          result = await _processKtp(imageFile);
          break;
        case SmartDocumentType.kartuKeluarga:
          result = await _processKartuKeluarga(imageFile);
          break;
        case SmartDocumentType.suratSehat:
          result = await _processSuratSehat(imageFile);
          break;
      }

      if (!mounted || _isDisposed) return;

      setState(() {
        _isProcessing = false;
        _latestResult = result;
      });

      // If submit button is hidden, immediately return result to caller
      if (!widget.showSubmitButton) {
        _returnResult(result);
      } else if (!result.isValid) {
        // Show validation snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFC02626),
            content: Text(
              result.errorMessage ?? 'Dokumen tidak valid atau kurang terbaca.',
              style: const TextStyle(fontFamily: 'PlusJakartaSans', color: Colors.white),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Gagal memproses dokumen: $e';
        });
      }
    }
  }

  Future<SmartDocumentResult> _processKtp(File imageFile) async {
    // 1. Crop KTP bounding box if found
    final File? croppedFile = await KtpExtractor.cropImageForKtp(imageFile);
    final File finalImage = croppedFile ?? imageFile;

    // 2. Extract KTP Model
    var ktpModel = await KtpExtractor.extractKtp(finalImage);

    // Fallback if crop lost NIK
    if (ktpModel.nik == null && croppedFile != null) {
      final fallback = await KtpExtractor.extractKtp(imageFile);
      if (fallback.nik != null) {
        ktpModel = fallback;
      }
    }

    // 3. Extract Pasfoto
    final File? photoFile = await KtpExtractor.cropKtpPhotoFile(finalImage);

    final bool isValid = ktpModel.nik != null && ktpModel.nik!.length == 16;
    final String? errorMessage = isValid
        ? null
        : (ktpModel.nik == null
            ? 'NIK 16 digit tidak terdeteksi. Pastikan e-KTP berada di dalam bingkai.'
            : 'Format NIK tidak valid (harus 16 digit).');

    return SmartDocumentResult(
      documentType: SmartDocumentType.ktp,
      imageFile: finalImage,
      isValid: isValid,
      rawText: ktpModel.rawText,
      ktpModel: ktpModel,
      ktpPhotoFile: photoFile,
      errorMessage: errorMessage,
    );
  }

  Future<SmartDocumentResult> _processKartuKeluarga(File imageFile) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final String rawText = recognizedText.text;

      final validation = KkExtractorHelper.validateFromText(
        rawText,
        options: widget.kkOptions,
        recognizedText: recognizedText,
      );

      final String? errorMsg = validation.isValid
          ? null
          : (validation.missingRequirements.isNotEmpty
              ? validation.missingRequirements.first
              : 'Format Kartu Keluarga tidak valid atau kurang terbaca.');

      return SmartDocumentResult(
        documentType: SmartDocumentType.kartuKeluarga,
        imageFile: imageFile,
        isValid: validation.isValid,
        rawText: rawText,
        kkModel: validation.data,
        kkValidation: validation,
        errorMessage: errorMsg,
      );
    } finally {
      textRecognizer.close();
    }
  }

  Future<SmartDocumentResult> _processSuratSehat(File imageFile) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final String rawText = recognizedText.text;

      final validation = SuratSehatExtractorHelper.validateFromText(
        rawText,
        options: widget.suratSehatOptions,
        recognizedText: recognizedText,
      );

      final String? errorMsg = validation.isValid
          ? null
          : (validation.missingRequirements.isNotEmpty
              ? validation.missingRequirements.first
              : 'Surat Keterangan Sehat tidak memenuhi kriteria verifikasi.');

      return SmartDocumentResult(
        documentType: SmartDocumentType.suratSehat,
        imageFile: imageFile,
        isValid: validation.isValid,
        rawText: rawText,
        suratSehatModel: validation.data,
        suratSehatValidation: validation,
        errorMessage: errorMsg,
      );
    } finally {
      textRecognizer.close();
    }
  }

  void _returnResult(SmartDocumentResult result) {
    if (widget.onSubmit != null) {
      widget.onSubmit!(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedImageFile = null;
      _latestResult = null;
      _statusMessage = '';
    });
  }

  // ---------------------------------------------------------------------------
  // Build UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF9F9FF),
          body: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Top Header Bar: Back Chevron + Title
                              _buildTopBar(),

                              // 2. Stepper Header ("TAHAPAN BERKAS", 3 Bars, 3 Steps)
                              if (widget.showStepper)
                                SmartDocumentStepperHeader(
                                  activeType: widget.documentType,
                                  currentStep: widget.currentStep,
                                  completedSteps: widget.completedSteps,
                                ),

                              SizedBox(height: 10.h),

                              // 3. Viewfinder Container (Camera Preview + Watermark Overlay)
                              _buildViewfinder(),

                              SizedBox(height: 14.h),

                              // 4. Panduan Pemindaian Card
                              _buildGuidanceCard(),

                              SizedBox(height: 16.h),

                              // 5. Shutter Row & Gallery Button
                              _buildShutterRow(),

                              const Spacer(),

                              // 6. Bottom Submit Button ("Kirim" / "Kirim & Selesaikan Verifikasi")
                              if (widget.showSubmitButton) _buildSubmitButton(),

                              SizedBox(height: 14.h),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 7. Processing Overlay Spinner
              if (_isProcessing)
                Container(
                  color: Colors.black.withOpacity(0.55),
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 22.h),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                            strokeWidth: 3.0,
                          ),
                          SizedBox(height: 14.h),
                          Text(
                            _statusMessage.isNotEmpty ? _statusMessage : 'Memverifikasi dokumen...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              color: const Color(0xFF002245),
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: const Color(0xFF111C2D),
              size: 20.sp,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Text(
              widget.headerTitle ?? widget.documentType.defaultTitle,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                color: const Color(0xFF0B3866),
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    // Determine card dimensions based on document aspect ratio
    final double cardWidth = 354.w;
    final double cardHeight = widget.documentType == SmartDocumentType.suratSehat
        ? (cardWidth / 0.88).clamp(320.0, 360.0).h // Portrait A4 box styled comfortably
        : (cardWidth / widget.documentType.aspectRatio);

    final bool isCameraActive =
        _controller != null && _controller!.value.isInitialized && !_isDisposed;

    return Center(
      child: Container(
        width: cardWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF111C2D),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF002245).withOpacity(0.16),
              blurRadius: 18.r,
              offset: Offset(0, 8.h),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main Camera / Image Frame
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Live Camera or Frozen Picture
                    if (_capturedImageFile != null)
                      Image.file(
                        _capturedImageFile!,
                        fit: BoxFit.cover,
                      )
                    else if (isCameraActive)
                      GestureDetector(
                        onTapDown: (TapDownDetails details) async {
                          final controller = _controller;
                          if (controller == null || !controller.value.isInitialized) return;
                          try {
                            final offset = Offset(
                              (details.localPosition.dx / cardWidth).clamp(0.0, 1.0),
                              (details.localPosition.dy / cardHeight).clamp(0.0, 1.0),
                            );
                            await controller.setFocusPoint(offset);
                            await controller.setFocusMode(FocusMode.auto);
                          } catch (_) {}
                        },
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.previewSize?.height ?? cardWidth,
                            height: _controller!.value.previewSize?.width ?? cardHeight,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      )
                    else
                      Container(
                        color: const Color(0xFF111C2D),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),

                    // 2. Custom Watermark & Corners Painter
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _laserAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            size: Size(cardWidth, cardHeight),
                            painter: SmartDocumentWatermarkPainter(
                              documentType: widget.documentType,
                              laserProgress: _laserAnimation.value,
                              showWatermark: !isCameraActive || _capturedImageFile != null,
                              showLaser: isCameraActive && _capturedImageFile == null,
                              cornerRadius: 20.r,
                            ),
                          );
                        },
                      ),
                    ),

                    // 3. Top-Right Quick Camera Actions (Flash & Lens Switch)
                    if (isCameraActive && _capturedImageFile == null)
                      Positioned(
                        top: 10.h,
                        right: 10.w,
                        child: Row(
                          children: [
                            _buildCameraActionIcon(
                              icon: _flashMode == FlashMode.torch
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              onTap: _toggleFlash,
                            ),
                            SizedBox(width: 8.w),
                            _buildCameraActionIcon(
                              icon: Icons.flip_camera_ios_rounded,
                              onTap: _switchCamera,
                            ),
                          ],
                        ),
                      ),

                    // 4. Retake Button when image is captured
                    if (_capturedImageFile != null)
                      Positioned(
                        top: 10.h,
                        right: 10.w,
                        child: _buildCameraActionIcon(
                          icon: Icons.refresh_rounded,
                          onTap: _retakePhoto,
                          label: 'Ulangi',
                        ),
                      ),
                  ],
                ),
              ),

              // Bottom Viewfinder Subtitle Banner (Matching Figma)
              Container(
                width: cardWidth,
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                color: const Color(0xFF0F1722),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.crop_free_rounded,
                      color: const Color(0xFFFD990F),
                      size: 16.sp,
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        widget.documentType.viewfinderHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraActionIcon({
    required IconData icon,
    required VoidCallback onTap,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(8.r),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.50),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 17.sp),
            if (label != null) ...[
              SizedBox(width: 4.w),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGuidanceCard() {
    final title = widget.guidanceTitle ?? widget.documentType.guidanceTitle;
    final tips = widget.guidanceTips ?? widget.documentType.guidanceTips;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Title Header
            Row(
              children: [
                SvgPicture.asset(
                  'assets/icons/ic_lamp.svg',
                  package: 'smart_id_extractor',
                  width: 18.r,
                  height: 18.r,
                ),
                SizedBox(width: 8.w),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    color: const Color(0xFF002245),
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),

            // Tip Bullet Points
            for (final tip in tips)
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5.r,
                      height: 5.r,
                      margin: EdgeInsets.only(top: 6.h, right: 9.w),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFD990F),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          color: const Color(0xFF43474F),
                          fontSize: 11.5.sp,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterRow() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Shutter Button in Center
            GestureDetector(
              onTap: _captureFromCamera,
              child: Container(
                width: 78.r,
                height: 78.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFD990F).withOpacity(0.18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFD990F).withOpacity(0.24),
                      blurRadius: 16.r,
                      spreadRadius: 2.r,
                      offset: Offset(0, 3.h),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 62.r,
                  height: 62.r,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFD990F),
                  ),
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    'assets/icons/ic_camera.svg',
                    package: 'smart_id_extractor',
                    width: 26.r,
                    height: 26.r,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),

            // Gallery Button (left-aligned relative to row)
            if (widget.enableGallery)
              Positioned(
                left: 36.w,
                child: GestureDetector(
                  onTap: _pickFromGallery,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44.r,
                        height: 44.r,
                        decoration: BoxDecoration(
                          color: const Color(0xFF002245).withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: SvgPicture.asset(
                          'assets/icons/ic_galeri.svg',
                          package: 'smart_id_extractor',
                          width: 20.r,
                          height: 20.r,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF002245),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Galeri',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          color: const Color(0xFF002245),
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        SizedBox(height: 8.h),

        // Shutter Label (e.g. "Ambil Foto KK Asli")
        Text(
          widget.documentType.shutterLabel,
          style: TextStyle(
            fontFamily: 'PlusJakartaSans',
            color: const Color(0xFF002245),
            fontSize: 13.5.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final String label = widget.submitButtonLabel ?? widget.documentType.submitButtonLabel;
    final bool canSubmit = _latestResult != null && _latestResult!.isValid;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: SizedBox(
        height: 50.h,
        child: ElevatedButton(
          onPressed: canSubmit ? () => _returnResult(_latestResult!) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0B3866),
            disabledBackgroundColor: const Color(0xFF0B3866).withOpacity(0.40),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.r),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.documentType == SmartDocumentType.suratSehat) ...[
                Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18.sp),
                SizedBox(width: 8.w),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
