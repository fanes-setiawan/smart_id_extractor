// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Shows an animated, dismissible custom floating snackbar matching the exact design:
/// - Dark navy rounded container (`#073359` / `#002B49`)
/// - Circular amber info icon (`#FD990F`)
/// - Max 2 lines of text (`PlusJakartaSans`, white, 13.sp)
/// - Circular semi-transparent dismiss (X) button on the right
/// - Clean transparent background without default Material Card shadow/clipping
/// - Smooth live floating (up & down) animation using internal vertical padding
///   to prevent any clipping or cutting during motion
/// - Auto-dismiss after [duration] (default 5s for readability) or instant tap on (X)
void showCustomSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 5),
  Widget? customIcon,
  Color? backgroundColor,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  messenger.showSnackBar(
    SnackBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.none,
      margin: EdgeInsets.only(
        bottom: 20.h,
        left: 16.w,
        right: 16.w,
      ),
      duration: duration,
      content: _AnimatedSnackBarContent(
        message: message,
        backgroundColor: backgroundColor ?? const Color(0xFF073359),
        customIcon: customIcon,
        onDismiss: () {
          messenger.hideCurrentSnackBar();
        },
      ),
    ),
  );
}

class _AnimatedSnackBarContent extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final Widget? customIcon;
  final VoidCallback onDismiss;

  const _AnimatedSnackBarContent({
    required this.message,
    required this.backgroundColor,
    this.customIcon,
    required this.onDismiss,
  });

  @override
  State<_AnimatedSnackBarContent> createState() =>
      _AnimatedSnackBarContentState();
}

class _AnimatedSnackBarContentState extends State<_AnimatedSnackBarContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;
  late final Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    // Gentle live floating animation: smooth sine oscillation
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(
      CurvedAnimation(
        parent: _floatController,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Provide internal vertical padding (6.h top and bottom) so that when the inner card
    // translates vertically, it never exceeds the SnackBar boundary or gets clipped.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _floatAnimation.value),
            child: child,
          );
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 14,
                spreadRadius: 0,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left Icon: Circular amber icon with bold info 'i'
              widget.customIcon ??
                  Container(
                    width: 32.r,
                    height: 32.r,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFD990F),
                        width: 2.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'i',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        color: const Color(0xFFFD990F),
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),

              SizedBox(width: 12.w),

              // Message text: Max 2 lines with smooth ellipsis
              Expanded(
                child: Text(
                  widget.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),

              SizedBox(width: 10.w),

              // Right Dismiss 'X' Button in a semi-transparent circular pill
              GestureDetector(
                onTap: widget.onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 34.r,
                  height: 34.r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 19.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
