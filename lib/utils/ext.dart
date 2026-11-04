import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:string_similarity/string_similarity.dart';

extension TextLineExt on RecognizedText {
  static const List<String> _knownLabels = [
    'nik',
    'nama',
    'tempat',
    'tgl',
    'lahir',
    'tempat/tgl',
    'tempat/tgl lahir',
    'tempattgl',
    'tempat tgl lahir',
    'jenis',
    'kelamin',
    'jenis kelamin',
    'alamat',
    'rtrw',
    'rt/rw',
    'rt',
    'rw',
    'keldesa',
    'kel/desa',
    'kelurahan',
    'desa',
    'kecamatan',
    'kecamalan',
    'kec',
    'agama',
    'status',
    'perkawinan',
    'status perkawinan',
    'pekerjaan',
    'pekeriaan',
    'kewarganegaraan',
    'kewarga negaraan',
    'kewarga',
    'berlaku',
    'hingga',
    'berlaku hingga',
    'gol',
    'darah',
    'gol. darah',
    'gol darah',
  ];

  static bool _isPureLabel(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(':', '')
        .replaceAll('/', '')
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .trim();
    if (_knownLabels.any((l) => l.replaceAll(RegExp(r'[\/\.\-\s]'), '') == cleaned)) {
      return true;
    }
    return false;
  }

  String? findAndClean(TextLine line, String key) {
    // 1. Coba bersihkan jika key dan value berada di TextLine yang sama
    if (line.elements.length > key.split(" ").length) {
      final cleaned = line.text.cleanse(key);
      if (cleaned.isNotEmpty && !_isPureLabel(cleaned)) {
        return cleaned;
      }
    }
    // 2. Cari TextLine di baris yang sama persis (inline ke kanan)
    final inlineLine = findInline(line);
    if (inlineLine != null) {
      final cleaned = inlineLine.text.cleanse(key);
      if (cleaned.isNotEmpty && !_isPureLabel(cleaned)) {
        return cleaned;
      }
    }
    // 3. Fallback pembersihan teks baris
    final cleaned = line.text.cleanse(key);
    return _isPureLabel(cleaned) ? null : cleaned;
  }

  TextLine? findInline(TextLine line) {
    final double top = line.boundingBox.top;
    final double bottom = line.boundingBox.bottom;
    final double height = bottom - top;
    // Gunakan toleransi vertikal yang fleksibel terhadap kemiringan/variasi baris KTP (~40% tinggi teks)
    final double verticalTolerance = (height * 0.40).clamp(4.0, 14.0);
    final double minLeft = line.boundingBox.left + 5;

    final List<TextLine> result = [];

    for (final block in blocks) {
      for (final textLine in block.lines) {
        final centerY =
            (textLine.boundingBox.bottom + textLine.boundingBox.top) / 2;
        final lineCenterY = (top + bottom) / 2;

        if ((centerY - lineCenterY).abs() <= verticalTolerance &&
            textLine.text != line.text &&
            textLine.boundingBox.left >= minLeft &&
            !_isPureLabel(textLine.text)) {
          result.add(textLine);
        }
      }
    }

    if (result.isEmpty) return null;

    // Ambil textLine paling dekat ke kanan label
    return result.reduce((a, b) {
      final leftA = a.boundingBox.left;
      final leftB = b.boundingBox.left;
      return leftA < leftB ? a : b;
    });
  }
}

extension StringExtension on String {
  String filterNumbersOnly() {
    final String corrected = replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll('B', '8')
        .replaceAll('b', '6')
        .replaceAll('S', '5')
        .replaceAll('Z', '2')
        .replaceAll('z', '2')
        .replaceAll('D', '0')
        .replaceAll('A', '4')
        .replaceAll('e', '2')
        .replaceAll('L', '6')
        .replaceAll('T', '7');

    return corrected.removeAlphabet();
  }

  String removeAlphabet() {
    return replaceAll(RegExp(r'[^0-9]'), '');
  }

