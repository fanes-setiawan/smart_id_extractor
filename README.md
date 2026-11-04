# smart_id_extractor

An intelligent, high-accuracy Flutter OCR and on-device machine learning library for extracting and validating Indonesian ID Cards (**KTP** - Kartu Tanda Penduduk), Indonesian Family Cards (**KK** - Kartu Keluarga), and International **Passports** (MRZ).

[![pub points](https://img.shields.io/pub/points/smart_id_extractor?color=2E8B57&label=pub%20points)](https://pub.dev/packages/smart_id_extractor)
[![pub package](https://img.shields.io/pub/v/smart_id_extractor.svg)](https://pub.dev/packages/smart_id_extractor)

---

## ✨ Features

- 🇮🇩 **KTP Extraction**: High-accuracy OCR parsing for NIK, Name, Place/Date of Birth, Gender, Address, RT/RW, Kelurahan/Desa, Kecamatan, Religion, Marital Status, Occupation, Nationality, Province, and City.
- 👨‍👩‍👧‍👦 **Kartu Keluarga (KK) Validation & Extraction**:
  - Automatically identifies whether an uploaded photo or document is a valid Indonesian Family Card (Kartu Keluarga).
  - Customizable validation rules: enforce mandatory Nomor KK (16 digits), header detection, Kepala Keluarga name, table structure, or address block.
  - Returns structured `KartuKeluargaModel` with validation confidence score, failure reason diagnostics, and key fields.
- 📷 **Smart Live Camera Screen**:
  - Real-time card boundary detection with smooth flexible animated overlay frame.
  - Customizable UI: toggle gallery picker (`enableGalleryPicker`), custom accent/loading colors (`loadingColor`), and real-time guidance text.
  - Automatic perspective crop using on-device machine learning model.
- 🛂 **Passport MRZ Extraction**:
  - Extracts Machine Readable Zone (MRZ - TD3 standard) data with check digit verification.
  - Extracts passport number, issuing country, nationality, surname, given names, date of birth, expiration date, and gender.
- ⚡ **Offline & Private**: Fully on-device processing using Google ML Kit and TensorFlow Lite without sending sensitive identity documents to third-party servers.

---

## 🚀 Getting Started

Add `smart_id_extractor` to your `pubspec.yaml`:

```yaml
dependencies:
  smart_id_extractor: ^1.0.0
```

or run:

```bash
flutter pub add smart_id_extractor
```

---

## ⚙️ Platform Setup

### 📱 Android

1. Ensure your `android/app/build.gradle` has `minSdkVersion` 21 or higher:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

2. Add camera and storage permissions in `android/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
```

3. (Optional) For multi-language OCR enhancement, add to `android/app/build.gradle`:

```groovy
dependencies {
    implementation 'com.google.mlkit:text-recognition-chinese:16.0.0'
    implementation 'com.google.mlkit:text-recognition-devanagari:16.0.0'
    implementation 'com.google.mlkit:text-recognition-japanese:16.0.0'
    implementation 'com.google.mlkit:text-recognition-korean:16.0.0'
}
```

---

### 🍏 iOS

1. Set iOS Deployment Target to **15.5.0** or newer in `ios/Podfile`:

```ruby
platform :ios, '15.5.0'

$iOSVersion = '15.5.0'

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings["EXCLUDED_ARCHS[sdk=*]"] = "armv7"
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = $iOSVersion
  end

  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      if Gem::Version.new($iOSVersion) > Gem::Version.new(config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'])
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = $iOSVersion
      end
    end
  end
end
```

2. Add camera and photo library usage descriptions in `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to scan identity documents.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app requires photo library access to select document images.</string>
```

---

## 📖 Usage Guide

### 1. Live Camera KTP Scanner

Launch the interactive scanner screen with real-time card guidance overlay and automatic cropping:

```dart
import 'package:flutter/material.dart';
import 'package:smart_id_extractor/smart_id_extractor.dart';

Future<void> scanKtpWithCamera(BuildContext context) async {
  KtpModel? ktpResult = await SmartExtractorPro.startKtpCamera(
    context,
    enableGalleryPicker: true,          // Allow user to select from gallery inside camera
    loadingColor: Colors.blueAccent,    // Custom loading indicator color
  );

  if (ktpResult != null) {
    print('NIK: ${ktpResult.nik}');
    print('Nama: ${ktpResult.name}');
    print('Alamat: ${ktpResult.address}');
    print('Provinsi: ${ktpResult.provinsi}');
    print('Kota/Kabupaten: ${ktpResult.kabupatenKota}');
  }
}
```

---

### 2. Extract from an Existing KTP Image File

If you already have a `File` (from an image picker or file system):

```dart
import 'dart:io';
import 'package:smart_id_extractor/smart_id_extractor.dart';

Future<void> extractFromImage(File imageFile) async {
  // 1. (Optional) Auto-crop card boundary
  File? croppedImage = await SmartExtractorPro.cropImageForKtp(imageFile);
  File fileToProcess = croppedImage ?? imageFile;

  // 2. Perform OCR extraction
  KtpModel ktp = await SmartExtractorPro.extractKtp(fileToProcess);

  print('NIK: ${ktp.nik}');
  print('Nama: ${ktp.name}');
  print('Tempat/Tgl Lahir: ${ktp.birthPlace}, ${ktp.birthDay}');
}
```

---

### 3. Kartu Keluarga (KK) Validation & Extraction

Validate whether an uploaded document is truly an Indonesian Family Card (Kartu Keluarga) and extract its key header metadata:

```dart
import 'dart:io';
import 'package:smart_id_extractor/smart_id_extractor.dart';

Future<void> processKartuKeluarga(File imageFile) async {
  // Define custom validation options:
  const options = KartuKeluargaValidationOptions(
    requireNomorKk: true,         // Wajib menemukan nomor KK valid (16 digit)
    requireHeaderTitle: true,     // Wajib ada kata "KARTU KELUARGA"
    requireKepalaKeluarga: false, // Opsional
    requireTableHeaders: true,    // Wajib ada kolom tabel KK (NIK, Nama, etc)
    requireAlamat: false,         // Opsional
    minRequiredMatches: 2,        // Minimal 2 kriteria terpenuhi
  );

  KartuKeluargaModel kkResult = await SmartExtractorPro.extractKartuKeluarga(
    imageFile,
    options: options,
  );

  if (kkResult.isLikelyKartuKeluarga) {
    print('✅ Valid Kartu Keluarga! (Confidence: ${(kkResult.confidenceScore * 100).toStringAsFixed(1)}%)');
    print('Nomor KK: ${kkResult.nomorKk}');
    print('Nama Kepala Keluarga: ${kkResult.namaKepalaKeluarga}');
    print('Alamat: ${kkResult.alamat}');
    print('RT/RW: ${kkResult.rtRw}');
    print('Desa/Kelurahan: ${kkResult.desaKelurahan}');
    print('Kecamatan: ${kkResult.kecamatan}');
    print('Kabupaten/Kota: ${kkResult.kabupatenKota}');
    print('Provinsi: ${kkResult.provinsi}');
  } else {
    print('❌ Dokumen bukan Kartu Keluarga yang valid.');
    print('Alasan: ${kkResult.reasons.join(', ')}');
  }
}
```

---

### 4. Passport MRZ Extraction

Extract Machine Readable Zone (MRZ) details from passport images:

```dart
import 'dart:io';
import 'package:smart_id_extractor/smart_id_extractor.dart';

Future<void> processPassport(File imageFile) async {
  PassportModel passport = await SmartExtractorPro.extractPassport(imageFile);

  print('Document Number: ${passport.docNumber}');
  print('Country: ${passport.country}');
  print('Nationality: ${passport.nationality}');
  print('Surname: ${passport.surNames}');
  print('Given Names: ${passport.givenNames}');
  print('Date of Birth: ${passport.birthDate}');
  print('Expiry Date: ${passport.expiryDate}');
  print('Gender: ${passport.gender}');
}
```

---

## 📊 Models Reference

### `KtpModel`
| Property | Type | Description |
| :--- | :--- | :--- |
| `nik` | `String?` | 16-digit National Identity Number |
| `name` | `String?` | Full name as stated on KTP |
| `birthPlace` | `String?` | Place of birth |
| `birthDay` | `String?` | Date of birth (DD-MM-YYYY) |
| `gender` | `String?` | LAKI-LAKI / PEREMPUAN |
| `address` | `String?` | Street address |
| `rtRw` | `String?` | RT and RW numbers |
| `kelurahanDesa` | `String?` | Kelurahan or Desa |
| `kecamatan` | `String?` | District (Kecamatan) |
| `religion` | `String?` | Stated religion |
| `maritalStatus` | `String?` | Marital status (KAWIN / BELUM KAWIN, etc.) |
| `occupation` | `String?` | Occupation |
| `nationality` | `String?` | WNI / WNA |
| `provinsi` | `String?` | Province |
| `kabupatenKota` | `String?` | City or Regency |

### `KartuKeluargaModel`
| Property | Type | Description |
| :--- | :--- | :--- |
| `isLikelyKartuKeluarga` | `bool` | `true` if document passes the configured validation |
| `confidenceScore` | `double` | Score between `0.0` and `1.0` |
| `reasons` | `List<String>` | Diagnostic reasons or validation failure explanations |
| `nomorKk` | `String?` | 16-digit Family Card Number (sanitized) |
| `namaKepalaKeluarga` | `String?` | Name of the head of family |
| `alamat` | `String?` | Family address |
| `rtRw` | `String?` | RT/RW info |
| `desaKelurahan` | `String?` | Village / Urban village |
| `kecamatan` | `String?` | District |
| `kabupatenKota` | `String?` | Regency or City |
| `provinsi` | `String?` | Province |
| `kodePos` | `String?` | Postal code |

### `PassportModel`
| Property | Type | Description |
| :--- | :--- | :--- |
| `docNumber` | `String?` | Passport document number |
| `country` | `String?` | 3-letter issuing country code (e.g. IDN) |
| `nationality` | `String?` | 3-letter nationality code |
| `surNames` | `String?` | Primary surname / family name |
| `givenNames` | `String?` | Given names |
| `birthDate` | `String?` | Date of birth (YYMMDD) |
| `expiryDate` | `String?` | Passport expiration date (YYMMDD) |
| `gender` | `String?` | M / F / < |

---

## 🤝 Backward Compatibility

If your project previously used `KtpExtractor` or `KtpKkExtractor`, you can continue using them seamlessly:

```dart
typedef SmartExtractorPro = KtpExtractor;
typedef KtpKkExtractor = KtpExtractor;
```

All import styles are supported:
- `import 'package:smart_id_extractor/smart_id_extractor.dart';` (recommended)
- `import 'package:smart_id_extractor/ktp_extractor.dart';`
- `import 'package:smart_id_extractor/ktp_kk_extractor.dart';`

---

## 📄 License & Attribution

- Developed and maintained by [Fanes Setiawan](https://github.com/fanes-setiawan).
- References and inspiration from [MNC Identifier OCR](https://pub.dev/packages/mnc_identifier_ocr).
- Issues and contributions: [GitHub Issues](https://github.com/fanes-setiawan/smart_id_extractor/issues).
