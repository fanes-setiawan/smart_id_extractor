import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/smart_document_type.dart';

/// Top stepper progress bar header widget matching Figma design.
///
/// Features:
/// - Label: "TAHAPAN BERKAS" (Amber / Orange `#FD990F`)
/// - Badge chip on the right (e.g. "Kartu Keluarga", "Kartu Tanda Penduduk", "Surat Keterangan Sehat")
/// - 3-Segment Progress indicators (Solid dark blue for completed/current, light grey for pending)
/// - Step labels: `1. KTP` (with checkmark if completed), `2. KK`, `3. Surat Sehat`.
class SmartDocumentStepperHeader extends StatelessWidget {
  /// The active document type for this screen.
  final SmartDocumentType activeType;

  /// Custom step index (1, 2, or 3). If omitted, automatically determined from [activeType].
  final int? currentStep;

  /// Optional set of steps that have already been completed (e.g. `{1}` or `{1, 2}`).
  final Set<int> completedSteps;

  /// Custom badge text. If omitted, uses [activeType.badgeLabel].
  final String? badgeText;

  /// Callback when user taps a specific step, if interactive switching is enabled.
  final ValueChanged<SmartDocumentType>? onStepTapped;

  const SmartDocumentStepperHeader({
    super.key,
    required this.activeType,
    this.currentStep,
    this.completedSteps = const {},
    this.badgeText,
    this.onStepTapped,
  });

  int get _stepNumber {
    if (currentStep != null) return currentStep!;
    switch (activeType) {
      case SmartDocumentType.ktp:
        return 1;
      case SmartDocumentType.kartuKeluarga:
        return 2;
      case SmartDocumentType.suratSehat:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int step = _stepNumber;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: "TAHAPAN BERKAS" (left) + Document Type Chip (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'TAHAPAN BERKAS',
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: const Color(0xFFFD990F),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF1F7),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: const Color(0xFFD4E1EE),
                    width: 1,
                  ),
                ),
                child: Text(
                  badgeText ?? activeType.badgeLabel,
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    color: const Color(0xFF0B3866),
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 12.h),

          // Row 2: 3 Progress Bars
          Row(
            children: [
              Expanded(
                child: _buildProgressBar(
                  isActiveOrDone: step >= 1 || completedSteps.contains(1),
                  isCurrentOrange: step == 1,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _buildProgressBar(
                  isActiveOrDone: step >= 2 || completedSteps.contains(2),
                  isCurrentOrange: step == 2 && activeType == SmartDocumentType.kartuKeluarga,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _buildProgressBar(
                  isActiveOrDone: step >= 3 || completedSteps.contains(3),
                  isCurrentOrange: step == 3 && activeType == SmartDocumentType.suratSehat,
                ),
              ),
            ],
          ),

          SizedBox(height: 10.h),

          // Row 3: Step Titles ("1. KTP", "2. KK", "3. Surat Sehat")
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildStepLabel(
                  stepNum: 1,
                  label: '1. KTP',
                  type: SmartDocumentType.ktp,
                  isCurrent: step == 1,
                  isCompleted: completedSteps.contains(1) || step > 1,
                ),
              ),
              Expanded(
                child: _buildStepLabel(
                  stepNum: 2,
                  label: '2. KK',
                  type: SmartDocumentType.kartuKeluarga,
                  isCurrent: step == 2,
                  isCompleted: completedSteps.contains(2) || step > 2,
                ),
              ),
              Expanded(
                child: _buildStepLabel(
                  stepNum: 3,
                  label: '3. Surat Sehat',
                  type: SmartDocumentType.suratSehat,
                  isCurrent: step == 3,
                  isCompleted: completedSteps.contains(3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar({required bool isActiveOrDone, bool isCurrentOrange = false}) {
    Color barColor;
    if (isCurrentOrange && activeType == SmartDocumentType.suratSehat) {
      barColor = const Color(0xFFFD990F); // Orange in Surat Sehat step Figma
    } else if (isActiveOrDone) {
      barColor = const Color(0xFF0B3866); // Dark blue in completed/active
    } else {
      barColor = const Color(0xFFE2E8F0); // Subtle light grey for inactive
    }

    return Container(
      height: 4.5.h,
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(4.r),
      ),
    );
  }

  Widget _buildStepLabel({
    required int stepNum,
    required String label,
    required SmartDocumentType type,
    required bool isCurrent,
    required bool isCompleted,
  }) {
    Widget indicator;
    Color textColor;

    if (isCompleted) {
      indicator = Icon(
        Icons.check_circle_rounded,
        size: 14.sp,
        color: const Color(0xFF0B3866),
      );
      textColor = const Color(0xFF0B3866);
    } else if (isCurrent) {
      if (type == SmartDocumentType.suratSehat) {
        indicator = Container(
          width: 14.sp,
          height: 14.sp,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFD990F),
          ),
          alignment: Alignment.center,
          child: Text(
            '3',
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              color: Colors.white,
              fontSize: 8.5.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        textColor = const Color(0xFF0B3866);
      } else {
        indicator = Container(
          width: 7.sp,
          height: 7.sp,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF0B3866),
          ),
        );
        textColor = const Color(0xFF0B3866);
      }
    } else {
      indicator = Container(
        width: 6.sp,
        height: 6.sp,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF94A3B8),
        ),
      );
      textColor = const Color(0xFF94A3B8);
    }

    return GestureDetector(
      onTap: onStepTapped != null ? () => onStepTapped!(type) : null,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          indicator,
          SizedBox(width: 5.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                color: textColor,
                fontSize: 11.sp,
                fontWeight: isCurrent || isCompleted ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
