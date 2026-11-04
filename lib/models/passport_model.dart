import 'package:equatable/equatable.dart';

class PassportModel extends Equatable {
  final String? documentType;
  final String? issuingCountry;
  final String? surname;
  final String? givenNames;
  final String? passportNumber;
  final String? nationality;
  final String? birthDate;
  final String? gender;
  final String? expiryDate;
  final String? personalNumber;
  final String? compositeCheckDigit;
  final String? mrz1;
  final String? mrz2;
  
  const PassportModel({
    this.documentType,
    this.issuingCountry,
    this.surname,
    this.givenNames,
    this.passportNumber,
    this.nationality,
    this.birthDate,
    this.gender,
    this.expiryDate,
    this.personalNumber,
    this.compositeCheckDigit,
    this.mrz1,
    this.mrz2,
  });

  @override
  List<Object?> get props => [
        documentType,
        issuingCountry,
        surname,
        givenNames,
        passportNumber,
        nationality,
        birthDate,
        gender,
        expiryDate,
        personalNumber,
        compositeCheckDigit,
        mrz1,
        mrz2,
      ];

  @override
  String toString() {
    return 'PassportModel('
        'documentType: $documentType, '
        'issuingCountry: $issuingCountry, '
        'surname: $surname, '
        'givenNames: $givenNames, '
        'passportNumber: $passportNumber, '
        'nationality: $nationality, '
        'birthDate: $birthDate, '
        'gender: $gender, '
        'expiryDate: $expiryDate, '
        'personalNumber: $personalNumber, '
        'compositeCheckDigit: $compositeCheckDigit'
        ')';
  }
}