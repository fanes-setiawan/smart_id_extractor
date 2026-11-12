// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Shows an animated, dismissible custom floating snackbar:
/// - Dark navy rounded container (`#002B49` / `#0A3358`)
/// - Left circular amber info icon (`#FD990F`)
/// - Max 2 lines of message text (`PlusJakartaSans`, white, 13.sp)
/// - Right circular dismiss (X) button with semi-transparent background
/// - Smooth entrance slide & subtle continuous breathing/floating animation
/// - Auto-dismiss after [duration] (default 5s for readability) or tap X to dismiss immediately
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
      margin: EdgeInsets.only(
        bottom: 24.h,
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
    // Gentle live floating animation: moves up & down by 2-3px smoothly
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: 0.0, end: -3.5).animate(
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
    return AnimatedBuilder(
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
              color: Colors.black.withOpacity(0.28),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 6),
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
    );
  }
}
