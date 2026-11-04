## 1.0.0

### Major Features
- **Rebranding & Identity**: Renamed package to `smart_id_extractor` for intelligent, comprehensive document extraction (KTP, Kartu Keluarga, and Passports).
- **Kartu Keluarga (KK) OCR & Validation**:
  - Added `extractKartuKeluarga(File image, {KartuKeluargaValidationOptions? options})` to extract and validate Indonesian Family Cards (Kartu Keluarga).
  - Added configurable `KartuKeluargaValidationOptions` to enforce strict or relaxed verification rules:
    - Mandatory Nomor KK check (`requireNomorKk`) with 16-digit normalization.
    - Header detection (`requireHeaderTitle`: "KARTU KELUARGA").
    - Kepala Keluarga detection (`requireKepalaKeluarga`).
    - Table column detection (`requireTableHeaders`: NIK, Nama Lengkap, Jenis Kelamin, etc.).
    - Alamat block detection (`requireAlamat`).
    - Configurable minimum criteria match score (`minRequiredMatches`).
  - Added `KartuKeluargaModel` providing structured data (Nomor KK, Nama Kepala Keluarga, Alamat, RT/RW, Desa/Kelurahan, Kecamatan, Kabupaten/Kota, Provinsi, Kode Pos) along with validation confidence score and failure diagnostics.
- **Enhanced Live Camera Screen (`startKtpCamera`)**:
  - Real-time animated flexible frame overlay with smooth quadrilateral card corner interpolation.
  - Added `enableGalleryPicker` option (boolean) to show or hide the gallery button inside the camera screen.
  - Added `loadingColor` customizer for clean, minimalist loading indicator during image processing.
  - Improved error handling when users cancel gallery picking or dismiss the camera.
- **Passport MRZ Extraction**:
  - Built-in MRZ (Machine Readable Zone - TD3) parser with checksum verification for international passports.
- **Backward Compatibility**:
  - Added `typedef SmartExtractorPro = KtpExtractor;` and `typedef KtpKkExtractor = KtpExtractor;`.
  - Maintained `package:smart_id_extractor/ktp_extractor.dart` and `package:smart_id_extractor/ktp_kk_extractor.dart` exports so existing implementations continue to function seamlessly.

## 0.0.3

### Major Features
- **MRZ Passport Detection and Extraction**: Added passport scanning functionality with Machine Readable Zone (MRZ) support
  - `PassportModel` class for structured passport data extraction
  - MRZ parsing for document type, issuing country, passport number, nationality, dates, and personal information
  
### Multi-Language Support
- **Enhanced Text Recognition**: Added ML Kit language-specific dependencies for improved OCR accuracy
  - Chinese text recognition support (`text-recognition-chinese:16.0.0`)
  - Devanagari text recognition support (`text-recognition-devanagari:16.0.0`) 
  - Japanese text recognition support (`text-recognition-japanese:16.0.0`)
  - Korean text recognition support (`text-recognition-korean:16.0.0`)

### Improvements
- Enhanced extraction methods with new passport processing capabilities
- Updated example app UI with tab navigation (KTP, KK, Passport)
- Extended utility functions for better text processing and image handling

## 0.0.2

- Added Province and City extraction support.

## 0.0.1

- Initial release with KTP image cropping and OCR text recognition.
