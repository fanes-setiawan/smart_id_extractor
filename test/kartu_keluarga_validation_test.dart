import 'package:flutter_test/flutter_test.dart';
import 'package:smart_id_extractor/smart_id_extractor.dart';

void main() {
  const sampleValidKkText = '''
REPUBLIK INDONESIA
KARTU KELUARGA
No. 3201010101010001
Nama Kepala Keluarga : AHMAD DAHLAN
Alamat : JL. MERDEKA NO. 45
RT/RW : 003/005
Desa/Kelurahan : SUKAMAJU
Kecamatan : CIBINONG
Kabupaten/Kota : KABUPATEN BOGOR
Kode Pos : 16911
Provinsi : JAWA BARAT

Tabel Anggota Keluarga:
No  Nama Lengkap        NIK               Jenis Kelamin  Agama
1   AHMAD DAHLAN        3201010203800001  LAKI-LAKI      ISLAM
2   SITI AMINAH         3201014506820002  PEREMPUAN      ISLAM
3   MUHAMMAD RIZKY      3201011210080003  LAKI-LAKI      ISLAM

Status Hubungan Dalam Keluarga:
1   KEPALA KELUARGA
2   ISTERI
3   ANAK
''';

  const sampleKtpText = '''
PROVINSI DAERAH ISTIMEWA YOGYAKARTA
KABUPATEN GUNUNGKIDUL
NIK : 3403071401030001
Nama : FANES SETIAWAN
Tempat/Tgl Lahir : GUNUNGKIDUL, 14-01-2003
Jenis Kelamin : LAKI-LAKI
Alamat : BLEKONANG
RT/RW : 001/007
Agama : ISLAM
Status Perkawinan : BELUM KAWIN
Pekerjaan : PELAJAR/MAHASISWA
Kewarganegaraan : WNI
Berlaku Hingga : SEUMUR HIDUP
''';

  const samplePassportText = '''
P<IDNSETIAWAN<<FANES<<<<<<<<<<<<<<<<<<<<<<<<
A1234567<3IDN0301148M31013143403071401030001
''';

  group('Kartu Keluarga Validation Tests', () {
    test('Validates authentic Kartu Keluarga with default options successfully', () {
      final result =
          KtpExtractor.validateKartuKeluargaFromText(sampleValidKkText);

      expect(result.isValid, isTrue);
      expect(result.hasHeader, isTrue);
      expect(result.hasNomorKk, isTrue);
      expect(result.nomorKk, equals('3201010101010001'));
      expect(result.hasKepalaKeluarga, isTrue);
      expect(result.hasAddress, isTrue);
      expect(result.missingRequirements, isEmpty);
      expect(result.confidence, greaterThanOrEqualTo(0.85));

      // Check extracted fields
      final data = result.data;
      expect(data, isNotNull);
      expect(data?.nomorKk, equals('3201010101010001'));
      expect(data?.namaKepalaKeluarga, equals('AHMAD DAHLAN'));
      expect(data?.alamat, equals('JL. MERDEKA NO. 45'));
      expect(data?.rt, equals('003'));
      expect(data?.rw, equals('005'));
      expect(data?.desaKelurahan, equals('SUKAMAJU'));
      expect(data?.kecamatan, equals('CIBINONG'));
      expect(data?.kabupatenKota, equals('BOGOR'));
      expect(data?.provinsi, equals('JAWA BARAT'));
      expect(data?.kodePos, equals('16911'));

      // Check extracted family members
      expect(data?.anggotaKeluarga.length, greaterThanOrEqualTo(2));
      expect(
        data?.anggotaKeluarga.any((m) => m.nik == '3201010203800001'),
        isTrue,
      );
    });

    test('Fails validation when Nomor KK is missing and requireNomorKk is true', () {
      const textWithoutKkNumber = '''
REPUBLIK INDONESIA
KARTU KELUARGA
Nama Kepala Keluarga : AHMAD DAHLAN
Alamat : JL. MERDEKA NO. 45
RT/RW : 003/005
Desa/Kelurahan : SUKAMAJU
Kecamatan : CIBINONG
''';

      final result = KtpExtractor.validateKartuKeluargaFromText(
        textWithoutKkNumber,
        options: const KartuKeluargaValidationOptions(requireNomorKk: true),
      );

      expect(result.isValid, isFalse);
      expect(result.hasNomorKk, isFalse);
      expect(result.nomorKk, isNull);
      expect(
        result.missingRequirements.any((m) => m.contains('Nomor Kartu Keluarga')),
        isTrue,
      );
    });

    test('Passes validation without Nomor KK when requireNomorKk is false', () {
      const textWithoutKkNumber = '''
REPUBLIK INDONESIA
KARTU KELUARGA
Nama Kepala Keluarga : AHMAD DAHLAN
Alamat : JL. MERDEKA NO. 45
RT/RW : 003/005
Desa/Kelurahan : SUKAMAJU
Kecamatan : CIBINONG
''';

      final result = KtpExtractor.validateKartuKeluargaFromText(
        textWithoutKkNumber,
        options: const KartuKeluargaValidationOptions(
          requireNomorKk: false,
          requireHeader: true,
          minKeywordMatches: 2,
        ),
      );

      expect(result.isValid, isTrue);
      expect(result.hasNomorKk, isFalse);
      expect(result.nomorKk, isNull);
    });

    test('Fails validation when header KARTU KELUARGA is missing', () {
      const textWithoutHeader = '''
No. 3201010101010001
Nama Kepala Keluarga : AHMAD DAHLAN
Alamat : JL. MERDEKA NO. 45
RT/RW : 003/005
Desa/Kelurahan : SUKAMAJU
''';

      final result = KtpExtractor.validateKartuKeluargaFromText(
        textWithoutHeader,
        options: const KartuKeluargaValidationOptions(requireHeader: true),
      );

      expect(result.isValid, isFalse);
      expect(result.hasHeader, isFalse);
      expect(
        result.missingRequirements.any((m) => m.contains('KARTU KELUARGA')),
        isTrue,
      );
    });

    test('Rejects KTP document as Kartu Keluarga', () {
      final result =
          KtpExtractor.validateKartuKeluargaFromText(sampleKtpText);

      expect(result.isValid, isFalse);
      expect(result.hasHeader, isFalse);
      expect(result.missingRequirements, isNotEmpty);
    });

    test('Rejects Passport document as Kartu Keluarga', () {
      final result =
          KtpExtractor.validateKartuKeluargaFromText(samplePassportText);

      expect(result.isValid, isFalse);
      expect(result.hasHeader, isFalse);
      expect(result.hasNomorKk, isFalse);
      expect(result.missingRequirements, isNotEmpty);
    });

    test('Custom keyword requirement validation', () {
      const kkWithoutCustomWord = sampleValidKkText;

      final result = KtpExtractor.validateKartuKeluargaFromText(
        kkWithoutCustomWord,
        options: const KartuKeluargaValidationOptions(
          customKeywords: ['KEMENDAGRI', 'TTE'],
        ),
      );

      expect(result.isValid, isFalse);
      expect(
        result.missingRequirements.any((m) => m.contains('KEMENDAGRI')),
        isTrue,
      );
      expect(
        result.missingRequirements.any((m) => m.contains('TTE')),
        isTrue,
      );
    });

    test('extractKartuKeluargaFromText extracts full model correctly', () {
      final model =
          KtpExtractor.extractKartuKeluargaFromText(sampleValidKkText);

      expect(model.nomorKk, equals('3201010101010001'));
      expect(model.namaKepalaKeluarga, equals('AHMAD DAHLAN'));
      expect(model.alamat, equals('JL. MERDEKA NO. 45'));
      expect(model.rt, equals('003'));
      expect(model.rw, equals('005'));
      expect(model.kecamatan, equals('CIBINONG'));
      expect(model.provinsi, equals('JAWA BARAT'));
    });
  });
}
