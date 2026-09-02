import 'package:flutter/material.dart';

/// 台股慣例：漲紅、跌綠。
class AppColors {
  static const bg = Color(0xFF0B0E13);
  static const surface = Color(0xFF141922);
  static const surface2 = Color(0xFF1C2430);
  static const border = Color(0xFF2A3441);
  static const ink = Color(0xFFF2F5F9);
  static const ink2 = Color(0xFF9AA6B6);
  static const ink3 = Color(0xFF63718A);
  static const accent = Color(0xFF3B82F6);

  static const up = Color(0xFFFF4D4F); // 漲
  static const down = Color(0xFF16C784); // 跌
  static const flat = Color(0xFF9AA6B6);
  static const warn = Color(0xFFF5A623); // 提示 / 盤前

  static Color forChange(num v) => v > 0
      ? up
      : v < 0
          ? down
          : flat;
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      surface: AppColors.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
      fontFamily: 'Roboto',
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerColor: AppColors.border,
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.ink3,
      type: BottomNavigationBarType.fixed,
    ),
  );
}

/// 等寬數字樣式
const kNum = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w600,
);
