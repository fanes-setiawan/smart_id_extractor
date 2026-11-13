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
/// - Frame lingkaran wajah presisi dengan 4 corner brackets
/// - Deteksi keberadaan wajah manusia & anti-blur
/// - Output konsisten: Resolusi 720 × 720 px (1:1), JPEG Quality 85%, ukuran 100–300 KB
/// - Standalone & aman tanpa dependensi ScreenUtil eksternal
class SmartFaceCameraScreen extends StatelessWidget {
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
  String _guideTitle = 'Posisikan wajah Anda di dalam lingkaran';
  String _guideSubtitle = 'Pastikan wajah terlihat jelas di dalam lingkaran.';
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

  /// Memproses jepretan, memvalidasi keberadaan wajah manusia,
  /// melakukan smart 1:1 square crop terpusat di wajah, lalu me-resize ke 720×720 @ 85% JPEG.
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

      // 1. Validasi Keberadaan Wajah Menggunakan Google ML Kit
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
          _guideTitle = 'Wajah tidak terdeteksi di dalam lingkaran';
          _guideSubtitle = 'Posisikan wajah menghadap langsung ke kamera.';
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
          _guideTitle = 'Terdeteksi lebih dari 1 wajah';
          _guideSubtitle = 'Pastikan hanya wajah Anda yang terlihat.';
        });
        return;
      }

      final Face face = faces.first;
      final Rect faceBox = face.boundingBox;

      // 2. Decode raw image & orientasikan sesuai EXIF
      final rawBytes = await rawFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(rawBytes);

      if (originalImage == null) {
        showCustomSnackBar(
          context,
          'Gagal memproses gambar. Silakan coba lagi.',
        );
        return;
      }

      // Pastikan rotasi gambar tegak sesuai EXIF kamera
      originalImage = img.bakeOrientation(originalImage);

      final int imgWidth = originalImage.width;
      final int imgHeight = originalImage.height;

      // 3. Validasi Proporsi Wajah (Anti-terlalu jauh / terlalu dekat)
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
          _guideTitle = 'Dekatkan wajah Anda ke kamera';
          _guideSubtitle = 'Wajah harus mengisi area lingkaran dengan pas.';
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
          _guideTitle = 'Jauhkan sedikit wajah Anda dari kamera';
          _guideSubtitle = 'Beri sedikit ruang antara wajah dan tepi bingkai.';
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
          _guideTitle = 'Posisikan wajah tepat di tengah';
          _guideSubtitle = 'Sejajarkan wajah dengan lingkaran hijau.';
        });
        return;
      }

      // 4. Potong Persegi 1:1 Berpusat pada Wajah
      // Menghitung crop box persegi berpusat pada titik tengah wajah
      final int cropSize = math.min(
        imgWidth,
        (faceDimension * 1.85).round().clamp(300, math.min(imgWidth, imgHeight)),
      );

      int cropX = (faceCenterX - (cropSize / 2.0)).round();
      // Berikan ruang sedikit lebih banyak di atas kepala agar proporsional
      int cropY = (faceCenterY - (cropSize * 0.46)).round();

      // Pastikan koordinat crop tidak keluar batas gambar
      cropX = cropX.clamp(0, imgWidth - cropSize);
      cropY = cropY.clamp(0, imgHeight - cropSize);

      img.Image croppedImage = img.copyCrop(
        originalImage,
        x: cropX,
        y: cropY,
        width: cropSize,
        height: cropSize,
      );

      // 5. Standarisasi Output: 720 × 720 px, Aspect Ratio 1:1
      img.Image resizedImage = img.copyResize(
        croppedImage,
        width: 720,
        height: 720,
        interpolation: img.Interpolation.linear,
      );

      // 6. Encode JPEG dengan Quality 85% (Estimasi Ukuran: 100 - 300 KB)
      final List<int> processedBytes = img.encodeJpg(resizedImage, quality: 85);

      final String finalPath =
          '${rawFile.parent.path}/profil_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File processedFile = await File(finalPath).writeAsBytes(processedBytes);

      // Hapus file temporary mentahan
      try {
        if (await rawFile.exists()) {
          await rawFile.delete();
        }
      } catch (_) {}

      // Sukses dan terverifikasi
      setState(() {
        _capturedFile = processedFile;
        _isFaceAligned = true;
        _frameStatus = SmartFaceFrameStatus.aligned;
        _guideTitle = 'Posisi kepala dan wajah sudah sesuai!';
        _guideSubtitle = 'Pastikan wajah terlihat jelas di dalam lingkaran.';
      });
    } catch (e) {
      debugPrint('Error capturing & processing face image: $e');
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
                      // Camera Preview atau Hasil Jepretan
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

                      // Circle Face Frame Overlay dengan 4 Corner Brackets
                      CustomPaint(
                        size: Size.infinite,
                        painter: CircleFaceFrameOverlayPainter(
                          isAligned: _isFaceAligned,
                          status: _frameStatus,
                          hasPhoto: _capturedFile != null,
                        ),
                      ),

                      // Top Guidance Banner (Hijau saat pas, Navy saat mencari)
                      Positioned(
                        top: 14.h,
                        left: 16.w,
                        right: 16.w,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 10.h,
                          ),
                          decoration: BoxDecoration(
                            color: _isFaceAligned
                                ? const Color(0xFF059669).withOpacity(0.95)
                                : const Color(0xFF0F172A).withOpacity(0.90),
                            borderRadius: BorderRadius.circular(16.r),
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
                              Container(
                                width: 28.w,
                                height: 28.w,
                                decoration: BoxDecoration(
                                  color: _isFaceAligned
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFFD990F),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isFaceAligned
                                      ? Icons.check_rounded
                                      : Icons.face_retouching_natural_rounded,
                                  color: Colors.white,
                                  size: 18.sp,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _guideTitle,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.sp,
                                        fontFamily: 'PlusJakartaSans',
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      _guideSubtitle,
                                      style: TextStyle(
                                        color: const Color(0xFFE2E8F0),
                                        fontSize: 11.sp,
                                        fontFamily: 'PlusJakartaSans',
                                        fontWeight: FontWeight.w400,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Pill Petunjuk di Bawah Frame
                      Positioned(
                        bottom: 22.h,
                        left: 40.w,
                        right: 40.w,
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 8.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(24.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.crop_free_rounded,
                                  color: Colors.white,
                                  size: 20.sp,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  'Pastikan seluruh wajah\nmasuk dalam lingkaran',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.sp,
                                    fontFamily: 'PlusJakartaSans',
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
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
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 18.h),
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
                      'Menyelaraskan foto 720 × 720 px...',
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
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFD990F),
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
        // Tombol Ulangi
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _capturedFile = null;
                  _frameStatus = SmartFaceFrameStatus.noFace;
                  _guideTitle = 'Posisikan wajah Anda di dalam lingkaran';
                  _guideSubtitle =
                      'Pastikan wajah terlihat jelas di dalam lingkaran.';
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

        // Tombol Simpan (Disabled jika wajah belum sesuai)
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

/// Custom painter: Lingkaran hijau presisi + 4 Corner Bracket Sudut
class CircleFaceFrameOverlayPainter extends CustomPainter {
  final bool isAligned;
  final SmartFaceFrameStatus status;
  final bool hasPhoto;

  CircleFaceFrameOverlayPainter({
    required this.isAligned,
    required this.status,
    required this.hasPhoto,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final double circleDiameter = size.width * 0.68;
    final Offset circleCenter = Offset(size.width / 2.0, size.height * 0.44);
    final Rect circleRect = Rect.fromCircle(
      center: circleCenter,
      radius: circleDiameter / 2.0,
    );

    // 1. Scrim gelap dengan lubang lingkaran
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final circleHolePath = Path()..addOval(circleRect);
    final transparentHolePath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      circleHolePath,
    );

    final scrimPaint = Paint()
      ..color = Colors.black.withOpacity(hasPhoto ? 0.20 : 0.65)
      ..style = PaintingStyle.fill;
    canvas.drawPath(transparentHolePath, scrimPaint);

    // 2. Garis Lingkaran Hijau/Amber
    final Color circleColor = isAligned
        ? const Color(0xFF10B981) // Hijau Emerald
        : (status == SmartFaceFrameStatus.offCenter ||
                status == SmartFaceFrameStatus.tooFar ||
                status == SmartFaceFrameStatus.tooClose)
            ? const Color(0xFFFD990F) // Amber
            : const Color(0xFF10B981).withOpacity(0.90);

    final circlePaint = Paint()
      ..color = circleColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(circleCenter, circleDiameter / 2.0, circlePaint);

    // 3. Empat Corner Brackets Sudut (Putih) di sekeliling lingkaran
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double bracketBoxSize = circleDiameter * 1.34;
    final Rect bracketRect = Rect.fromCenter(
      center: circleCenter,
      width: bracketBoxSize,
      height: bracketBoxSize,
    );
    const double armLength = 26.0;
    const double cornerRadius = 10.0;

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
  bool shouldRepaint(covariant CircleFaceFrameOverlayPainter oldDelegate) {
    return oldDelegate.isAligned != isAligned ||
        oldDelegate.status != status ||
        oldDelegate.hasPhoto != hasPhoto;
  }
}
