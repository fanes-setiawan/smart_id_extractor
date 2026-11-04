// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../ktp_extractor.dart';
import '../utils/utils.dart';

/// A full-screen live camera view with smart KTP card frame overlay,
/// real-time flexible quadrilateral tracking (Normal, Tilt, 3D Perspective Trapezoid, and Free Rotation),
/// and auto-capture with autofocus settling and stabilization time.
class KtpCameraScreen extends StatefulWidget {
  /// Whether auto-capture is enabled by default. Defaults to true.
  final bool autoCapture;

  /// Duration in milliseconds for the camera to settle autofocus before auto-capturing.
  /// Defaults to 1300 ms.
  final int focusHoldDurationMs;

  /// Custom prompt text displayed above or below the viewfinder.
  final String? title;

  /// Subtitle or instruction line below title.
  final String? subtitle;

  /// Header title for the screen. Defaults to 'SMART INDOPSIKO - OCR -KTP'.
  final String headerTitle;

  /// Whether to show the gallery picker button allowing the user to select an image from the gallery.
  /// If true, the gallery button is visible.
  /// If false, the gallery button is hidden.
  /// Defaults to true.
  final bool enableGallery;

  /// Custom color for the loading indicator spinners, progress ring, and active status accents.
  /// Defaults to amber/orange accent (const Color(0xFFF59E0B)).
  final Color loadingColor;

  /// Optional callback when user taps "Isi Manual".
  final VoidCallback? onManualInput;

  const KtpCameraScreen({
    super.key,
    this.autoCapture = true,
    this.focusHoldDurationMs = 1300,
    this.title,
    this.subtitle,
    this.headerTitle = 'SMART INDOPSIKO - OCR -KTP',
    this.enableGallery = true,
    this.loadingColor = const Color(0xFFF59E0B),
    this.onManualInput,
  });

  @override
  State<KtpCameraScreen> createState() => _KtpCameraScreenState();
}

