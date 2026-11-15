// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'custom_snackbar.dart';

/// Status panduan wajah di dalam bingkai foto profil
enum SmartFaceFrameStatus {
  noFace,
  multipleFaces,
  tooFar,
  tooClose,
  offCenter,
  aligned,
}

/// Layar Kamera Foto Profil Berstandar:
/// - Desain konsisten persis SmartDocumentCameraScreen (Card Viewfinder rapi di tengah latar #F9F9FF)
/// - Preview kamera pas di dalam Card rounded tanpa garis potong hitam acak
/// - Panduan resmi di bawah kartu kamera dengan bullet point & ikon lampu ide
/// - Shutter button elegan dengan shadow soft amber
/// - Saat foto berhasil diambil: Card rapi tanpa radius border, tombol Ulangi & Simpan siap pakai
/// - Validasi ketat: Wajah manusia wajib menghadap lurus ke depan (Euler Angle Y/Z/X)
/// - Output konsisten: 720 × 720 px (1:1), JPEG Quality 85%, 100–300 KB
class SmartFaceCameraScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final ValueChanged<File>? onPhotoSaved;

  const SmartFaceCameraScreen({
    super.key,
    this.title = 'Uji Foto Profil',
    this.subtitle = 'Pastikan seluruh wajah masuk dalam lingkaran',
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
  bool _isProcessingCapture = false;

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
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
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
      final File rawFile = File(picture.path);

      // 1. Validasi Keberadaan Wajah
      final inputImage = InputImage.fromFilePath(rawFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        showCustomSnackBar(
          context,
          'Wajah tidak terdeteksi. Posisikan wajah Anda tepat di dalam lingkaran.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.noFace;
          _isFaceAligned = false;
        });
        return;
      }

      if (faces.length > 1) {
        showCustomSnackBar(
          context,
          'Terdeteksi lebih dari satu wajah. Pastikan hanya ada 1 orang di frame.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.multipleFaces;
          _isFaceAligned = false;
        });
        return;
      }

      final Face face = faces.first;
      final Rect faceBox = face.boundingBox;

      // 2. Validasi Ketat Sudut Rotasi Kepala (Wajib Menghadap Lurus ke Depan)
      final double rotY = face.headEulerAngleY ?? 0.0;
      final double rotZ = face.headEulerAngleZ ?? 0.0;
      final double rotX = face.headEulerAngleX ?? 0.0;

      if (rotY.abs() > 12.0) {
        showCustomSnackBar(
          context,
          'Wajah harus menghadap lurus ke depan. Jangan menoleh ke samping.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.offCenter;
          _isFaceAligned = false;
        });
        return;
      }

      if (rotZ.abs() > 14.0) {
        showCustomSnackBar(
          context,
          'Posisi kepala miring. Tegakkan kepala menghadap kamera.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.offCenter;
          _isFaceAligned = false;
        });
        return;
      }

      if (rotX.abs() > 16.0) {
        showCustomSnackBar(
          context,
          'Arahkan pandangan sejajar dengan kamera (tidak terlalu mendongak/menunduk).',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.offCenter;
          _isFaceAligned = false;
        });
        return;
      }

      // 3. Decode & Orientasi EXIF
      final rawBytes = await rawFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(rawBytes);

      if (originalImage == null) {
        showCustomSnackBar(
          context,
          'Gagal memproses gambar. Silakan coba lagi.',
        );
        return;
      }

      originalImage = img.bakeOrientation(originalImage);

      final int imgWidth = originalImage.width;
      final int imgHeight = originalImage.height;

      // 4. Validasi Proporsi Wajah
      final double minDimension = math.min(imgWidth, imgHeight).toDouble();
      final double faceDimension = math.max(faceBox.width, faceBox.height);
      final double faceRatio = faceDimension / minDimension;

      final double faceCenterX = (faceBox.left + faceBox.right) / 2.0;
      final double faceCenterY = (faceBox.top + faceBox.bottom) / 2.0;
      final double relOffsetX =
          (faceCenterX - (imgWidth / 2.0)).abs() / (imgWidth / 2.0);
      final double relOffsetY =
          (faceCenterY - (imgHeight * 0.44)).abs() / (imgHeight * 0.44);

      if (faceRatio < 0.20) {
        showCustomSnackBar(
          context,
          'Posisi wajah terlalu jauh. Dekatkan wajah Anda ke kamera.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.tooFar;
          _isFaceAligned = false;
        });
        return;
      }

      if (faceRatio > 0.88) {
        showCustomSnackBar(
          context,
          'Posisi wajah terlalu dekat. Jauhkan sedikit wajah Anda.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.tooClose;
          _isFaceAligned = false;
        });
        return;
      }

      if (relOffsetX > 0.38 || relOffsetY > 0.45) {
        showCustomSnackBar(
          context,
          'Posisikan wajah tepat di tengah lingkaran.',
        );
        setState(() {
          _frameStatus = SmartFaceFrameStatus.offCenter;
          _isFaceAligned = false;
        });
        return;
      }

      // 5. Potong Persegi 1:1 Berpusat pada Wajah
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

      // 6. Standarisasi Output: 720 × 720 px, JPEG Quality 85%
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

      setState(() {
        _capturedFile = processedFile;
        _isFaceAligned = true;
        _frameStatus = SmartFaceFrameStatus.aligned;
      });
    } catch (e) {
      debugPrint('Error capturing face image: $e');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top Bar Konsisten
            _buildTopBar(),

            // 2. Area Konten Tengah
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 6.h),

                    // 3. Viewfinder Card Elegan (Rapi, Konsisten dengan Dokumen)
                    _buildFaceViewfinderCard(),

                    SizedBox(height: 16.h),

                    // 4. Kartu Panduan Foto Profil (Sesuai Style Resmi)
                    _buildGuidanceCard(),
                  ],
                ),
              ),
            ),

            // 5. Bottom Action Bar
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

  Widget _buildFaceViewfinderCard() {
    final double cardWidth = 345.w;
    // Saat review hasil (1:1), buat card tepat persegi (1:1) agar foto memenuhi container tanpa sisa padding
    final double cardHeight = _capturedFile != null ? cardWidth : cardWidth * 1.15;

    return Center(
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: _capturedFile != null ? Colors.white : const Color(0xFF111C2D),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF002245).withOpacity(0.08),
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
              // 1. Live Camera Preview saat belum ada foto
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

              // 2. Hasil Foto (Memenuhi card 1:1 secara penuh, tajam, dan proporsional tanpa gap)
              if (_capturedFile != null)
                Image.file(
                  _capturedFile!,
                  fit: BoxFit.cover,
                  width: cardWidth,
                  height: cardHeight,
                ),

              // 3. Circle Face Frame Overlay (Hanya saat memotret)
              if (_capturedFile == null)
                CustomPaint(
                  size: Size.infinite,
                  painter: CleanCircleFaceFramePainter(
                    isAligned: _isFaceAligned,
                    status: _frameStatus,
                  ),
                ),

              // 4. Pill Petunjuk Bawah di dalam Card Viewfinder
              if (_capturedFile == null)
                Positioned(
                  bottom: 12.h,
                  left: 20.w,
                  right: 20.w,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 6.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.60),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.crop_free_rounded,
                            color: Colors.white,
                            size: 16.sp,
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'Posisikan wajah Anda tegak di dalam lingkaran',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5.sp,
                              fontFamily: 'Plus Jakarta Sans',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 5. Spinner saat memproses
              if (_isProcessingCapture)
                Container(
                  color: Colors.black.withOpacity(0.40),
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
          _buildGuidelineItem('Wajah wajib menghadap lurus ke depan kamera (tidak menoleh atau miring).'),
          _buildGuidelineItem('Pastikan pencahayaan cukup terang dan tidak membelakangi cahaya (backlight).'),
          _buildGuidelineItem('Posisikan wajah pas di dalam lingkaran hingga indikator berubah hijau.'),
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
    return Center(
      child: GestureDetector(
        onTap: _takePictureAndVerify,
        child: Container(
          width: 72.w,
          height: 72.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFD990F).withOpacity(0.18),
          ),
          padding: EdgeInsets.all(6.w),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFD990F),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFD990F).withOpacity(0.40),
                  blurRadius: 14.r,
                  offset: Offset(0, 4.h),
                ),
              ],
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
        // Tombol Ulangi
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
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 14.w),

        // Tombol Simpan
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: ElevatedButton.icon(
              onPressed: () {
                if (widget.onPhotoSaved != null) {
                  widget.onPhotoSaved!(_capturedFile!);
                }
                Navigator.pop(context, _capturedFile);
              },
              icon: const Icon(
                Icons.check_circle_outline_rounded,
                size: 20,
                color: Colors.white,
              ),
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
                backgroundColor: const Color(0xFFFD990F),
                elevation: 0,
                shadowColor: Colors.transparent,
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

/// Custom painter: Lingkaran hijau bersih dan 4 corner brackets presisi di dalam viewfinder
class CleanCircleFaceFramePainter extends CustomPainter {
  final bool isAligned;
  final SmartFaceFrameStatus status;

  CleanCircleFaceFramePainter({
    required this.isAligned,
    required this.status,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final Offset center = Offset(size.width / 2.0, size.height * 0.46);
    final double radius = size.width * 0.35;

    // 1. Scrim gelap tipis di luar lingkaran
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final circleHolePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final transparentHole = Path.combine(
      PathOperation.difference,
      backgroundPath,
      circleHolePath,
    );

    final scrimPaint = Paint()
      ..color = Colors.black.withOpacity(0.40)
      ..style = PaintingStyle.fill;
    canvas.drawPath(transparentHole, scrimPaint);

    // 2. Garis Lingkaran Hijau/Amber
    final Color circleColor = isAligned
        ? const Color(0xFF10B981)
        : (status == SmartFaceFrameStatus.offCenter ||
                status == SmartFaceFrameStatus.tooFar ||
                status == SmartFaceFrameStatus.tooClose)
            ? const Color(0xFFFD990F)
            : const Color(0xFF10B981);

    final circlePaint = Paint()
      ..color = circleColor
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, circlePaint);

    // 3. Empat Corner Brackets
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double boxSize = radius * 2.30;
    final Rect bracketRect = Rect.fromCenter(
      center: center,
      width: boxSize,
      height: boxSize,
    );
    const double armLength = 22.0;
    const double cornerRadius = 8.0;

    // Top-Left
    final tl = Path()
      ..moveTo(bracketRect.left, bracketRect.top + armLength)
      ..lineTo(bracketRect.left, bracketRect.top + cornerRadius)
      ..quadraticBezierTo(bracketRect.left, bracketRect.top,
          bracketRect.left + cornerRadius, bracketRect.top)
      ..lineTo(bracketRect.left + armLength, bracketRect.top);
    canvas.drawPath(tl, cornerPaint);

    // Top-Right
    final tr = Path()
      ..moveTo(bracketRect.right - armLength, bracketRect.top)
      ..lineTo(bracketRect.right - cornerRadius, bracketRect.top)
      ..quadraticBezierTo(bracketRect.right, bracketRect.top,
          bracketRect.right, bracketRect.top + cornerRadius)
      ..lineTo(bracketRect.right, bracketRect.top + armLength);
    canvas.drawPath(tr, cornerPaint);

    // Bottom-Left
    final bl = Path()
      ..moveTo(bracketRect.left, bracketRect.bottom - armLength)
      ..lineTo(bracketRect.left, bracketRect.bottom - cornerRadius)
      ..quadraticBezierTo(bracketRect.left, bracketRect.bottom,
          bracketRect.left + cornerRadius, bracketRect.bottom)
      ..lineTo(bracketRect.left + armLength, bracketRect.bottom);
    canvas.drawPath(bl, cornerPaint);

    // Bottom-Right
    final br = Path()
      ..moveTo(bracketRect.right - armLength, bracketRect.bottom)
      ..lineTo(bracketRect.right - cornerRadius, bracketRect.bottom)
      ..quadraticBezierTo(bracketRect.right, bracketRect.bottom,
          bracketRect.right, bracketRect.bottom - cornerRadius)
      ..lineTo(bracketRect.right, bracketRect.bottom - armLength);
    canvas.drawPath(br, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CleanCircleFaceFramePainter oldDelegate) {
    return oldDelegate.isAligned != isAligned || oldDelegate.status != status;
  }
}
