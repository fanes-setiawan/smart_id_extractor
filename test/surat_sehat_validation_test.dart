import 'package:flutter_test/flutter_test.dart';
import 'package:smart_id_extractor/smart_id_extractor.dart';

void main() {
  group('Surat Sehat Validation & Extraction Tests', () {
    const validSuratSehatText = '''
PEMERINTAH KOTA ADMINISTRASI JAKARTA SELATAN
SUKU DINAS KESEHATAN
PUSKESMAS KECAMATAN TEBET
Jl. Prof. Dr. Soepomo No. 54, Jakarta Selatan

SURAT KETERANGAN DOKTER
Nomor: 445/082/PKM-TB/X/2024

Yang bertanda tangan di bawah ini, Dokter Pemeriksa pada Puskesmas Kecamatan Tebet menerangkan bahwa:
Nama            : AHMAD FAUZI
NIK             : 3174051203920005
Umur            : 32 Tahun
Jenis Kelamin   : Laki-laki
Pekerjaan       : Karyawan Swasta
Alamat          : Jl. Tebet Timur Dalam No. 12, RT 003/RW 005

Berdasarkan hasil pemeriksaan fisik dan kesehatan yang telah dilakukan:
Tinggi Badan    : 172 cm
Berat Badan     : 68 kg
Tekanan Darah   : 120/80 mmHg
Golongan Darah  : O
Buta Warna      : Tidak Buta Warna (Normal)

Menyatakan bahwa orang tersebut dinyatakan dalam keadaan SEHAT JASMANI & ROHANI.
Demikian surat keterangan ini dibuat untuk dipergunakan sebagaimana mestinya.

Jakarta, 14 Oktober 2024
Dokter Pemeriksa,

dr. Siti Nurhaliza, Sp.OK
SIP: 503/441/SIP.D/2022
NIP: 198506122010012015
''';

    test('Validates authentic Surat Sehat with default options successfully', () {
      final result = SmartIdExtractor.validateSuratSehatFromText(validSuratSehatText);

      expect(result.isValid, isTrue);
      expect(result.hasHeader, isTrue);
      expect(result.hasDokter, isTrue);
      expect(result.hasFaskes, isTrue);
      expect(result.hasPemeriksaanFisik, isTrue);
      expect(result.matchedKeywordCount, greaterThanOrEqualTo(5));
      expect(result.confidence, greaterThan(0.8));
      expect(result.missingRequirements, isEmpty);

      final model = result.data;
      expect(model, isNotNull);
      expect(model!.nama, 'AHMAD FAUZI');
      expect(model.nik, '3174051203920005');
      expect(model.umur, '32 Tahun');
      expect(model.jenisKelamin, 'Laki-laki');
      expect(model.tinggiBadan, '172 cm');
      expect(model.beratBadan, '68 kg');
      expect(model.tekananDarah, '120/80 mmHg');
      expect(model.golonganDarah, 'O');
      expect(model.kesimpulan, 'SEHAT');
      expect(model.nomorSip, contains('503/441/SIP.D/2022'));
    });

    test('Fails validation when document is not a medical letter', () {
      const ktpText = '''
PROVINSI DKI JAKARTA
JAKARTA SELATAN
NIK: 3174051203920005
NAMA: AHMAD FAUZI
TEMPAT/TGL LAHIR: JAKARTA, 12-03-1992
JENIS KELAMIN: LAKI-LAKI
AGAMA: ISLAM
STATUS PERKAWINAN: KAWIN
PEKERJAAN: KARYAWAN SWASTA
KEWARGANEGARAAN: WNI
BERLAKU HINGGA: SEUMUR HIDUP
''';

      final result = SmartIdExtractor.validateSuratSehatFromText(ktpText);
      expect(result.isValid, isFalse);
      expect(result.hasHeader, isFalse);
      expect(result.missingRequirements, isNotEmpty);
    });

    test('Validates custom medical options (requireFaskes, requireDokter)', () {
      const partialText = '''
SURAT KETERANGAN SEHAT
Nama: Budi
Tinggi Badan: 165 cm
Berat Badan: 60 kg
Menyatakan keadaan SEHAT.
''';

      final strictResult = SmartIdExtractor.validateSuratSehatFromText(
        partialText,
        options: const SuratSehatValidationOptions(
          requireHeader: true,
          requireDokter: true,
          requireFaskes: true,
        ),
      );
      expect(strictResult.isValid, isFalse);
      expect(
        strictResult.missingRequirements.any((m) => m.contains('dokter')),
        isTrue,
      );
      expect(
        strictResult.missingRequirements.any((m) => m.contains('fasilitas kesehatan')),
        isTrue,
      );

      final relaxedResult = SmartIdExtractor.validateSuratSehatFromText(
        partialText,
        options: const SuratSehatValidationOptions(
          requireHeader: true,
          requireDokter: false,
          requireFaskes: false,
          minKeywordMatches: 1,
        ),
      );
      expect(relaxedResult.isValid, isTrue);
    });

    test('SmartDocumentType extension values are correct', () {
      expect(SmartDocumentType.ktp.defaultTitle, 'Upload Berkas KTP');
      expect(SmartDocumentType.kartuKeluarga.defaultTitle, 'Upload Berkas (KK)');
      expect(SmartDocumentType.suratSehat.defaultTitle, 'Upload Surat Keterangan Sehat');

      expect(SmartDocumentType.ktp.badgeLabel, 'Kartu Tanda Penduduk');
      expect(SmartDocumentType.kartuKeluarga.badgeLabel, 'Kartu Keluarga');
      expect(SmartDocumentType.suratSehat.badgeLabel, 'Surat Keterangan Sehat');

      expect(SmartDocumentType.ktp.shutterLabel, 'Ambil Foto e-KTP');
      expect(SmartDocumentType.kartuKeluarga.shutterLabel, 'Ambil Foto KK Asli');
      expect(SmartDocumentType.suratSehat.shutterLabel, 'Ambil Foto Surat Sehat Asli');

      expect(SmartDocumentType.ktp.submitButtonLabel, 'Kirim');
      expect(SmartDocumentType.suratSehat.submitButtonLabel, 'Kirim & Selesaikan Verifikasi');
    });
  });
}
