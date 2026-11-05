import 'package:equatable/equatable.dart';

/// Represents parsed data from an Indonesian medical certificate
/// (Surat Keterangan Dokter / Surat Keterangan Sehat).
class SuratSehatModel extends Equatable {
  /// Name of the patient / examined individual.
  final String? nama;

  /// NIK (16-digit) if printed on the medical letter.
  final String? nik;

  /// Age or date of birth of the patient.
  final String? umur;

  /// Gender (Laki-laki / Perempuan).
  final String? jenisKelamin;

  /// Job / occupation of the patient.
  final String? pekerjaan;

  /// Address of the patient.
  final String? alamat;

  /// Height in cm (Tinggi Badan).
  final String? tinggiBadan;

  /// Weight in kg (Berat Badan).
  final String? beratBadan;

  /// Blood pressure (Tekanan Darah / Tensi), e.g. "120/80 mmHg".
  final String? tekananDarah;

  /// Blood type (Golongan Darah: A, B, AB, O).
  final String? golonganDarah;

  /// Pulse rate (Denyut Nadi).
  final String? denyutNadi;

  /// Color blindness status (Buta Warna: Tidak / Normal / Buta Warna).
  final String? butaWarna;

  /// Stated health conclusion (e.g. "SEHAT", "SEHAT FISIK & ROHANI", "LAYAK BEKERJA").
  final String? kesimpulan;

  /// Name of the examining doctor.
  final String? namaDokter;

  /// SIP (Surat Izin Praktik) or NIP of the examining doctor.
  final String? nomorSip;

  /// Name of the health clinic / puskesmas / hospital.
  final String? namaFaskes;

  /// Location / city of issuance.
  final String? kota;

  /// Date the letter was issued (e.g. "12 Oktober 2024").
  final String? tanggalSurat;

  /// Full raw OCR text recognized from the document.
  final String? rawText;

  const SuratSehatModel({
    this.nama,
    this.nik,
    this.umur,
    this.jenisKelamin,
    this.pekerjaan,
    this.alamat,
    this.tinggiBadan,
    this.beratBadan,
    this.tekananDarah,
    this.golonganDarah,
    this.denyutNadi,
    this.butaWarna,
    this.kesimpulan,
    this.namaDokter,
    this.nomorSip,
    this.namaFaskes,
    this.kota,
    this.tanggalSurat,
    this.rawText,
  });

  Map<String, dynamic> toMap() {
    return {
      'nama': nama,
      'nik': nik,
      'umur': umur,
      'jenisKelamin': jenisKelamin,
      'pekerjaan': pekerjaan,
      'alamat': alamat,
      'tinggiBadan': tinggiBadan,
      'beratBadan': beratBadan,
      'tekananDarah': tekananDarah,
      'golonganDarah': golonganDarah,
      'denyutNadi': denyutNadi,
      'butaWarna': butaWarna,
      'kesimpulan': kesimpulan,
      'namaDokter': namaDokter,
      'nomorSip': nomorSip,
      'namaFaskes': namaFaskes,
      'kota': kota,
      'tanggalSurat': tanggalSurat,
    };
  }

  @override
  List<Object?> get props => [
        nama,
        nik,
        umur,
        jenisKelamin,
        pekerjaan,
        alamat,
        tinggiBadan,
        beratBadan,
        tekananDarah,
        golonganDarah,
        denyutNadi,
        butaWarna,
        kesimpulan,
        namaDokter,
        nomorSip,
        namaFaskes,
        kota,
        tanggalSurat,
        rawText,
      ];

  @override
  String toString() {
    return 'SuratSehatModel(nama: $nama, faskes: $namaFaskes, dokter: $namaDokter, tensi: $tekananDarah, kesimpulan: $kesimpulan)';
  }
}

