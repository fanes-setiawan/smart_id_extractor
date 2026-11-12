// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void showCustomSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  Widget? customIcon,
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.only(
        bottom: 20.h,
        left: 20.w,
        right: 20.w,
      ),
      content: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: backgroundColor ?? const Color(0xFF1E1E1E).withOpacity(0.50),
            borderRadius: BorderRadius.circular(30.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 15,
                spreadRadius: 1,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              customIcon ??
                  Container(
                    width: 24.w,
                    height: 24.h,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: Colors.white,
                      size: 16.r,
                    ),
                  ),
              SizedBox(width: 12.w),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'PlusJakartaSans',
                    fontWeight: FontWeight.w400,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      duration: duration,
    ),
  );
}
