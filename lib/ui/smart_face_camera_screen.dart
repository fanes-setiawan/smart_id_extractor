// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'custom_snackbar.dart';

/// Alignment status of a detected face inside the head & shoulders frame guide.
enum SmartFaceFrameStatus {
  noFace,
  multipleFaces,
  tooFar,
  tooClose,
  offCenter,
  aligned,
}

/// A complete Face Camera Screen featuring:
/// - Combined Head (Oval) & Shoulders Frame Guide (`SmartFaceFrameOverlayPainter`)
/// - Works standalone without ScreenUtil dependency errors (uses ScreenUtilInit safe fallback)
/// - Robust Still-Frame Verification (prevents camera ImageStream buffer crashes)
/// - Live color-coded visual feedback (Green = Aligned, Amber = Adjust, White = Neutral)
/// - Instruction banner with smooth transitions
/// - Front/back camera toggle
/// - Disabled shutter button until face is positioned
/// - Disabled Save button until captured photo has a valid, aligned face
class SmartFaceCameraScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final ValueChanged<File>? onPhotoSaved;

  const SmartFaceCameraScreen({
    super.key,
    this.title = 'Foto Profil',
    this.subtitle = 'Posisikan kepala dan bahu di dalam bingkai',
    this.onPhotoSaved,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return _SmartFaceCameraView(
          title: title,
          subtitle: subtitle,
          onPhotoSaved: onPhotoSaved,
        );
      },
    );
  }
}

class _SmartFaceCameraView extends StatefulWidget {
  final String title;
  final String subtitle;
  final ValueChanged<File>? onPhotoSaved;

  const _SmartFaceCameraView({
    required this.title,
    required this.subtitle,
    this.onPhotoSaved,
  });

  @override
  State<_SmartFaceCameraView> createState() => _SmartFaceCameraViewState();
}

