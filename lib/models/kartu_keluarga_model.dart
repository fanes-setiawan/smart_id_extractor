import 'package:equatable/equatable.dart';

/// Represents an individual family member listed in a Kartu Keluarga table.
class KartuKeluargaAnggotaModel extends Equatable {
  final String? nama;
  final String? nik;
  final String? jenisKelamin;
  final String? tempatLahir;
  final String? tanggalLahir;
  final String? agama;
  final String? pendidikan;
  final String? jenisPekerjaan;
  final String? statusPernikahan;
  final String? statusHubungan;
  final String? kewarganegaraan;
  final String? ayah;
  final String? ibu;

  const KartuKeluargaAnggotaModel({
    this.nama,
    this.nik,
    this.jenisKelamin,
    this.tempatLahir,
    this.tanggalLahir,
    this.agama,
    this.pendidikan,
    this.jenisPekerjaan,
    this.statusPernikahan,
    this.statusHubungan,
    this.kewarganegaraan,
    this.ayah,
    this.ibu,
  });

  /// Alias for [statusHubungan] (e.g. KEPALA KELUARGA, SUAMI, ISTERI, ANAK).
  String? get hubungan => statusHubungan;

  Map<String, dynamic> toMap() {
    return {
      'nama': nama,
      'nik': nik,
      'jenisKelamin': jenisKelamin,
      'tempatLahir': tempatLahir,
      'tanggalLahir': tanggalLahir,
      'agama': agama,
      'pendidikan': pendidikan,
      'jenisPekerjaan': jenisPekerjaan,
      'statusPernikahan': statusPernikahan,
      'statusHubungan': statusHubungan,
      'kewarganegaraan': kewarganegaraan,
      'ayah': ayah,
      'ibu': ibu,
    };
  }

  @override
  List<Object?> get props => [
        nama,
        nik,
        jenisKelamin,
        tempatLahir,
        tanggalLahir,
        agama,
        pendidikan,
        jenisPekerjaan,
        statusPernikahan,
        statusHubungan,
        kewarganegaraan,
        ayah,
        ibu,
      ];

  @override
  String toString() {
    return 'KartuKeluargaAnggotaModel(nama: $nama, nik: $nik, hubungan: $statusHubungan)';
  }
}

/// Represents extracted data from an Indonesian Kartu Keluarga (KK).
class KartuKeluargaModel extends Equatable {
  final String? nomorKk;
  final String? namaKepalaKeluarga;
  final String? alamat;
  final String? rt;
  final String? rw;
  final String? kodePos;
  final String? desaKelurahan;
  final String? kecamatan;
  final String? kabupatenKota;
  final String? provinsi;
  final List<KartuKeluargaAnggotaModel> anggotaKeluarga;
  final String? rawText;

  const KartuKeluargaModel({
    this.nomorKk,
    this.namaKepalaKeluarga,
    this.alamat,
    this.rt,
    this.rw,
    this.kodePos,
    this.desaKelurahan,
    this.kecamatan,
    this.kabupatenKota,
    this.provinsi,
    this.anggotaKeluarga = const [],
    this.rawText,
  });

  /// Formatted RT/RW string (e.g. "005 / 002").
  String? get rtRw {
    if (rt == null && rw == null) return null;
    return '${rt ?? '-'} / ${rw ?? '-'}';
  }

  Map<String, dynamic> toMap() {
    return {
      'nomorKk': nomorKk,
      'namaKepalaKeluarga': namaKepalaKeluarga,
      'alamat': alamat,
      'rt': rt,
      'rw': rw,
      'kodePos': kodePos,
      'desaKelurahan': desaKelurahan,
      'kecamatan': kecamatan,
      'kabupatenKota': kabupatenKota,
      'provinsi': provinsi,
      'anggotaKeluarga': anggotaKeluarga.map((a) => a.toMap()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        nomorKk,
        namaKepalaKeluarga,
        alamat,
        rt,
        rw,
        kodePos,
        desaKelurahan,
        kecamatan,
        kabupatenKota,
        provinsi,
        anggotaKeluarga,
        rawText,
      ];

  @override
  String toString() {
    return 'KartuKeluargaModel('
        'nomorKk: $nomorKk, '
        'kepalaKeluarga: $namaKepalaKeluarga, '
        'alamat: $alamat, '
        'rt/rw: $rt/$rw, '
        'kecamatan: $kecamatan, '
        'kabupatenKota: $kabupatenKota, '
        'provinsi: $provinsi, '
        'anggotaCount: ${anggotaKeluarga.length}'
        ')';
  }
}