  String cleanse(String text, {bool ignoreCase = true}) {
    String cleaned = this;

    // Replace text with an empty string, respecting case sensitivity
    if (ignoreCase) {
      cleaned = cleaned.replaceAll(
          RegExp(RegExp.escape(text), caseSensitive: false), '');
    } else {
      cleaned = cleaned.replaceAll(text, '');
    }

    // Remove colons, equal signs, and trim whitespace
    cleaned = cleaned.replaceAll(':', '').replaceAll('=', '').trim();
    if (cleaned.startsWith('-')) {
      cleaned = cleaned.substring(1).trim();
    }

    return cleaned;
  }

  String filterNumberToAlphabet() {
    return replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('4', 'A')
        .replaceAll('5', 'S')
        .replaceAll('7', 'T')
        .replaceAll('8', 'B');
  }

  String filterAlphabetToNumber() {
    return replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll('B', '8')
        .replaceAll('b', '6')
        .replaceAll('S', '5')
        .replaceAll('Z', '2')
        .replaceAll('z', '2')
        .replaceAll('D', '0')
        .replaceAll('A', '4')
        .replaceAll('e', '2')
        .replaceAll('L', '6')
        .replaceAll('T', '7');
  }

  String? correctWord(List<String> expectedWords, {bool safetyBack = false}) {
    /// define zero initial and increase when add similar from word
    /// this is same with confidence in AI
    double highestSimilarity = 0.0;
    String closestWord = this;

    for (final word in expectedWords) {
      final double similarity = similarityTo(word);
      if (similarity > highestSimilarity) {
        highestSimilarity = similarity;
        closestWord = word;
      }
    }

    if (!safetyBack && highestSimilarity < 0.5) {
      return null;
    }
    return closestWord;
  }

  String cleanMrzText() {
    return toUpperCase()
        .replaceAll('«', '<')
        .replaceAll('»', '<')
        .replaceAll('‹', '<')
        .replaceAll('›', '<')
        .replaceAll('〈', '<')
        .replaceAll('〉', '<')
        .replaceAll('＜', '<')
        .replaceAll('＞', '<')
        .replaceAll(RegExp(r'[^A-Z0-9<]'), '')
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('8', 'B')
        .replaceAll('5', 'S');
  }

  String normalizeMrzLine() {
    String normalized = cleanMrzText();
    if (normalized.length < 44) {
      normalized = normalized.padRight(44, '<');
    } else if (normalized.length > 44) {
      normalized = normalized.substring(0, 44);
    }
    return normalized;
  }

  List<String> extractMrzLines(String fullText) {
    if (kDebugMode) {
      print("extract");
    }
    final lines = fullText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    List<String> mrzLines = [];

    for (String line in lines) {
      final cleanedLine = line.cleanMrzText();

      // MRZ Line 1: Must start with P< for passport
      bool isMrzLine1 = cleanedLine.startsWith('P<') ||
          cleanedLine.startsWith('P«') ||
          cleanedLine.startsWith('P‹') ||
          cleanedLine.startsWith('P〈') ||
          cleanedLine.startsWith('P＜');

      // MRZ Line 2: Must have at least 3 consecutive < characters or variants
      bool isMrzLine2 = RegExp(r'[<«»‹›〈〉＜＞]{3,}').hasMatch(cleanedLine) &&
          cleanedLine.length >= 40 &&
          !cleanedLine.startsWith('P') &&
          RegExp(r'[A-Z0-9]{6,}').hasMatch(cleanedLine);

      if (isMrzLine1 || (isMrzLine2 && cleanedLine.length >= 36)) {
        if (kDebugMode) {
          print("line : $line");
          print("cleanedLine : $cleanedLine");
          print("isMrzLine1: $isMrzLine1, isMrzLine2: $isMrzLine2");
        }
        mrzLines.add(cleanedLine.normalizeMrzLine());
      }
    }

    if (mrzLines.length >= 2) {
      if (kDebugMode) {
        print("mrzline > 2 : ${mrzLines.toString()}");
      }
      return mrzLines.take(2).toList();
    }

    return mrzLines;
  }
}
