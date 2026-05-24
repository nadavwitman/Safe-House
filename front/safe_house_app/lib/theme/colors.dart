import 'package:flutter/material.dart';

class AppColors {
  // Background
  static const bgCream = Color(0xFFF2EDDF);
  static const bgSoft = Color(0xFFEDE6D3);
  static const bgCanvas = Color(0xFFE9E1CD);

  // Surfaces
  static const card = Color(0xFFFBF8F0);
  static const card2 = Color(0xFFFFFFFF);
  static const card3 = Color(0xFFF6F1E2);
  static const line = Color(0xFFE2D9C2);
  static const line2 = Color(0xFFD9CFB5);

  // Ink
  static const ink900 = Color(0xFF2F3A2E);
  static const ink800 = Color(0xFF3B4A3D);
  static const ink700 = Color(0xFF4D5E4F);
  static const ink600 = Color(0xFF61735F);
  static const ink500 = Color(0xFF82917F);
  static const ink400 = Color(0xFF9DA89A);
  static const ink300 = Color(0xFFBCC4B6);

  // Sage — primary brand
  static const sage800 = Color(0xFF4F6B53);
  static const sage700 = Color(0xFF6B8B6E);
  static const sage600 = Color(0xFF8FAA8C);
  static const sage500 = Color(0xFFA8C0A0);
  static const sage400 = Color(0xFFBBCFB3);
  static const sage300 = Color(0xFFCFDFC7);
  static const sage200 = Color(0xFFDFEAD6);
  static const sage100 = Color(0xFFEBF1E1);
  static const sage50 = Color(0xFFF4F6EA);

  // Status
  static const ok = Color(0xFF6B8B6E);
  static const okSoft = Color(0xFFDFEAD6);
  static const warn = Color(0xFFC99544);
  static const warnSoft = Color(0xFFF4E5C2);
  static const alert = Color(0xFFB95F4A);
  static const alertSoft = Color(0xFFF2D6CB);

  // Tone map for IconWell
  static Color iconWellBg(String tone) {
    switch (tone) {
      case 'sage':   return sage100;
      case 'warm':   return const Color(0xFFF1E7CB);
      case 'coral':  return alertSoft;
      case 'cream':  return card3;
      case 'sky':    return const Color(0xFFE1ECEC);
      case 'plum':   return const Color(0xFFECE2E8);
      default:       return sage100;
    }
  }

  static Color iconWellFg(String tone) {
    switch (tone) {
      case 'sage':   return sage800;
      case 'warm':   return const Color(0xFF8C6D2A);
      case 'coral':  return const Color(0xFF7E3A28);
      case 'cream':  return ink700;
      case 'sky':    return const Color(0xFF3F6868);
      case 'plum':   return const Color(0xFF704863);
      default:       return sage800;
    }
  }
}
