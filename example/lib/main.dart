import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_id_extractor/smart_id_extractor.dart';
import 'package:smart_id_extractor/utils/utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentExtractorApp();
  }
}

class DocumentExtractorApp extends StatelessWidget {
  const DocumentExtractorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Extractor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ImagePicker _imagePicker = ImagePicker();

  File? _ktpImage;
  File? _ktpPhoto;
  KtpModel? _ktpModel;
  bool _isProcessingKtp = false;

  File? _kkImage;
  KartuKeluargaValidationResult? _kkValidationResult;
  bool _requireNomorKk = true;
  bool _requireHeader = true;
  bool _requireKepalaKeluarga = false;
  bool _isProcessingKk = false;

  File? _suratSehatImage;
  SuratSehatValidationResult? _suratSehatValidationResult;
  bool _isProcessingSuratSehat = false;

  File? _passportImage;
  PassportModel? _passportModel;
  bool _isProcessingPassport = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Extractor'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF64748B),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.badge_outlined, size: 17),
                        SizedBox(width: 6),
                        Text('KTP'),
                      ],
                    ),
                  ),
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.family_restroom_rounded, size: 17),
                        SizedBox(width: 6),
                        Text('KK'),
                      ],
                    ),
                  ),
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.medical_services_outlined, size: 17),
                        SizedBox(width: 6),
                        Text('Surat Sehat'),
                      ],
                    ),
                  ),
                  Tab(
                    iconMargin: EdgeInsets.zero,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.flight_takeoff_rounded, size: 17),
                        SizedBox(width: 6),
                        Text('Passport'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildKtpTab(),
          _buildKkTab(),
          _buildSuratSehatTab(),
          _buildPassportTab(),
        ],
      ),
    );
  }

  Widget _buildKtpTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_ktpImage != null) ...[
          _buildKtpPreviews(
            ktpImageFile: _ktpImage!,
            photoFile: _ktpPhoto,
            onClear: () {
              setState(() {
                _ktpImage = null;
                _ktpPhoto = null;
                _ktpModel = null;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.camera_rounded,
                        color: Color(0xFF2563EB), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Live Camera Scanner',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFD990F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text(
                    'Smart Document Camera (Figma UI)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openSmartDocumentCamera(SmartDocumentType.ktp),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text(
                    'Auto-Capture (Otomatis Jepret)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openLiveKtpCamera(autoCapture: true),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text(
                    'Manual Shutter (Tekan Tombol)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openLiveKtpCamera(autoCapture: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_open_rounded,
                        color: Color(0xFF64748B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Unggah Gambar Dokumen',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18, color: Color(0xFF2563EB)),
                        label: const Text(
                          'Galeri',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        onPressed: () => _getImage(ImageSource.gallery, 'ktp'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_camera_outlined,
                            size: 18, color: Color(0xFF10B981)),
                        label: const Text(
                          'Kamera',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        onPressed: () => _getImage(ImageSource.camera, 'ktp'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.collections_outlined,
                            size: 18, color: Color(0xFF8B5CF6)),
                        label: const Text(
                          'Sample',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        onPressed: () => _getImageAsset('ktp'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isProcessingKtp) _buildLoadingIndicator('Mengekstrak data KTP...'),
        if (!_isProcessingKtp && _ktpModel != null) ...[
          const SizedBox(height: 16),
          _buildKtpResult(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildKkTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_kkImage != null) ...[
          _buildImagePreview(
            imageFile: _kkImage!,
            onClear: () {
              setState(() {
                _kkImage = null;
                _kkValidationResult = null;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 20, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kriteria Validasi Kartu Keluarga',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(color: Color(0xFFE2E8F0)),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Wajib Nomor KK (16 Digit)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Nomor KK 16 digit angka wajib terdeteksi',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  value: _requireNomorKk,
                  onChanged: (val) {
                    setState(() {
                      _requireNomorKk = val;
                    });
                  },
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Wajib Header "KARTU KELUARGA"',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Header KARTU KELUARGA wajib ditemukan',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  value: _requireHeader,
                  onChanged: (val) {
                    setState(() {
                      _requireHeader = val;
                    });
                  },
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Wajib Nama Kepala Keluarga',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Label kepala keluarga wajib terdeteksi',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  value: _requireKepalaKeluarga,
                  onChanged: (val) {
                    setState(() {
                      _requireKepalaKeluarga = val;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.upload_file_rounded,
                        color: Color(0xFF64748B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Pilih Foto Kartu Keluarga',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFD990F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text(
                    'Buka Kamera KK (Sesuai Figma)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openSmartDocumentCamera(SmartDocumentType.kartuKeluarga),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text('Galeri'),
                        onPressed: () => _getImage(ImageSource.gallery, 'kk'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: const Text('Kamera'),
                        onPressed: () => _getImage(ImageSource.camera, 'kk'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isProcessingKk)
          _buildLoadingIndicator('Memvalidasi Kartu Keluarga...'),
        if (!_isProcessingKk && _kkValidationResult != null) ...[
          const SizedBox(height: 16),
          _buildKkResult(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSuratSehatTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_suratSehatImage != null) ...[
          _buildImagePreview(
            imageFile: _suratSehatImage!,
            onClear: () {
              setState(() {
                _suratSehatImage = null;
                _suratSehatValidationResult = null;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.medical_services_rounded,
                        color: Color(0xFFFD990F), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Pindai Surat Keterangan Sehat (Figma UI)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFD990F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.document_scanner_rounded),
                  label: const Text(
                    'Buka Kamera Surat Sehat (Sesuai Figma)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () =>
                      _openSmartDocumentCamera(SmartDocumentType.suratSehat),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_rounded, size: 18),
                        label: const Text('Galeri'),
                        onPressed: () =>
                            _getImage(ImageSource.gallery, 'suratSehat'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_rounded, size: 18),
                        label: const Text('Kamera'),
                        onPressed: () =>
                            _getImage(ImageSource.camera, 'suratSehat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isProcessingSuratSehat)
          _buildLoadingIndicator('Memvalidasi Surat Keterangan Sehat...'),
        if (!_isProcessingSuratSehat && _suratSehatValidationResult != null) ...[
          const SizedBox(height: 16),
          _buildSuratSehatResult(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildPassportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_passportImage != null) ...[
          _buildImagePreview(
            imageFile: _passportImage!,
            onClear: () {
              setState(() {
                _passportImage = null;
                _passportModel = null;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.flight_takeoff_rounded,
                        color: Color(0xFF2563EB), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Pindai Passport (MRZ)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18, color: Color(0xFF2563EB)),
                        label: const Text(
                          'Galeri',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        onPressed: () =>
                            _getImage(ImageSource.gallery, 'passport'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.photo_camera_outlined,
                            size: 18, color: Color(0xFF10B981)),
                        label: const Text(
                          'Kamera',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        onPressed: () =>
                            _getImage(ImageSource.camera, 'passport'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.collections_outlined,
                            size: 18, color: Color(0xFF8B5CF6)),
                        label: const Text(
                          'Sample',
                          style: TextStyle(color: Color(0xFF0F172A)),
                        ),
                        onPressed: () => _getImageAsset('passport'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_isProcessingPassport)
          _buildLoadingIndicator('Mengekstrak data Passport...'),
        if (!_isProcessingPassport && _passportModel != null) ...[
          const SizedBox(height: 16),
          _buildPassportResult(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildKtpPreviews({
    required File ktpImageFile,
    File? photoFile,
    required VoidCallback onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Foto KTP Utuh (Hasil Crop)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 18, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Text(
                          '1. Hasil Crop KTP',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Color(0xFF64748B)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onClear,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      ktpImageFile,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 2. Foto Wajah KTP (Hasil Crop Profil)
        if (photoFile != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.face_rounded,
                          size: 18, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '2. Hasil Crop Pasfoto (Foto Profil)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Preview Kotak Foto Beradius
                      Container(
                        width: 100,
                        height: 130,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF10B981), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            photoFile,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Info Penggunaan
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Siap untuk Foto Profil',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Foto wajah berhasil dipotong otomatis dari area pasfoto e-KTP dengan orientasi tegak dan siap diunggah ke sistem akun/profil.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF475569),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePreview({
    required File imageFile,
    required VoidCallback onClear,
  }) {
    return Stack(
      children: [
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              imageFile,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Text('Gagal menampilkan gambar'),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKtpResult() {
    final model = _ktpModel!;
    final hasNik = model.nik != null && model.nik!.length == 16;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined,
                    color: Color(0xFF2563EB), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Informasi KTP',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasNik
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hasNik
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                  child: Text(
                    hasNik ? 'NIK Valid' : 'NIK Belum Lengkap',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasNik
                          ? const Color(0xFF047857)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFE2E8F0)),
            _buildDetailRow('NIK', model.nik, isBold: true),
            _buildDetailRow('Nama', model.name),
            _buildDetailRow('Tempat Lahir', model.placeBirth),
            _buildDetailRow('Tanggal Lahir', model.birthDay),
            _buildDetailRow('Jenis Kelamin', model.gender),
            _buildDetailRow('Alamat', model.address),
            _buildDetailRow(
                'RT / RW',
                (model.rt != null || model.rw != null)
                    ? '${model.rt ?? '-'} / ${model.rw ?? '-'}'
                    : null),
            _buildDetailRow('Kel / Desa', model.subDistrict),
            _buildDetailRow('Kecamatan', model.district),
            _buildDetailRow('Kabupaten / Kota', model.city),
            _buildDetailRow('Provinsi', model.province),
            _buildDetailRow('Agama', model.religion),
            _buildDetailRow('Status Kawin', model.marital),
            _buildDetailRow('Pekerjaan', model.occupation),
            _buildDetailRow('Kewarganegaraan', model.nationality),
            _buildDetailRow('Berlaku Hingga', model.validUntil),
          ],
        ),
      ),
    );
  }

  Widget _buildKkResult() {
    final result = _kkValidationResult!;
    final isValid = result.isValid;
    final model = result.model;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isValid ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isValid ? Icons.check_circle_rounded : Icons.cancel_outlined,
                color:
                    isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isValid
                          ? 'DOKUMEN VALID KARTU KELUARGA'
                          : 'BUKAN KARTU KELUARGA / TIDAK VALID',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isValid
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tingkat Keyakinan: ${(result.confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (result.nomorKk != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'No. KK: ${result.nomorKk}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (result.missingRequirements.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Kriteria yang belum terpenuhi:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final item in result.missingRequirements)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      '• $item',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (model != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.description_outlined,
                          color: Color(0xFF2563EB), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Detail Kartu Keluarga',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE2E8F0)),
                  _buildDetailRow('No. KK', model.nomorKk, isBold: true),
                  _buildDetailRow('Kepala Keluarga', model.namaKepalaKeluarga),
                  _buildDetailRow('Alamat', model.alamat),
                  _buildDetailRow('RT / RW', model.rtRw),
                  _buildDetailRow('Desa / Kelurahan', model.desaKelurahan),
                  _buildDetailRow('Kecamatan', model.kecamatan),
                  _buildDetailRow('Kabupaten / Kota', model.kabupatenKota),
                  _buildDetailRow('Provinsi', model.provinsi),
                  _buildDetailRow('Kode Pos', model.kodePos),
                  if (model.anggotaKeluarga.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Anggota Keluarga (${model.anggotaKeluarga.length} orang)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < model.anggotaKeluarga.length; i++)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. ${model.anggotaKeluarga[i].nama ?? '-'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'NIK: ${model.anggotaKeluarga[i].nik ?? '-'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            if (model.anggotaKeluarga[i].jenisKelamin != null)
                              Text(
                                'Jenis Kelamin: ${model.anggotaKeluarga[i].jenisKelamin}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            if (model.anggotaKeluarga[i].hubungan != null)
                              Text(
                                'Hubungan: ${model.anggotaKeluarga[i].hubungan}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF475569),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSuratSehatResult() {
    final result = _suratSehatValidationResult!;
    final isValid = result.isValid;
    final model = result.model;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isValid ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isValid ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isValid ? Icons.check_circle_rounded : Icons.cancel_outlined,
                color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isValid
                          ? 'DOKUMEN VALID SURAT KETERANGAN SEHAT'
                          : 'BUKAN SURAT SEHAT / TIDAK VALID',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isValid ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tingkat Keyakinan: ${(result.confidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (model?.nama != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Nama Pasien: ${model?.nama}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (result.missingRequirements.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Color(0xFFD97706), size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Kriteria yang belum terpenuhi:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final item in result.missingRequirements)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      '• $item',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF78350F),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (model != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.health_and_safety_rounded,
                          color: Color(0xFFFD990F), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Data Hasil Pemeriksaan Kesehatan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE2E8F0)),
                  _buildDetailRow('Fasilitas Kesehatan', model.namaFaskes, isBold: true),
                  _buildDetailRow('Nama Pasien', model.nama, isBold: true),
                  _buildDetailRow('NIK', model.nik),
                  _buildDetailRow('Umur', model.umur),
                  _buildDetailRow('Jenis Kelamin', model.jenisKelamin),
                  _buildDetailRow('Alamat', model.alamat),
                  _buildDetailRow('Tinggi Badan', model.tinggiBadan),
                  _buildDetailRow('Berat Badan', model.beratBadan),
                  _buildDetailRow('Tekanan Darah (Tensi)', model.tekananDarah),
                  _buildDetailRow('Golongan Darah', model.golonganDarah),
                  _buildDetailRow('Buta Warna', model.butaWarna),
                  _buildDetailRow('Kesimpulan', model.kesimpulan, isBold: true),
                  _buildDetailRow('Dokter Pemeriksa', model.namaDokter),
                  _buildDetailRow('SIP / NIP Dokter', model.nomorSip),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPassportResult() {
    final model = _passportModel!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.flight_takeoff_rounded,
                    color: Color(0xFF2563EB), size: 20),
                SizedBox(width: 8),
                Text(
                  'Informasi Passport',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFE2E8F0)),
            _buildDetailRow('Document Type', model.documentType),
            _buildDetailRow('Issuing Country', model.issuingCountry),
            _buildDetailRow('Surname', model.surname),
            _buildDetailRow('Given Names', model.givenNames),
            _buildDetailRow('Passport Number', model.passportNumber,
                isBold: true),
            _buildDetailRow('Nationality', model.nationality),
            _buildDetailRow('Birth Date', model.birthDate),
            _buildDetailRow('Gender', model.gender),
            _buildDetailRow('Expiry Date', model.expiryDate),
            _buildDetailRow('Personal Number', model.personalNumber),
            const SizedBox(height: 12),
            const Text(
              'MRZ (Machine Readable Zone):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.mrz1 ?? '-',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model.mrz2 ?? '-',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF38BDF8),
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

  Widget _buildDetailRow(String label, String? value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLiveKtpCamera({bool autoCapture = true}) async {
    final KtpCameraResult? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KtpCameraScreen(
          autoCapture: autoCapture,
          title: autoCapture ? 'Auto-Capture' : 'Manual Shutter',
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _ktpImage = result.imageFile;
        _ktpPhoto = result.photoFile;
        _ktpModel = result.model;
      });
    }
  }

  Future<void> _openSmartDocumentCamera(SmartDocumentType type) async {
    final SmartDocumentResult? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmartDocumentCameraScreen(
          documentType: type,
          showSubmitButton: true,
          enableGallery: true,
          kkOptions: KartuKeluargaValidationOptions(
            requireNomorKk: _requireNomorKk,
            requireHeader: _requireHeader,
            requireKepalaKeluarga: _requireKepalaKeluarga,
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        switch (type) {
          case SmartDocumentType.ktp:
            _ktpImage = result.imageFile;
            _ktpPhoto = result.ktpPhotoFile;
            _ktpModel = result.ktpModel;
            break;
          case SmartDocumentType.kartuKeluarga:
            _kkImage = result.imageFile;
            _kkValidationResult = result.kkValidation;
            break;
          case SmartDocumentType.suratSehat:
            _suratSehatImage = result.imageFile;
            _suratSehatValidationResult = result.suratSehatValidation;
            break;
        }
      });
    }
  }

  Future<void> _getImage(ImageSource source, String documentType) async {
    if (documentType == 'ktp') {
      setState(() {
        _ktpImage = null;
        _ktpModel = null;
        _isProcessingKtp = true;
      });
    } else if (documentType == 'kk') {
      setState(() {
        _kkImage = null;
        _kkValidationResult = null;
        _isProcessingKk = true;
      });
    } else if (documentType == 'suratSehat') {
      setState(() {
        _suratSehatImage = null;
        _suratSehatValidationResult = null;
        _isProcessingSuratSehat = true;
      });
    } else {
      setState(() {
        _passportImage = null;
        _passportModel = null;
        _isProcessingPassport = true;
      });
    }

    final pickedFile = await _imagePicker.pickImage(
      source: source,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 98,
    );
    if (pickedFile != null) {
      _processFile(pickedFile.path, documentType);
    } else {
      setState(() {
        _isProcessingKtp = false;
        _isProcessingKk = false;
        _isProcessingSuratSehat = false;
        _isProcessingPassport = false;
      });
    }
  }

  Future<void> _getImageAsset(String documentType) async {
    List<String> assets = [];
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      assets = manifest.listAssets();
    } catch (_) {
      try {
        final manifestContent =
            await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifestMap = json.decode(manifestContent);
        assets = manifestMap.keys.toList();
      } catch (_) {}
    }

    final filteredAssets = assets
        .where((String key) => key.contains('images/'))
        .where((String key) =>
            key.contains('.jpg') ||
            key.contains('.jpeg') ||
            key.contains('.png') ||
            key.contains('.webp'))
        .toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final matchingAssets = filteredAssets.where((path) {
          final lower = path.toLowerCase();
          if (documentType == 'ktp') {
            return lower.contains('ktp') || lower.contains('3a1c67e8');
          } else {
            return lower.contains('passport');
          }
        }).toList();

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pilih Sample ${documentType.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.65,
                  ),
                  child: matchingAssets.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Tidak ada gambar sample',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final path in matchingAssets)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () async {
                                      Navigator.of(dialogContext).pop();
                                      final assetPath =
                                          await getAssetPath(path);
                                      if (mounted) {
                                        setState(() {
                                          if (documentType == 'ktp') {
                                            _isProcessingKtp = true;
                                          } else {
                                            _isProcessingPassport = true;
                                          }
                                        });
                                        _processFile(assetPath, documentType);
                                      }
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(path),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processFile(String path, String documentType) async {
    final originalFile = File(path);

    if (documentType == 'ktp') {
      final cropped = await KtpExtractor.cropImageForKtp(originalFile);
      KtpModel model = await KtpExtractor.extractKtp(cropped ?? originalFile);

      if (model.nik == null && cropped != null) {
        final fallbackModel = await KtpExtractor.extractKtp(originalFile);
        if (fallbackModel.nik != null) {
          model = fallbackModel;
          _ktpImage = originalFile;
        } else {
          _ktpImage = cropped;
        }
      } else {
        _ktpImage = cropped ?? originalFile;
      }

      if (_ktpImage != null) {
        _ktpPhoto = await KtpExtractor.cropKtpPhotoFile(_ktpImage!);
      }

      _ktpModel = model;
      _isProcessingKtp = false;
    } else if (documentType == 'kk') {
      _kkImage = originalFile;
      final options = KartuKeluargaValidationOptions(
        requireNomorKk: _requireNomorKk,
        requireHeader: _requireHeader,
        requireKepalaKeluarga: _requireKepalaKeluarga,
      );
      _kkValidationResult = await KtpExtractor.validateKartuKeluarga(
        originalFile,
        options: options,
      );
      _isProcessingKk = false;
    } else if (documentType == 'suratSehat') {
      _suratSehatImage = originalFile;
      _suratSehatValidationResult = await KtpExtractor.validateSuratSehat(
        originalFile,
      );
      _isProcessingSuratSehat = false;
    } else {
      final cropped = await KtpExtractor.cropImageForPassport(originalFile);
      PassportModel model =
          await KtpExtractor.extractPassport(cropped ?? originalFile);

      if (model.passportNumber == null && cropped != null) {
        final fallbackModel = await KtpExtractor.extractPassport(originalFile);
        if (fallbackModel.passportNumber != null) {
          model = fallbackModel;
          _passportImage = originalFile;
        } else {
          _passportImage = cropped;
        }
      } else {
        _passportImage = cropped ?? originalFile;
      }

      _passportModel = model;
      _isProcessingPassport = false;
    }

    if (mounted) {
      setState(() {});
    }
  }
}
