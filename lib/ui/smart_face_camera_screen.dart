import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_svg/flutter_svg.dart';
import 'custom_snackbar.dart';

enum SmartFaceFrameStatus {
  noFace,
  multipleFaces,
  tooFar,
  tooClose,
  offCenter,
  aligned,
}

class SmartFaceCameraScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final ValueChanged<File>? onPhotoSaved;

  const SmartFaceCameraScreen({
    super.key,
    this.title = 'Uji Foto Profil',
    this.subtitle = 'Posisikan kepala & bahu sesuai siluet',
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
  bool _isProcessingCapture = false;
  bool _isDetecting = false;
  DateTime _lastDetectionTime = DateTime.fromMillisecondsSinceEpoch(0);

  late final FaceDetector _faceDetector;

  bool get _isFrontCamera {
    if (_availableCameras.isEmpty ||
        _selectedCameraIndex >= _availableCameras.length) {
      return true;
    }
    return _availableCameras[_selectedCameraIndex].lensDirection ==
        CameraLensDirection.front;
  }

  SmartFaceFrameStatus _frameStatus = SmartFaceFrameStatus.noFace;
  bool _isFaceAligned = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
        minFaceSize: 0.15,
      ),
    );
    _initCamerasAndController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopImageStream();
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
    await _stopImageStream();
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
      setState(() {});
      _startImageStream();
    } catch (e) {
      debugPrint('Error setting up camera controller: $e');
    }
  }

  void _startImageStream() {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages) {
      return;
    }

    try {
      controller.startImageStream((CameraImage image) {
        _processCameraImage(image);
      });
    } catch (e) {
      debugPrint('Error starting image stream: $e');
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('Error stopping image stream: $e');
      }
    }
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    final InputImageRotation? rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    if (Platform.isAndroid && image.planes.length > 1) {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
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

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting ||
        _isProcessingCapture ||
        _capturedFile != null ||
        !mounted) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastDetectionTime).inMilliseconds < 200) {
      return;
    }

    _isDetecting = true;
    _lastDetectionTime = now;

    try {
      if (_availableCameras.isEmpty ||
          _selectedCameraIndex >= _availableCameras.length) {
        return;
      }
      final camera = _availableCameras[_selectedCameraIndex];
      final inputImage = _inputImageFromCameraImage(image, camera);
      if (inputImage == null) return;

      final List<Face> faces = await _faceDetector.processImage(inputImage);
      if (!mounted || _capturedFile != null || _isProcessingCapture) return;

      if (faces.isEmpty) {
        if (_frameStatus != SmartFaceFrameStatus.noFace || _isFaceAligned) {
          setState(() {
            _frameStatus = SmartFaceFrameStatus.noFace;
            _isFaceAligned = false;
          });
        }
        return;
      }

      if (faces.length > 1) {
        if (_frameStatus != SmartFaceFrameStatus.multipleFaces ||
            _isFaceAligned) {
          setState(() {
            _frameStatus = SmartFaceFrameStatus.multipleFaces;
            _isFaceAligned = false;
          });
        }
        return;
      }

      final Face face = faces.first;
      final double rotY = face.headEulerAngleY ?? 0.0;
      final double rotZ = face.headEulerAngleZ ?? 0.0;
      final double rotX = face.headEulerAngleX ?? 0.0;

      if (rotY.abs() > 22.0 || rotZ.abs() > 22.0 || rotX.abs() > 24.0) {
        if (_frameStatus != SmartFaceFrameStatus.offCenter || _isFaceAligned) {
          setState(() {
            _frameStatus = SmartFaceFrameStatus.offCenter;
            _isFaceAligned = false;
          });
        }
        return;
      }

      final Rect faceBox = face.boundingBox;
      final double imgHeight = image.height.toDouble();
      final double faceCenterYRatio =
          ((faceBox.top + faceBox.bottom) / 2.0) / imgHeight;

      if (faceCenterYRatio < 0.20 || faceCenterYRatio > 0.75) {
        if (_frameStatus != SmartFaceFrameStatus.offCenter || _isFaceAligned) {
          setState(() {
            _frameStatus = SmartFaceFrameStatus.offCenter;
            _isFaceAligned = false;
          });
        }
        return;
      }

      if (_frameStatus != SmartFaceFrameStatus.aligned || !_isFaceAligned) {
        setState(() {
          _frameStatus = SmartFaceFrameStatus.aligned;
          _isFaceAligned = true;
        });
      }
    } catch (e) {
      debugPrint('Error processing camera stream: $e');
    } finally {
      _isDetecting = false;
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
        _isProcessingCapture ||
        !_isFaceAligned) {
      return;
    }

    setState(() {
      _isProcessingCapture = true;
    });

    try {
      await _stopImageStream();
      final XFile picture = await _controller!.takePicture();
      final File rawFile = File(picture.path);

      final inputImage = InputImage.fromFilePath(rawFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Wajah tidak terdeteksi. Posisikan wajah tepat di dalam lingkaran.',
          );
          setState(() {
            _frameStatus = SmartFaceFrameStatus.noFace;
            _isFaceAligned = false;
          });
          _startImageStream();
        }
        return;
      }

      if (faces.length > 1) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Terdeteksi lebih dari satu orang. Pastikan hanya ada 1 orang di frame.',
          );
          setState(() {
            _frameStatus = SmartFaceFrameStatus.multipleFaces;
            _isFaceAligned = false;
          });
          _startImageStream();
        }
        return;
      }

      final Face face = faces.first;
      final Rect faceBox = face.boundingBox;

      final double rotY = face.headEulerAngleY ?? 0.0;
      final double rotZ = face.headEulerAngleZ ?? 0.0;
      final double rotX = face.headEulerAngleX ?? 0.0;

      if (rotY.abs() > 22.0) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Wajah harus menghadap lurus ke depan. Jangan menoleh ke samping.',
          );
          setState(() {
            _frameStatus = SmartFaceFrameStatus.offCenter;
            _isFaceAligned = false;
          });
          _startImageStream();
        }
        return;
      }

      if (rotZ.abs() > 22.0) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Posisi kepala miring. Tegakkan kepala menghadap kamera.',
          );
          setState(() {
            _frameStatus = SmartFaceFrameStatus.offCenter;
            _isFaceAligned = false;
          });
          _startImageStream();
        }
        return;
      }

      if (rotX.abs() > 24.0) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Arahkan pandangan sejajar dengan kamera (tidak terlalu mendongak/menunduk).',
          );
          setState(() {
            _frameStatus = SmartFaceFrameStatus.offCenter;
            _isFaceAligned = false;
          });
          _startImageStream();
        }
        return;
      }

      final rawBytes = await rawFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(rawBytes);

      if (originalImage == null) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Gagal memproses gambar. Silakan coba lagi.',
          );
          _startImageStream();
        }
        return;
      }

      originalImage = img.bakeOrientation(originalImage);

      final int imgWidth = originalImage.width;
      final int imgHeight = originalImage.height;

      final double faceCenterYRatio =
          ((faceBox.top + faceBox.bottom) / 2.0) / imgHeight.toDouble();

      if (faceCenterYRatio < 0.20 || faceCenterYRatio > 0.75) {
        if (mounted) {
          showCustomSnackBar(
            context,
            'Posisikan wajah di bagian kepala siluet (bukan di dada).',
          );
          setState(() {
            _frameStatus = SmartFaceFrameStatus.offCenter;
            _isFaceAligned = false;
          });
          _startImageStream();
        }
        return;
      }

      final double faceDimension = math.max(faceBox.width, faceBox.height);
      final double faceCenterX = (faceBox.left + faceBox.right) / 2.0;
      final double faceCenterY = (faceBox.top + faceBox.bottom) / 2.0;

      final int cropSize = math.min(
        imgWidth,
        (faceDimension * 1.85).round().clamp(300, math.min(imgWidth, imgHeight)),
      );

      int cropX = (faceCenterX - (cropSize / 2.0)).round();
      int cropY = (faceCenterY - (cropSize * 0.46)).round();

      cropX = cropX.clamp(0, imgWidth - cropSize);
      cropY = cropY.clamp(0, imgHeight - cropSize);

      img.Image croppedImage = img.copyCrop(
        originalImage,
        x: cropX,
        y: cropY,
        width: cropSize,
        height: cropSize,
      );

      if (_isFrontCamera) {
        croppedImage = img.flipHorizontal(croppedImage);
      }

      img.Image resizedImage = img.copyResize(
        croppedImage,
        width: 720,
        height: 720,
        interpolation: img.Interpolation.linear,
      );

      final List<int> processedBytes = img.encodeJpg(resizedImage, quality: 85);

      final String finalPath =
          '${rawFile.parent.path}/profil_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File processedFile =
          await File(finalPath).writeAsBytes(processedBytes);

      try {
        if (await rawFile.exists()) {
          await rawFile.delete();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _capturedFile = processedFile;
          _isFaceAligned = true;
          _frameStatus = SmartFaceFrameStatus.aligned;
        });
      }
    } catch (e) {
      debugPrint('Error capturing face image: $e');
      if (mounted) {
        showCustomSnackBar(
          context,
          'Terjadi kendala saat memproses foto. Silakan coba lagi.',
        );
        _startImageStream();
      }
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
    _stopImageStream();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(),

            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 6.h),

                    _buildFaceViewfinderCard(),

                    SizedBox(height: 16.h),

                    _buildGuidanceCard(),
                  ],
                ),
              ),
            ),

            Container(
              color: Colors.transparent,
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
              child: _capturedFile == null
                  ? _buildShutterButton()
                  : _buildReviewControls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
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
            onPressed: () => Navigator.pop(context),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                color: const Color(0xFF0B3866),
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_capturedFile == null && _availableCameras.length > 1)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                Icons.flip_camera_ios_rounded,
                color: const Color(0xFF0B3866),
                size: 22.sp,
              ),
              onPressed: _switchCamera,
              tooltip: 'Ganti Kamera',
            ),
        ],
      ),
    );
  }

  String get _guidancePillText {
    switch (_frameStatus) {
      case SmartFaceFrameStatus.aligned:
        return 'Wajah pas, silakan ambil foto';
      case SmartFaceFrameStatus.offCenter:
        return 'Posisikan wajah di bagian kepala siluet';
      case SmartFaceFrameStatus.tooFar:
        return 'Dekatkan wajah Anda ke kamera';
      case SmartFaceFrameStatus.tooClose:
        return 'Jauhkan sedikit wajah Anda';
      case SmartFaceFrameStatus.multipleFaces:
        return 'Pastikan hanya ada 1 orang di frame';
      case SmartFaceFrameStatus.noFace:
        return 'Posisikan kepala & bahu sesuai siluet';
    }
  }

  Widget _buildFaceViewfinderCard() {
    final double cardWidth = 345.w;
    final double cardHeight = _capturedFile != null ? cardWidth : cardWidth * 1.18;

    return Center(
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: _capturedFile != null ? Colors.white : const Color(0xFF111C2D),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF002245).withValues(alpha: 0.08),
              blurRadius: 16.r,
              offset: Offset(0, 4.h),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.r),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_capturedFile == null &&
                  _controller != null &&
                  _controller!.value.isInitialized)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.previewSize?.height ?? cardWidth,
                    height: _controller!.value.previewSize?.width ?? cardHeight,
                    child: _isFrontCamera
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(math.pi),
                            child: CameraPreview(_controller!),
                          )
                        : CameraPreview(_controller!),
                  ),
                ),

              if (_capturedFile != null)
                Image.file(
                  _capturedFile!,
                  fit: BoxFit.cover,
                  width: cardWidth,
                  height: cardHeight,
                ),

              if (_capturedFile == null)
                IgnorePointer(
                  child: Center(
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        _isFaceAligned
                            ? const Color(0xFF10B981)
                            : (_frameStatus == SmartFaceFrameStatus.offCenter ||
                                    _frameStatus == SmartFaceFrameStatus.tooFar ||
                                    _frameStatus == SmartFaceFrameStatus.tooClose)
                                ? const Color(0xFFFD990F)
                                : Colors.white.withValues(alpha: 0.88),
                        BlendMode.srcIn,
                      ),
                      child: Transform.translate(
                        offset: Offset(0, 52.h),
                        child: Transform.scale(
                          scale: 1.18,
                          alignment: Alignment.bottomCenter,
                          child: SvgPicture.asset(
                            'assets/icons/frame.svg',
                            package: 'smart_id_extractor',
                            fit: BoxFit.contain,
                            width: cardWidth,
                            height: cardHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (_capturedFile == null)
                Positioned(
                  bottom: 12.h,
                  left: 12.w,
                  right: 12.w,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 6.h,
                      ),
                      decoration: BoxDecoration(
                        color: _isFaceAligned
                            ? const Color(0xFF10B981).withValues(alpha: 0.85)
                            : Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isFaceAligned
                                ? Icons.check_circle_rounded
                                : Icons.crop_free_rounded,
                            color: Colors.white,
                            size: 14.sp,
                          ),
                          SizedBox(width: 5.w),
                          Flexible(
                            child: Text(
                              _guidancePillText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5.sp,
                                fontFamily: 'Plus Jakarta Sans',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_isProcessingCapture)
                Container(
                  color: Colors.black.withValues(alpha: 0.40),
                  child: Center(
                    child: Container(
                      width: 68.r,
                      height: 68.r,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 28.r,
                          height: 28.r,
                          child: const CircularProgressIndicator(
                            color: Color(0xFFFD990F),
                            strokeWidth: 2.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuidanceCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: const Color(0xFFFD990F),
                size: 18.sp,
              ),
              SizedBox(width: 8.w),
              Text(
                'Panduan Pengambilan Foto Wajah',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  color: const Color(0xFF002245),
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _buildGuidelineItem('Posisikan kepala, telinga, leher, dan bahu sejajar dengan garis siluet.'),
          _buildGuidelineItem('Wajah wajib menghadap lurus ke depan kamera (tidak menoleh atau miring).'),
          _buildGuidelineItem('Pastikan pencahayaan cukup terang dan posisikan wajah di area kepala hingga garis siluet berubah hijau.'),
        ],
      ),
    );
  }

  Widget _buildGuidelineItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5.r,
            height: 5.r,
            margin: EdgeInsets.only(top: 5.h, right: 8.w),
            decoration: const BoxDecoration(
              color: Color(0xFFFD990F),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                color: const Color(0xFF43474F),
                fontSize: 11.sp,
                height: 1.35,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShutterButton() {
    final bool isEnabled = _isFaceAligned && !_isProcessingCapture;

    return Center(
      child: GestureDetector(
        onTap: isEnabled ? _takePictureAndVerify : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 72.w,
          height: 72.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isEnabled
                ? const Color(0xFFFD990F).withValues(alpha: 0.18)
                : const Color(0xFFE2E8F0).withValues(alpha: 0.50),
          ),
          padding: EdgeInsets.all(6.w),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled
                  ? const Color(0xFFFD990F)
                  : const Color(0xFFCBD5E1),
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFD990F).withValues(alpha: 0.40),
                        blurRadius: 14.r,
                        offset: Offset(0, 4.h),
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 28.sp,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewControls() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _capturedFile = null;
                  _frameStatus = SmartFaceFrameStatus.noFace;
                  _isFaceAligned = false;
                });
                _startImageStream();
              },
              icon: Icon(Icons.refresh_rounded,
                  size: 20.sp, color: const Color(0xFF0B3866)),
              label: Text(
                'Ulangi',
                style: TextStyle(
                  color: const Color(0xFF0B3866),
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0B3866), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_capturedFile != null) {
                  widget.onPhotoSaved?.call(_capturedFile!);
                  Navigator.pop(context, _capturedFile);
                }
              },
              icon: Icon(Icons.check_rounded, size: 20.sp, color: Colors.white),
              label: Text(
                'Simpan',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B3866),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