class _KtpCameraScreenState extends State<KtpCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;

  bool _isCapturing = false;
  bool _isDisposed = false;
  late bool _isAutoMode;
  String _statusMessage = 'Posisikan KTP di dalam bingkai';
  File? _capturedFreezeFile;

  late AnimationController _laserAnimationController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _isAutoMode = widget.autoCapture;
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

  bool _isInitializingCamera = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final CameraController? cameraController = _controller;
      _controller = null;
      if (mounted) {
        setState(() {});
      }
      if (cameraController != null) {
        try {
          if (cameraController.value.isStreamingImages) {
            cameraController.stopImageStream();
          }
        } catch (_) {}
        cameraController.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null || !_controller!.value.isInitialized) {
        _initCamera();
      }
    }
  }

  Future<void> _initCamera() async {
    if (_isDisposed || _isInitializingCamera) return;
    _isInitializingCamera = true;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted && !_isDisposed) {
          setState(() {
            _statusMessage = 'Kamera tidak ditemukan';
          });
        }
        return;
      }

      for (var i = 0; i < _cameras.length; i++) {
        if (_cameras[i].lensDirection == CameraLensDirection.back) {
          _cameraIndex = i;
          break;
        }
      }

      if (_cameraIndex == -1) _cameraIndex = 0;

      await _startLiveCamera(_cameras[_cameraIndex]);
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _statusMessage = 'Gagal mengakses kamera: $e';
        });
      }
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _startLiveCamera(CameraDescription camera) async {
    if (_isDisposed) return;

    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}
      try {
        await oldController.dispose();
      } catch (_) {}
    }

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
      if (!mounted || _isDisposed) {
        await controller.dispose();
        return;
      }

      _controller = controller;

      // Lock portrait orientation for consistent OCR
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Attempt auto-focus & exposure lock if supported
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      // Always start image stream for real-time card guide & detection
      _startImageStream();

      setState(() {});
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _statusMessage = 'Inisialisasi kamera gagal: $e';
        });
      }
    }
  }

  void _startImageStream() {
    // Keep frame fixed/static (tidak mencari KTP kemana-mana)
    // Pengguna memposisikan KTP sendiri tepat ke dalam frame bingkai
    return;
  }

  Future<void> _triggerCapture({bool isAuto = false}) async {
    final controller = _controller;
    if (_isCapturing ||
        controller == null ||
        !controller.value.isInitialized ||
        _isDisposed) {
      return;
    }

    _isCapturing = true;

    // Haptic feedback
    HapticFeedback.heavyImpact();

    if (mounted) {
      setState(() {
        _statusMessage =
            isAuto ? 'KTP terverifikasi! Memproses...' : 'Mengambil gambar...';
      });
    }

    try {
      if (controller.value.isStreamingImages) {
        try {
          await controller.stopImageStream();
        } catch (_) {}
      }

      if (_controller == null ||
          !_controller!.value.isInitialized ||
          _isDisposed) {
        if (mounted) {
          setState(() {
            _isCapturing = false;
          });
        }
        return;
      }

      // Capture high-definition picture
      final XFile picture = await controller.takePicture();
      final File originalFile = File(picture.path);

      // Immediately freeze the captured frame so moving the camera doesn't change what's on screen
      if (mounted) {
        setState(() {
          _capturedFreezeFile = originalFile;
          _statusMessage = 'Mengekstrak data KTP...';
        });
      }

      // 1. Direct Viewport Crop: Since user positioned physical KTP inside the viewfinder frame,
      // crop directly matching the frame on screen for a clean, straight, zero-distortion card image.
      final double cardWidth = 358.w;
      final double cardHeight = cardWidth / 1.5858;
      final File? frameCrop = await cropCameraViewport(
        imageFile: originalFile,
        screenSize: Size(cardWidth, cardHeight),
        viewportRect: Rect.fromLTWH(0, 0, cardWidth, cardHeight),
      );

      // 2. Intelligent deskew fallback if needed
      final File? objectCroppedFile =
          await KtpExtractor.cropImageForKtp(originalFile);

      File finalImage = frameCrop ?? objectCroppedFile ?? originalFile;

      // Extract KTP data
      KtpModel model = await KtpExtractor.extractKtp(finalImage);

      // Dual-pass fallback if crop lost NIK
      if (model.nik == null) {
        final fallbackModel = await KtpExtractor.extractKtp(originalFile);
        if (fallbackModel.nik != null) {
          model = fallbackModel;
        }
      }

      // Crop user profile photo from the KTP card
      final File? photoFile = await KtpExtractor.cropKtpPhotoFile(finalImage);

      if (mounted) {
        Navigator.of(context).pop(KtpCameraResult(
          model: model,
          imageFile: finalImage,
          photoFile: photoFile,
        ));
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isCapturing = false;
          _statusMessage = 'Gagal memproses KTP: $e';
        });
        if (widget.autoCapture &&
            _controller != null &&
            _controller!.value.isInitialized &&
            !_controller!.value.isStreamingImages) {
          _startImageStream();
        }
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing || _isDisposed) return;

    // Temporarily pause streaming if active so camera doesn't run in background
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (_) {}
    }

    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile == null || !mounted || _isDisposed) {
        if (mounted && !_isDisposed) {
          setState(() {
            _isCapturing = false;
            _statusMessage = _isAutoMode
                ? 'Posisikan KTP di dalam bingkai'
                : 'Arahkan KTP ke bingkai lalu foto';
          });
        }
        // If camera was disposed while gallery was open, reinitialize it
        if (_controller == null || !_controller!.value.isInitialized) {
          _initCamera();
        } else if (widget.autoCapture &&
            !_controller!.value.isStreamingImages) {
          _startImageStream();
        }
        return;
      }

      _isCapturing = true;
      HapticFeedback.mediumImpact();

      if (mounted) {
        setState(() {
          _statusMessage = 'Mengekstrak Data KTP dari Galeri...';
        });
      }

      final File originalFile = File(pickedFile.path);

      // Crop KTP object using smart object detector / deskew
      final File? croppedFile =
          await KtpExtractor.cropImageForKtp(originalFile);

      // Extract KTP data
      KtpModel model =
          await KtpExtractor.extractKtp(croppedFile ?? originalFile);
      File finalImage = croppedFile ?? originalFile;

      // Dual-pass fallback if crop lost NIK
      if (model.nik == null && croppedFile != null) {
        final fallbackModel = await KtpExtractor.extractKtp(originalFile);
        if (fallbackModel.nik != null) {
          model = fallbackModel;
        }
      }

      // Crop user profile photo from the KTP card
      final File? photoFile = await KtpExtractor.cropKtpPhotoFile(finalImage);

      if (mounted) {
        Navigator.of(context).pop(KtpCameraResult(
          model: model,
          imageFile: finalImage,
          photoFile: photoFile,
        ));
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isCapturing = false;
          _statusMessage = 'Gagal memproses KTP dari galeri: $e';
        });
        if (widget.autoCapture &&
            _controller != null &&
            _controller!.value.isInitialized &&
            !_controller!.value.isStreamingImages) {
          _startImageStream();
        }
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _laserAnimationController.dispose();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          controller.stopImageStream();
        }
      } catch (_) {}
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        final double cardWidth = 358.w;
        final double cardHeight = cardWidth / 1.5858;

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
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Top Header Bar: Chevron Back + Title
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  // horizontal: 16.w,
                                  vertical: 6.h,
                                ),
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
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                    SizedBox(width: 14.w),
                                    Expanded(
                                      child: Text(
                                        widget.headerTitle,
                                        style: TextStyle(
                                          fontFamily: 'PlusJakartaSans',
                                          color: const Color(0xFF0B3866),
                                          fontSize: 18.sp,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 6.h),

                              // 2. Title & Instruction Subtitle
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20.w),
                                child: Column(
                                  children: [
                                    Text(
                                      widget.title != null &&
                                              widget.title != 'Auto-Capture' &&
                                              widget.title != 'Manual Shutter'
                                          ? widget.title!
                                          : 'Posisikan e-KTP di Dalam Bingkai',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'PlusJakartaSans',
                                        color: const Color(0xFF002245),
                                        fontSize: 18.5.sp,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    SizedBox(height: 4.h),
                                    Text(
                                      widget.subtitle ??
                                          'Sejajarkan 4 sudut kartu dan pastikan NIK terlihat jelas',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'PlusJakartaSans',
                                        color: const Color(0xFF43474F),
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 14.h),

                              // 3. Static/Fixed KTP Card Viewfinder Frame
                              Center(
                                child: Container(
                                  width: cardWidth,
                                  height: cardHeight,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20.r),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF002245)
                                            .withOpacity(0.12),
                                        blurRadius: 20.r,
                                        offset: Offset(0, 8.h),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20.r),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // 3a. Camera Preview / Frozen Captured Picture
                                        _capturedFreezeFile != null
                                            ? Image.file(
                                                _capturedFreezeFile!,
                                                fit: BoxFit.cover,
                                              )
                                            : _controller != null &&
                                                _controller!
                                                    .value.isInitialized &&
                                                !_isDisposed
                                            ? GestureDetector(
                                                onTapDown: (TapDownDetails
                                                    details) async {
                                                  final controller =
                                                      _controller;
                                                  if (controller == null ||
                                                      !controller.value
                                                          .isInitialized) {
                                                    return;
                                                  }
                                                  try {
                                                    final offset = Offset(
                                                      (details.localPosition
                                                                  .dx /
                                                              cardWidth)
                                                          .clamp(0.0, 1.0),
                                                      (details.localPosition
                                                                  .dy /
                                                              cardHeight)
                                                          .clamp(0.0, 1.0),
                                                    );
                                                    await controller
                                                        .setFocusPoint(offset);
                                                    await controller
                                                        .setFocusMode(
                                                            FocusMode.auto);
                                                  } catch (_) {}
                                                },
                                                child: FittedBox(
                                                  fit: BoxFit.cover,
                                                  child: SizedBox(
                                                    width: _controller!
                                                            .value
                                                            .previewSize
                                                            ?.height ??
                                                        cardWidth,
                                                    height: _controller!
                                                            .value
                                                            .previewSize
                                                            ?.width ??
                                                        cardHeight,
                                                    child: CameraPreview(
                                                        _controller!),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                color: const Color(0xFF111C2D),
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                            Color>(
                                                      widget.loadingColor,
                                                    ),
                                                    strokeWidth: 2.5,
                                                  ),
                                                ),
                                              ),

                                        // 3b. KTP Guide Overlay (Watermark, Text, Orange Corners, Laser Scan)
                                        IgnorePointer(
                                          child: AnimatedBuilder(
                                            animation: _laserAnimation,
                                            builder: (context, child) {
                                              final bool isCameraActive =
                                                  _controller != null &&
                                                      _controller!.value
                                                          .isInitialized &&
                                                      !_isDisposed;
                                              return CustomPaint(
                                                size:
                                                    Size(cardWidth, cardHeight),
                                                painter:
                                                    _KtpCardWatermarkAndGuidePainter(
                                                  laserProgress:
                                                      _laserAnimation.value,
                                                  isLocked: false,
                                                  focusProgress: 0.0,
                                                  showWatermark:
                                                      !isCameraActive,
                                                  showLaser: widget.autoCapture,
                                                  cornerRadius: 20.r,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: 16.h),

                              // 4. "Panduan Pindai Maksimal" Info Card
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20.w),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16.w,
                                    vertical: 14.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(18.r),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Card Header
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
                                            'Panduan Pindai Maksimal',
                                            style: TextStyle(
                                              fontFamily: 'PlusJakartaSans',
                                              color: const Color(0xFF002245),
                                              fontSize: 14.sp,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 10.h),

                                      // Tip Item 1
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 17.r,
                                            height: 17.r,
                                            margin: EdgeInsets.only(top: 1.5.h),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF002245)
                                                  .withOpacity(0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '1',
                                                style: TextStyle(
                                                  fontFamily: 'PlusJakartaSans',
                                                  color:
                                                      const Color(0xFF43474F),
                                                  fontSize: 10.sp,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 9.w),
                                          Expanded(
                                            child: Text(
                                              'Hindari kilatan sinar lampu langsung atau pantulan kaca hologram pada permukaan e-KTP.',
                                              style: TextStyle(
                                                fontFamily: 'PlusJakartaSans',
                                                color: const Color(0xFF43474F),
                                                fontSize: 11.8.sp,
                                                height: 1.35,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 8.h),

                                      // Tip Item 2
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 17.r,
                                            height: 17.r,
                                            margin: EdgeInsets.only(top: 1.5.h),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF002245)
                                                  .withOpacity(0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '2',
                                                style: TextStyle(
                                                  fontFamily: 'PlusJakartaSans',
                                                  color:
                                                      const Color(0xFF43474F),
                                                  fontSize: 10.sp,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 9.w),
                                          Expanded(
                                            child: Text(
                                              'Letakkan e-KTP di atas bidang datar dengan latar belakang gelap kontras.',
                                              style: TextStyle(
                                                fontFamily: 'PlusJakartaSans',
                                                color: const Color(0xFF43474F),
                                                fontSize: 11.8.sp,
                                                height: 1.35,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const Spacer(),

                              // 5. Bottom Row Controls: Galeri, Shutter Button, Isi Manual
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 28.w),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Galeri Button (SVG dari Figma)
                                    _buildSvgActionButton(
                                      svgPath: 'assets/icons/ic_galeri.svg',
                                      label: 'Galeri',
                                      onTap: _pickFromGallery,
                                    ),

                                    // Center Orange Shutter Button
                                    GestureDetector(
                                      onTap: () =>
                                          _triggerCapture(isAuto: false),
                                      child: Container(
                                        width: 80.r,
                                        height: 80.r,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFFD990F)
                                              .withOpacity(0.18),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFD990F)
                                                  .withOpacity(0.22),
                                              blurRadius: 16.r,
                                              spreadRadius: 2.r,
                                              offset: Offset(0, 3.h),
                                            ),
                                          ],
                                        ),
                                        alignment: Alignment.center,
                                        child: Container(
                                          width: 66.r,
                                          height: 66.r,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Color(0xFF002245),
                                          ),
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: 56.r,
                                            height: 56.r,
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
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                Color(0xFFFFFFFF),
                                                BlendMode.srcIn,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Isi Manual Button (SVG dari Figma)
                                    _buildSvgActionButton(
                                      svgPath: 'assets/icons/ic_note.svg',
                                      label: 'Isi Manual',
                                      onTap: () {
                                        if (widget.onManualInput != null) {
                                          widget.onManualInput!();
                                        } else {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 14.h),

                              // 6. Security & Privacy Note Footer
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 28.w),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.shield_outlined,
                                      size: 13.sp,
                                      color: const Color(0xFF43474F)
                                          .withOpacity(0.85),
                                    ),
                                    SizedBox(width: 5.w),
                                    Text(
                                      'KEBIJAKAN PRIVASI INDOPSIKO',
                                      style: TextStyle(
                                        fontFamily: 'PlusJakartaSans',
                                        color: const Color(0xFF43474F),
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 10.h),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 7. Processing Loading Screen
              if (_isCapturing)
                Container(
                  color: Colors.black.withOpacity(0.50),
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24.w,
                        vertical: 20.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFF59E0B),
                            ),
                            strokeWidth: 3.0,
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            _statusMessage,
                            style: TextStyle(
                              color: const Color(0xFF0F172A),
                              fontSize: 13.5.sp,
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

  Widget _buildSvgActionButton({
    required String svgPath,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48.r,
            height: 48.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: const Color(0xFF002245).withOpacity(0.08),
                width: 1.r,
              ),
            ),
            alignment: Alignment.center,
            child: SvgPicture.asset(
              svgPath,
              package: 'smart_id_extractor',
              width: 22.r,
              height: 22.r,
              colorFilter: const ColorFilter.mode(
                Color(0xFF002245),
                BlendMode.srcIn,
              ),
            ),
          ),
          SizedBox(height: 7.h),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              color: const Color(0xFF002245),
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the KTP Card watermark guide, translucent KTP layout,
/// amber glowing corner brackets, and scanning laser line.
class _KtpCardWatermarkAndGuidePainter extends CustomPainter {
  final double laserProgress;
  final bool isLocked;
  final double focusProgress;
  final bool showWatermark;
  final bool showLaser;
  final double cornerRadius;

  _KtpCardWatermarkAndGuidePainter({
    required this.laserProgress,
    required this.isLocked,
    this.focusProgress = 0.0,
    this.showWatermark = false,
    this.showLaser = true,
    this.cornerRadius = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect cardRect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(cardRect, Radius.circular(cornerRadius));

    // Outer subtle card frame with clear border for KTP positioning
    final Paint cardBorderPaint = Paint()
      ..color = const Color(0xFF002245).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, cardBorderPaint);

    if (showWatermark) {
      // 1. Semi-translucent KTP Card Body with soft blue-grey tint & shadow
      final Paint cardBgPaint = Paint()
        ..color = const Color(0xFF90B5D8).withOpacity(0.55)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, cardBgPaint);

      // 2. KTP Text Header ("REPUBLIK INDONESIA" & "PROVINSI DKI JAKARTA")
      final TextPainter headerPainter = TextPainter(
        text: const TextSpan(
          text: 'REPUBLIK INDONESIA\n',
          style: TextStyle(
            color: Color(0xFF1E3A5F),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            height: 1.25,
          ),
          children: [
            TextSpan(
              text: 'PROVINSI ANDA',
              style: TextStyle(
                color: Color(0xFF2C4A6F),
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      headerPainter.layout(maxWidth: size.width);
      headerPainter.paint(
        canvas,
        Offset((size.width - headerPainter.width) / 2, size.height * 0.08),
      );

      // 3. KTP Text placeholder bars (representing NIK, Name, Address lines)
      final Paint linePaint = Paint()
        ..color = const Color(0xFF6B8BAA).withOpacity(0.70)
        ..style = PaintingStyle.fill;

      const double leftMargin = 16.0;
      final double textStartY = size.height * 0.38;
      const double lineHeight = 5.5;
      const double lineSpacing = 10.0;
      final List<double> lineWidths = [
        size.width * 0.28,
        size.width * 0.36,
        size.width * 0.32,
        size.width * 0.23,
      ];

      for (int i = 0; i < lineWidths.length; i++) {
        final lineRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            leftMargin,
            textStartY + (i * lineSpacing),
            lineWidths[i],
            lineHeight,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(lineRect, linePaint);
      }

      // 4. Subtle center chip / qr watermark icon
      final Paint chipPaint = Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      final double chipCenterX = size.width * 0.44;
      final double chipCenterY = size.height * 0.48;
      final Rect chipRect = Rect.fromCenter(
        center: Offset(chipCenterX, chipCenterY),
        width: 18,
        height: 18,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
        chipPaint,
      );

      // 5. Photo Box on the right side
      final double photoWidth = size.width * 0.18;
      final double photoHeight = size.height * 0.32;
      final double photoLeft = size.width - photoWidth - 18.0;
      final double photoTop = size.height * 0.36;

      final RRect photoRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(photoLeft, photoTop, photoWidth, photoHeight),
        const Radius.circular(10),
      );

      // Photo Box Background (White translucent card)
      canvas.drawRRect(
        photoRRect,
        Paint()
          ..color = Colors.white.withOpacity(0.85)
          ..style = PaintingStyle.fill,
      );

      // Avatar Icon Placeholder inside Photo Box
      final Paint avatarPaint = Paint()
        ..color = const Color(0xFF7E97AF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final Offset avatarHeadCenter = Offset(
        photoLeft + photoWidth / 2,
        photoTop + photoHeight * 0.36,
      );
      canvas.drawCircle(avatarHeadCenter, 6.5, avatarPaint);

      final Path avatarBodyPath = Path()
        ..addArc(
          Rect.fromCenter(
            center: Offset(
                photoLeft + photoWidth / 2, photoTop + photoHeight * 0.72),
            width: 18,
            height: 14,
          ),
          pi,
          pi,
        );
      canvas.drawPath(avatarBodyPath, avatarPaint);

      // Photo signature line beneath avatar
      canvas.drawLine(
        Offset(photoLeft + 6, photoTop + photoHeight - 5),
        Offset(photoLeft + photoWidth - 6, photoTop + photoHeight - 5),
        Paint()
          ..color = const Color(0xFFD4A373)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );

      // 6. Bottom Text Placeholders: "BERLAKU SEUMUR HIDUP" & "JAKARTA, 12-04-2018"
      final TextPainter bottomTextLeft = TextPainter(
        text: const TextSpan(
          text: 'BERLAKU SEUMUR HIDUP',
          style: TextStyle(
            color: Color(0xFF2C4A6F),
            fontSize: 6.8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bottomTextLeft.paint(
        canvas,
        Offset(leftMargin, size.height - 18),
      );

      final TextPainter bottomTextRight = TextPainter(
        text: const TextSpan(
          text: 'DAERAH, 00-00-0000',
          style: TextStyle(
            color: Color(0xFF2C4A6F),
            fontSize: 6.8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bottomTextRight.paint(
        canvas,
        Offset(size.width - bottomTextRight.width - 18, size.height - 18),
      );
    }

    // 7. Live KTP Photo Target Box (Kotak target posisi foto KTP di sisi kanan)
    // Ukuran diperkecil agar pas dan proporsional dengan pasfoto fisik e-KTP
    final double livePhotoWidth = size.width * 0.200;
    final double livePhotoHeight = size.height * 0.400;
    final double livePhotoLeft = size.width * 0.715;
    final double livePhotoTop = size.height * 0.300;

    final RRect livePhotoRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          livePhotoLeft, livePhotoTop, livePhotoWidth, livePhotoHeight),
      Radius.circular(8.0 * (cornerRadius / 20.0)),
    );

    // Glowing subtle target border
    final Paint photoBoxBorder = Paint()
      ..color = const Color(0xFFFD990F).withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * (cornerRadius / 20.0);
    canvas.drawRRect(livePhotoRRect, photoBoxBorder);

    // Subtle translucent background tint
    final Paint photoBoxBg = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(livePhotoRRect, photoBoxBg);

    // Minimal user avatar watermark in center of photo box
    final double photoCenterX = livePhotoLeft + (livePhotoWidth / 2.0);
    final double photoCenterY = livePhotoTop + (livePhotoHeight * 0.38);
    final Paint userSilhouettePaint = Paint()
      ..color = const Color(0xFFFD990F).withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(
        Offset(photoCenterX, photoCenterY), 8.0, userSilhouettePaint);

    final Path userSilhouetteBody = Path()
      ..addArc(
        Rect.fromCenter(
          center: Offset(photoCenterX, photoCenterY + 14.0),
          width: 18,
          height: 13,
        ),
        pi,
        pi,
      );
    canvas.drawPath(userSilhouetteBody, userSilhouettePaint);

    // 7. Glowing Orange Scanning Laser Line (Horizontal laser across the card)
    // Dibuat lebih tipis dan pudar/soft agar tidak mengganggu pandangan
    if (showLaser) {
      final double laserY = size.height * (0.15 + (laserProgress * 0.70));
      final Paint laserLinePaint = Paint()
        ..shader = const LinearGradient(
          colors: [
            Colors.transparent,
            Color(0x99FD990F),
            Color(0xCCFBBF24),
            Color(0x99FD990F),
            Colors.transparent,
          ],
          stops: [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(Rect.fromLTWH(0, laserY, size.width, 1.5))
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      final Paint laserGlowPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFFFD990F).withOpacity(0.12),
            const Color(0xFFFD990F).withOpacity(0.12),
            Colors.transparent,
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ).createShader(Rect.fromLTWH(0, laserY - 4, size.width, 8))
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(12, laserY),
        Offset(size.width - 12, laserY),
        laserGlowPaint,
      );
      canvas.drawLine(
        Offset(12, laserY),
        Offset(size.width - 12, laserY),
        laserLinePaint,
      );
    }

    // 8. High-visibility Orange Corner Brackets with Glow
    _drawOrangeCornerBrackets(canvas, size);
  }

  void _drawOrangeCornerBrackets(Canvas canvas, Size size) {
    final double padding = 12.0 * (cornerRadius / 20.0);
    final double bracketLength = 24.0 * (cornerRadius / 20.0);
    final double strokeW = 4.0 * (cornerRadius / 20.0);
    final double r = 14.0 * (cornerRadius / 20.0);
    final double offset = padding + (strokeW / 2);
    final double arcR = r - (strokeW / 2);
    const Color orangeColor = Color(0xFFFD990F);

    final Paint glowPaint = Paint()
      ..color = orangeColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW + 4.0
      ..strokeCap = StrokeCap.round;

    final Paint cornerPaint = Paint()
      ..color = orangeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    void drawCorner(Path path) {
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, cornerPaint);
    }

    // Top-Left corner (diberi padding agar berada di dalam frame):
    final Path tl = Path()
      ..moveTo(offset, offset + r + bracketLength)
      ..lineTo(offset, offset + r)
      ..arcToPoint(
        Offset(offset + r, offset),
        radius: Radius.circular(arcR),
        clockwise: true,
      )
      ..lineTo(offset + r + bracketLength, offset);
    drawCorner(tl);

    // Top-Right corner:
    final Path tr = Path()
      ..moveTo(size.width - offset - r - bracketLength, offset)
      ..lineTo(size.width - offset - r, offset)
      ..arcToPoint(
        Offset(size.width - offset, offset + r),
        radius: Radius.circular(arcR),
        clockwise: true,
      )
      ..lineTo(size.width - offset, offset + r + bracketLength);
    drawCorner(tr);

    // Bottom-Left corner:
    final Path bl = Path()
      ..moveTo(offset, size.height - offset - r - bracketLength)
      ..lineTo(offset, size.height - offset - r)
      ..arcToPoint(
        Offset(offset + r, size.height - offset),
        radius: Radius.circular(arcR),
        clockwise: false,
      )
      ..lineTo(offset + r + bracketLength, size.height - offset);
    drawCorner(bl);

    // Bottom-Right corner:
    final Path br = Path()
      ..moveTo(size.width - offset - r - bracketLength, size.height - offset)
      ..lineTo(size.width - offset - r, size.height - offset)
      ..arcToPoint(
        Offset(size.width - offset, size.height - offset - r),
        radius: Radius.circular(arcR),
        clockwise: false,
      )
      ..lineTo(size.width - offset, size.height - offset - r - bracketLength);
    drawCorner(br);
  }

  @override
  bool shouldRepaint(covariant _KtpCardWatermarkAndGuidePainter oldDelegate) {
    return oldDelegate.laserProgress != laserProgress ||
        oldDelegate.isLocked != isLocked ||
        oldDelegate.focusProgress != focusProgress;
  }
}
