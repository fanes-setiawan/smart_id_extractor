// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'custom_snackbar.dart';

/// Alignment status of a detected face inside the oval frame guide.
enum SmartFaceFrameStatus {
  noFace,
  multipleFaces,
  tooFar,
  tooClose,
  offCenter,
  aligned,
}

/// A complete, standalone Face Camera Screen featuring:
/// - Smooth Oval Face Guide Frame (`SmartFaceFrameOverlayPainter`)
/// - Live face detection via Google ML Kit
/// - Real-time color-coded visual feedback (Green = Aligned, Amber = Adjust, White = Neutral)
/// - Instruction banner with smooth transitions
/// - Front/back camera toggle
/// - Disabled shutter button until face is aligned
/// - Disabled Save button until captured photo has a valid, aligned face
class SmartFaceCameraScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final ValueChanged<File>? onPhotoSaved;

  const SmartFaceCameraScreen({
    super.key,
    this.title = 'Foto Profil',
    this.subtitle = 'Posisikan wajah Anda di dalam bingkai oval',
    this.onPhotoSaved,
  });

  @override
  State<SmartFaceCameraScreen> createState() => _SmartFaceCameraScreenState();
}

class _SmartFaceCameraScreenState extends State<SmartFaceCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;

  File? _capturedFile;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _isProcessingCapture = false;

  late final FaceDetector _faceDetector;

  SmartFaceFrameStatus _frameStatus = SmartFaceFrameStatus.noFace;
  String _guideMessage = 'Posisikan wajah Anda di dalam bingkai oval';
  bool _isFaceAligned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableContours: false,
        enableClassification: false,
        minFaceSize: 0.25,
      ),
    );
    _initCamerasAndController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopLiveDetection();
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamerasAndController();
    }
  }

  Future<void> _initCamerasAndController() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) return;

      // Prefer front-facing camera
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
    _stopLiveDetection();
    await _controller?.dispose();

    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
      _startLiveDetection();
    } catch (e) {
      debugPrint('Error setting up camera controller: $e');
    }
  }

  void _startLiveDetection() {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isStreamingImages) {
      return;
    }

    _controller!.startImageStream((CameraImage image) {
      if (_isDetecting || _capturedFile != null || _isProcessingCapture) return;
      _isDetecting = true;
      _processCameraImage(image);
    });
  }

  void _stopLiveDetection() {
    if (_controller != null &&
        _controller!.value.isInitialized &&
        _controller!.value.isStreamingImages) {
      try {
        _controller!.stopImageStream();
      } catch (e) {
        debugPrint('Error stopping image stream: $e');
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _buildInputImageFromCamera(image);
      if (inputImage == null) {
        _isDetecting = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      _evaluateFaces(faces, image.width, image.height);
    } catch (e) {
      // Ignore transient ML Kit exceptions
    } finally {
      _isDetecting = false;
    }
  }

  InputImage? _buildInputImageFromCamera(CameraImage image) {
    if (_controller == null) return null;
    final camera = _availableCameras[_selectedCameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation =
            (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    } else {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  void _evaluateFaces(List<Face> faces, int imgWidth, int imgHeight) {
    if (!mounted || _capturedFile != null) return;

    if (faces.isEmpty) {
      _updateStatus(
        SmartFaceFrameStatus.noFace,
        'Posisikan wajah Anda tepat di dalam bingkai oval',
        false,
      );
      return;
    }

    if (faces.length > 1) {
      _updateStatus(
        SmartFaceFrameStatus.multipleFaces,
        'Pastikan hanya ada satu wajah di dalam kamera',
        false,
      );
      return;
    }

    final face = faces.first;
    final box = face.boundingBox;

    final double minDim = math.min(imgWidth, imgHeight).toDouble();
    final double faceDim = math.max(box.width, box.height);
    final double ratio = faceDim / minDim;

    final double imgCenterX = (box.left + box.right) / 2.0;
    final double imgCenterY = (box.top + box.bottom) / 2.0;
    final double relOffsetX =
        (imgCenterX - (imgWidth / 2.0)).abs() / (imgWidth / 2.0);
    final double relOffsetY =
        (imgCenterY - (imgHeight / 2.0)).abs() / (imgHeight / 2.0);

    if (ratio < 0.28) {
      _updateStatus(
        SmartFaceFrameStatus.tooFar,
        'Dekatkan wajah Anda ke kamera',
        false,
      );
    } else if (ratio > 0.85) {
      _updateStatus(
        SmartFaceFrameStatus.tooClose,
        'Jauhkan sedikit wajah Anda dari kamera',
        false,
      );
    } else if (relOffsetX > 0.35 || relOffsetY > 0.35) {
      _updateStatus(
        SmartFaceFrameStatus.offCenter,
        'Posisikan wajah tepat di tengah bingkai',
        false,
      );
    } else {
      _updateStatus(
        SmartFaceFrameStatus.aligned,
        'Posisi wajah sudah pas! Tekan tombol untuk memotret',
        true,
      );
    }
  }

  void _updateStatus(
      SmartFaceFrameStatus status, String message, bool aligned) {
    if (_frameStatus == status &&
        _guideMessage == message &&
        _isFaceAligned == aligned) {
      return;
    }
    setState(() {
      _frameStatus = status;
      _guideMessage = message;
      _isFaceAligned = aligned;
    });
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) return;
    _selectedCameraIndex =
        (_selectedCameraIndex + 1) % _availableCameras.length;
    await _setupCameraController(_availableCameras[_selectedCameraIndex]);
  }

  Future<void> _takePicture() async {
    if (!_isFaceAligned) {
      showCustomSnackBar(
        context,
        'Posisikan wajah Anda di dalam bingkai oval terlebih dahulu.',
      );
      return;
    }

    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isTakingPicture) {
      return;
    }

    setState(() {
      _isProcessingCapture = true;
    });
    _stopLiveDetection();

    try {
      final XFile picture = await _controller!.takePicture();
      final File file = File(picture.path);

      // Verify still image contains face
      final inputImage = InputImage.fromFilePath(file.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        showCustomSnackBar(
          context,
          'Wajah tidak terdeteksi. Silakan ulangi dengan posisi wajah di dalam bingkai.',
        );
        _startLiveDetection();
        setState(() {
          _isProcessingCapture = false;
        });
        return;
      }

      setState(() {
        _capturedFile = file;
        _isFaceAligned = true;
        _guideMessage =
            'Foto profil siap disimpan. Pastikan posisi wajah sudah sesuai.';
      });
    } catch (e) {
      debugPrint('Error taking face picture: $e');
      _startLiveDetection();
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
    _stopLiveDetection();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double ovalWidth = screenSize.width * 0.70;
    final double ovalHeight = ovalWidth * 1.35;

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

                      // Oval Face Frame Overlay
                      CustomPaint(
                        size: Size.infinite,
                        painter: SmartFaceFrameOverlayPainter(
                          ovalWidth: ovalWidth,
                          ovalHeight: ovalHeight,
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
                                ? const Color(0xFF065F46)
                                    .withOpacity(0.90)
                                : const Color(0xFF0F172A)
                                    .withOpacity(0.85),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: _isFaceAligned
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFFD990F)
                                      .withOpacity(0.8),
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
              color: Colors.black.withOpacity(0.55),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Color(0xFFFD990F),
                    ),
                    SizedBox(height: 14.h),
                    Text(
                      'Memeriksa posisi wajah...',
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
    final bool canCapture = _isFaceAligned && !_isProcessingCapture;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          canCapture
              ? 'Posisi wajah sesuai! Tekan untuk memotret'
              : 'Sesuaikan wajah dengan bingkai oval untuk memotret',
          textAlign: TextAlign.center,
          style: TextStyle(
            color:
                canCapture ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
            fontSize: 12.sp,
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 14.h),
        GestureDetector(
          onTap: canCapture
              ? _takePicture
              : () {
                  showCustomSnackBar(
                    context,
                    'Posisikan wajah Anda di dalam bingkai oval terlebih dahulu.',
                  );
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 72.w,
            width: 72.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: canCapture
                  ? const Color(0xFFFD990F)
                  : const Color(0xFF334155),
              boxShadow: canCapture
                  ? [
                      BoxShadow(
                        color:
                            const Color(0xFFFD990F).withOpacity(0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            padding: EdgeInsets.all(5.w),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2.5,
                ),
                color: canCapture
                    ? const Color(0xFFFD990F)
                    : const Color(0xFF1E293B),
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                color: canCapture ? Colors.white : const Color(0xFF64748B),
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
                      'Posisikan wajah Anda di dalam bingkai oval';
                  _isFaceAligned = false;
                });
                _startLiveDetection();
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

/// Custom painter for the face frame oval cutout and adaptive border.
class SmartFaceFrameOverlayPainter extends CustomPainter {
  final double ovalWidth;
  final double ovalHeight;
  final bool isAligned;
  final SmartFaceFrameStatus status;
  final bool hasPhoto;

  SmartFaceFrameOverlayPainter({
    required this.ovalWidth,
    required this.ovalHeight,
    required this.isAligned,
    required this.status,
    required this.hasPhoto,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final center = Offset(size.width / 2.0, size.height * 0.44);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    // 1. Dark semi-transparent scrim with oval cutout
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(ovalRect);
    final transparentHolePath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      ovalPath,
    );

    final scrimPaint = Paint()
      ..color = Colors.black.withOpacity(hasPhoto ? 0.40 : 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(transparentHolePath, scrimPaint);

    // 2. Oval Outline with state color
    final Color borderColor = isAligned
        ? const Color(0xFF10B981) // Emerald Green
        : (status == SmartFaceFrameStatus.offCenter ||
                status == SmartFaceFrameStatus.tooFar ||
                status == SmartFaceFrameStatus.tooClose)
            ? const Color(0xFFFD990F) // Amber
            : Colors.white.withOpacity(0.45);

    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = isAligned ? 3.0 : 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ovalRect, borderPaint);

    // 3. Inner soft guideline for eye-level
    final innerGuidePaint = Paint()
      ..color = Colors.white.withOpacity(0.20)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double eyeLevelY = ovalRect.top + (ovalRect.height * 0.38);
    const double dashWidth = 6.0;
    const double dashSpace = 6.0;
    final double eyeLineStart = ovalRect.left + (ovalRect.width * 0.20);
    final double eyeLineEnd = ovalRect.right - (ovalRect.width * 0.20);

    double currentX = eyeLineStart;
    while (currentX < eyeLineEnd) {
      canvas.drawLine(
        Offset(currentX, eyeLevelY),
        Offset(math.min(currentX + dashWidth, eyeLineEnd), eyeLevelY),
        innerGuidePaint,
      );
      currentX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant SmartFaceFrameOverlayPainter oldDelegate) {
    return oldDelegate.ovalWidth != ovalWidth ||
        oldDelegate.ovalHeight != ovalHeight ||
        oldDelegate.isAligned != isAligned ||
        oldDelegate.status != status ||
        oldDelegate.hasPhoto != hasPhoto;
  }
}
