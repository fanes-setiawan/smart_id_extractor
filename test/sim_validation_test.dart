import 'package:flutter_test/flutter_test.dart';
import 'package:smart_id_extractor/smart_id_extractor.dart';

void main() {
  group('SIM (Surat Izin Mengemudi) Validation Tests', () {
    const validSimText = '''
KEPOLISIAN NEGARA REPUBLIK INDONESIA
SURAT IZIN MENGEMUDI
DRIVING LICENSE

A
1234-5678-000123

1. NAMA : BUDI SANTOSO
2. TGL LAHIR : 15-08-1990
3. GOL. DARAH : O   PRIA
4. ALAMAT : JL. MERDEKA NO. 45 RT 001/002
5. PEKERJAAN : KARYAWAN SWASTA
6. DOMISILI : JAKARTA SELATAN

BERLAKU S/D : 15-08-2028
KORLANTAS POLRI
''';

    const validSimCText = '''
SURAT IZIN MENGEMUDI
DRIVING LICENSE
C
9876 5432 109876
NAMA : SITI RAHMAWATI
TGL LAHIR : 20-05-1995
WANITA
GOL. DARAH : A
ALAMAT : BANDUNG
BERLAKU S/D : 20-05-2027
POLRI
''';

    test('Validates authentic SIM A successfully with default options', () {
      final result = SmartIdExtractor.validateSimFromText(validSimText);

      expect(result.isValid, isTrue);
      expect(result.hasHeader, isTrue);
      expect(result.hasGolongan, isTrue);
      expect(result.golongan, 'A');
      expect(result.nomorSim, isNotNull);
      expect(result.hasNomorSim, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.8));
      expect(result.missingRequirements, isEmpty);
      expect(result.failureReason, isNull);
    });

    test('Validates authentic SIM C successfully', () {
      final result = SmartIdExtractor.validateSimFromText(validSimCText);

      expect(result.isValid, isTrue);
      expect(result.hasHeader, isTrue);
      expect(result.hasGolongan, isTrue);
      expect(result.golongan, 'C');
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Rejects KTP text as SIM (negative discrimination)', () {
      const ktpText = '''
PROVINSI DAERAH ISTIMEWA YOGYAKARTA
KABUPATEN GUNUNGKIDUL
NIK : 3403011234560001
NAMA : FANES SETIAWAN
TEMPAT/TGL LAHIR : GUNUNGKIDUL, 31-01-2000
JENIS KELAMIN : LAKI-LAKI
ALAMAT : BLEKONANG
RT/RW : 001/002
AGAMA : ISLAM
STATUS PERKAWINAN : BELUM KAWIN
PEKERJAAN : PELAJAR/MAHASISWA
KEWARGANEGARAAN : WNI
BERLAKU HINGGA : SEUMUR HIDUP
''';

      final result = SmartIdExtractor.validateSimFromText(ktpText);

      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('Kartu Tanda Penduduk'));
    });

    test('Rejects Kartu Keluarga text as SIM (negative discrimination)', () {
      const kkText = '''
KARTU KELUARGA
No. 3201011234560001
Nama Kepala Keluarga : SULAIMAN
Alamat : DUSUN MAJU
RT/RW : 002/003
Desa/Kelurahan : SUKAMAJU
Kecamatan : CIPARAY
Kabupaten/Kota : BANDUNG
Kode Pos : 40381
Provinsi : JAWA BARAT
''';

      final result = SmartIdExtractor.validateSimFromText(kkText);

      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('Kartu Keluarga'));
    });

    test('Rejects non-document random text', () {
      const randomText = 'Halo ini adalah dokumen pengantar belanja sayur di supermarket.';
      final result = SmartIdExtractor.validateSimFromText(randomText);

      expect(result.isValid, isFalse);
      expect(result.hasHeader, isFalse);
      expect(result.confidence, lessThan(0.5));
    });

    test('Fails validation when requireGolongan is true but no class is detected', () {
      const simTextWithoutClass = '''
SURAT IZIN MENGEMUDI
DRIVING LICENSE
POLRI
BERLAKU S/D 2028
''';

      final result = SmartIdExtractor.validateSimFromText(
        simTextWithoutClass,
        options: const SimValidationOptions(
          requireHeader: true,
          requireGolongan: true,
          minKeywordMatches: 2,
        ),
      );

      expect(result.isValid, isFalse);
      expect(result.missingRequirements.any((r) => r.contains('Golongan SIM')), isTrue);
    });

    test('Validates real photo sample with low-contrast header (Veri Vardia)', () {
      const realSampleOcr = '''
INDONESIA
1005-0304-000388
C
1. VERI VARDIA
2. BANDUNG, 16-04-2003
3. O - PRIA
4. JL. MENTOP NO.39
RT 08/07 CICENDO
KOTA BANDUNG
5. PELAJAR/MHS
6. JABAR
24-09-2025
''';
      final result = SmartIdExtractor.validateSimFromText(realSampleOcr);

      expect(result.isValid, isTrue);
      expect(result.hasHeader, isTrue);
      expect(result.hasNomorSim, isTrue);
      expect(result.nomorSim, '10050304000388');
      expect(result.missingRequirements, isEmpty);
    });
  });
}