class _SmartFaceCameraViewState extends State<_SmartFaceCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;

  File? _capturedFile;
  bool _isCameraInitialized = false;
  bool _isProcessingCapture = false;

  late final FaceDetector _faceDetector;

  SmartFaceFrameStatus _frameStatus = SmartFaceFrameStatus.noFace;
  String _guideMessage = 'Posisikan kepala dan bahu Anda di dalam bingkai';
  bool _isFaceAligned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableClassification: false,
        minFaceSize: 0.20,
      ),
    );
    _initCamerasAndController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamerasAndController();
    }
  }

  Future<void> _initCamerasAndController() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) return;

      int frontIndex = _availableCameras.indexWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );
      _selectedCameraIndex = frontIndex != -1 ? frontIndex : 0;

      await _setupCameraController(_availableCameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _setupCameraController(CameraDescription description) async {
    await _controller?.dispose();

    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Error setting up camera controller: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) return;
    _selectedCameraIndex =
        (_selectedCameraIndex + 1) % _availableCameras.length;
    await _setupCameraController(_availableCameras[_selectedCameraIndex]);
  }

  Future<void> _takePictureAndVerify() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isTakingPicture ||
        _isProcessingCapture) {
      return;
    }

    setState(() {
      _isProcessingCapture = true;
    });

    try {
      final XFile picture = await _controller!.takePicture();
      final File file = File(picture.path);

      // Verify face position in the captured photo using ML Kit
      final inputImage = InputImage.fromFilePath(file.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        showCustomSnackBar(
          context,
          'Wajah tidak terdeteksi. Posisikan wajah dan bahu tepat di dalam bingkai.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.noFace;
          _isFaceAligned = false;
          _guideMessage = 'Wajah tidak terdeteksi di dalam bingkai';
        });
        return;
      }

      if (faces.length > 1) {
        showCustomSnackBar(
          context,
          'Terdeteksi lebih dari satu wajah. Pastikan hanya ada satu orang.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.multipleFaces;
          _isFaceAligned = false;
          _guideMessage = 'Pastikan hanya ada satu wajah di bingkai';
        });
        return;
      }

      final face = faces.first;
      final box = face.boundingBox;

      // Decode image dimensions to check alignment ratio
      final decodedImage = await decodeImageFromList(await file.readAsBytes());
      final imgW = decodedImage.width.toDouble();
      final imgH = decodedImage.height.toDouble();

      final minDim = math.min(imgW, imgH);
      final faceDim = math.max(box.width, box.height);
      final ratio = faceDim / minDim;

      final faceCenterX = (box.left + box.right) / 2.0;
      final faceCenterY = (box.top + box.bottom) / 2.0;
      final relOffsetX = (faceCenterX - (imgW / 2.0)).abs() / (imgW / 2.0);
      final relOffsetY = (faceCenterY - (imgH * 0.40)).abs() / (imgH * 0.40);

      if (ratio < 0.22) {
        showCustomSnackBar(
          context,
          'Posisi wajah terlalu jauh. Dekatkan wajah Anda ke kamera.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.tooFar;
          _isFaceAligned = false;
          _guideMessage = 'Dekatkan wajah Anda ke kamera';
        });
        return;
      }

      if (ratio > 0.82) {
        showCustomSnackBar(
          context,
          'Posisi wajah terlalu dekat. Jauhkan sedikit wajah Anda.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.tooClose;
          _isFaceAligned = false;
          _guideMessage = 'Jauhkan sedikit wajah Anda dari kamera';
        });
        return;
      }

      if (relOffsetX > 0.35 || relOffsetY > 0.45) {
        showCustomSnackBar(
          context,
          'Posisi wajah tidak pas di tengah. Sejajarkan kepala dan bahu di bingkai.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.offCenter;
          _isFaceAligned = false;
          _guideMessage = 'Posisikan wajah tepat di tengah bingkai';
        });
        return;
      }

      // Valid & Aligned!
      setState(() {
        _capturedFile = file;
        _isFaceAligned = true;
        _frameStatus = SmartFaceFrameStatus.aligned;
        _guideMessage = 'Posisi kepala dan bahu sesuai! Siap disimpan.';
      });
    } catch (e) {
      debugPrint('Error capturing and verifying face: $e');
      showCustomSnackBar(
        context,
        'Terjadi kendala saat memproses foto. Silakan coba lagi.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingCapture = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF071426),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071426),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_capturedFile == null && _availableCameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_ios_rounded,
                  color: Colors.white),
              onPressed: _switchCamera,
              tooltip: 'Ganti Kamera',
            ),
          SizedBox(width: 8.w),
        ],
      ),
      body: Stack(
        children: [
          if (!_isCameraInitialized && _capturedFile == null)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFD990F),
              ),
            )
          else
            Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_capturedFile == null &&
                          _controller != null &&
                          _controller!.value.isInitialized)
                        Center(
                          child: AspectRatio(
                            aspectRatio: 1 / _controller!.value.aspectRatio,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      if (_capturedFile != null)
                        Center(
                          child: Image.file(
                            _capturedFile!,
                            fit: BoxFit.contain,
                          ),
                        ),

                      // Head & Shoulders Frame Overlay
                      CustomPaint(
                        size: Size.infinite,
                        painter: SmartFaceFrameOverlayPainter(
                          screenSize: screenSize,
                          isAligned: _isFaceAligned,
                          status: _frameStatus,
                          hasPhoto: _capturedFile != null,
                        ),
                      ),

                      // Top Guidance Banner
                      Positioned(
                        top: 16.h,
                        left: 20.w,
                        right: 20.w,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 10.h,
                          ),
                          decoration: BoxDecoration(
                            color: _isFaceAligned
                                ? const Color(0xFF065F46).withOpacity(0.92)
                                : const Color(0xFF0F172A).withOpacity(0.88),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: _isFaceAligned
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFFD990F).withOpacity(0.85),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isFaceAligned
                                    ? Icons.check_circle_rounded
                                    : Icons.face_retouching_natural_rounded,
                                color: _isFaceAligned
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFFD990F),
                                size: 22.sp,
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  _guideMessage,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.sp,
                                    fontFamily: 'PlusJakartaSans',
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Control Bar
                Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0B192C),
                    border: Border(
                      top: BorderSide(
                        color: Color(0xFF1E293B),
                        width: 1,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: _capturedFile == null
                        ? _buildCaptureControls()
                        : _buildReviewControls(),
                  ),
                ),
              ],
            ),

          if (_isProcessingCapture)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withOpacity(0.60),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFFFD990F),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'Memeriksa posisi kepala & bahu...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontFamily: 'PlusJakartaSans',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Posisikan kepala dan bahu di dalam bingkai',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color(0xFF94A3B8),
            fontSize: 12.sp,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 14.h),
        GestureDetector(
          onTap: _takePictureAndVerify,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 72.w,
            width: 72.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFD990F),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFD990F).withOpacity(0.40),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: EdgeInsets.all(5.w),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2.5,
                ),
                color: const Color(0xFFFD990F),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 30.sp,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewControls() {
    final bool canSave = _isFaceAligned;

    return Row(
      children: [
        // Ulangi Button
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _capturedFile = null;
                  _frameStatus = SmartFaceFrameStatus.noFace;
                  _guideMessage =
                      'Posisikan kepala dan bahu Anda di dalam bingkai';
                  _isFaceAligned = false;
                });
              },
              icon: Icon(Icons.refresh_rounded,
                  size: 20.sp, color: Colors.white),
              label: Text(
                'Ulangi',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'PlusJakartaSans',
                  fontWeight: FontWeight.w600,
                  fontSize: 14.sp,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side:
                    const BorderSide(color: Color(0xFF334155), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 14.w),

        // Simpan Button (Disabled if face is not aligned/valid)
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: ElevatedButton.icon(
              onPressed: canSave
                  ? () {
                      if (widget.onPhotoSaved != null) {
                        widget.onPhotoSaved!(_capturedFile!);
                      }
                      Navigator.pop(context, _capturedFile);
                    }
                  : () {
                      showCustomSnackBar(
                        context,
                        'Posisi wajah belum sesuai dengan frame. Silakan ulangi pemotretan.',
                      );
                    },
              icon: Icon(
                Icons.check_circle_outline_rounded,
                size: 20.sp,
                color: canSave ? Colors.white : const Color(0xFF94A3B8),
              ),
              label: Text(
                'Simpan',
                style: TextStyle(
                  color: canSave ? Colors.white : const Color(0xFF94A3B8),
                  fontFamily: 'PlusJakartaSans',
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canSave
                    ? const Color(0xFFFD990F)
                    : const Color(0xFF334155),
                disabledBackgroundColor: const Color(0xFF334155),
                elevation: canSave ? 3 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for the Head & Shoulders frame cutout and adaptive border.
class SmartFaceFrameOverlayPainter extends CustomPainter {
  final Size screenSize;
  final bool isAligned;
  final SmartFaceFrameStatus status;
  final bool hasPhoto;

  SmartFaceFrameOverlayPainter({
    required this.screenSize,
    required this.isAligned,
    required this.status,
    required this.hasPhoto,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final double headWidth = size.width * 0.54;
    final double headHeight = headWidth * 1.30;
    final double headCenterY = size.height * 0.38;
    final headRect = Rect.fromCenter(
      center: Offset(size.width / 2.0, headCenterY),
      width: headWidth,
      height: headHeight,
    );

    // Build Head (Oval) + Shoulders (Curved base) Silhouette Path
    final silhouettePath = Path();

    // 1. Head Oval
    silhouettePath.addOval(headRect);

    // 2. Shoulders Path
    final double shoulderTopY = headRect.bottom - (headHeight * 0.18);
    final double shoulderWidth = size.width * 0.88;
    final double shoulderLeft = (size.width - shoulderWidth) / 2.0;
    final double shoulderRight = shoulderLeft + shoulderWidth;
    final double shoulderBottomY = size.height * 0.80;

    final shoulderPath = Path();
    shoulderPath.moveTo(headRect.left + (headWidth * 0.15), shoulderTopY);
    // Left shoulder curve
    shoulderPath.quadraticBezierTo(
      shoulderLeft + (shoulderWidth * 0.15),
      shoulderTopY + 25,
      shoulderLeft,
      shoulderBottomY,
    );
    shoulderPath.lineTo(shoulderRight, shoulderBottomY);
    // Right shoulder curve
    shoulderPath.quadraticBezierTo(
      shoulderRight - (shoulderWidth * 0.15),
      shoulderTopY + 25,
      headRect.right - (headWidth * 0.15),
      shoulderTopY,
    );
    shoulderPath.close();

    // Combined Cutout
    final combinedGuidePath = Path.combine(
      PathOperation.union,
      silhouettePath,
      shoulderPath,
    );

    // Dark semi-transparent scrim with silhouette cutout
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final transparentHolePath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      combinedGuidePath,
    );

    final scrimPaint = Paint()
      ..color = Colors.black.withOpacity(hasPhoto ? 0.35 : 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(transparentHolePath, scrimPaint);

    // Outline with state color
    final Color borderColor = isAligned
        ? const Color(0xFF10B981) // Emerald Green
        : (status == SmartFaceFrameStatus.offCenter ||
                status == SmartFaceFrameStatus.tooFar ||
                status == SmartFaceFrameStatus.tooClose)
            ? const Color(0xFFFD990F) // Amber
            : Colors.white.withOpacity(0.50);

    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = isAligned ? 3.0 : 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(combinedGuidePath, borderPaint);

    // Soft eye-level line across head oval
    final eyeLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.20)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double eyeLevelY = headRect.top + (headHeight * 0.38);
    const double dashWidth = 6.0;
    const double dashSpace = 6.0;
    final double eyeLineStart = headRect.left + (headWidth * 0.20);
    final double eyeLineEnd = headRect.right - (headWidth * 0.20);

    double currentX = eyeLineStart;
    while (currentX < eyeLineEnd) {
      canvas.drawLine(
        Offset(currentX, eyeLevelY),
        Offset(math.min(currentX + dashWidth, eyeLineEnd), eyeLevelY),
        eyeLinePaint,
      );
      currentX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant SmartFaceFrameOverlayPainter oldDelegate) {
    return oldDelegate.isAligned != isAligned ||
        oldDelegate.status != status ||
        oldDelegate.hasPhoto != hasPhoto;
  }
}
