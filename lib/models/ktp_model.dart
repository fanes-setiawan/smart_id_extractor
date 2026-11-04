import 'package:equatable/equatable.dart';

class KtpModel extends Equatable {
  final String? nik;
  final String? name;
  final String? birthDay;
  final String? placeBirth;
  final String? gender;
  final String? address;
  final String? rt;
  final String? rw;
  final String? subDistrict;
  final String? district;
  final String? province;
  final String? city;
  final String? religion;
  final String? marital;
  final String? occupation;
  final String? nationality;
  final String? validUntil;

  const KtpModel({
    this.nik,
    this.name,
    this.birthDay,
    this.placeBirth,
    this.gender,
    this.address,
    this.rt,
    this.rw,
    this.subDistrict,
    this.district,
    this.province,
    this.city,
    this.religion,
    this.marital,
    this.occupation,
    this.nationality,
    this.validUntil,
  });

  @override
  List<Object?> get props => [
        nik,
        name,
        birthDay,
        placeBirth,
        gender,
        address,
        rt,
        rw,
        subDistrict,
        district,
        province,
        city,
        religion,
        marital,
        occupation,
        nationality,
        validUntil,
      ];
}
