import 'package:flutter/material.dart';

/// 台股慣例：漲紅、跌綠。
/// bg/surface/border/ink 這幾個「介面色」會隨淺色/深色模式切換，
/// 用 static getter 讀目前模式；漲跌/強調色是語意色，兩種模式都一樣。
class AppColors {
  static bool _light = false;
  static bool get isLight => _light;
  static void setLight(bool light) => _light = light;

  static Color get bg => _light ? const Color(0xFFF5F6F8) : const Color(0xFF0B0E13);
  static Color get surface => _light ? const Color(0xFFFFFFFF) : const Color(0xFF141922);
  static Color get surface2 => _light ? const Color(0xFFEEF0F3) : const Color(0xFF1C2430);
  static Color get border => _light ? const Color(0xFFE1E4E9) : const Color(0xFF2A3441);
  static Color get ink => _light ? const Color(0xFF12151A) : const Color(0xFFF2F5F9);
  static Color get ink2 => _light ? const Color(0xFF5B6572) : const Color(0xFF9AA6B6);
  static Color get ink3 => _light ? const Color(0xFF8A93A0) : const Color(0xFF63718A);

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
  final base = AppColors.isLight
      ? ThemeData.light(useMaterial3: true)
      : ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      surface: AppColors.surface,
      brightness: AppColors.isLight ? Brightness.light : Brightness.dark,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
      fontFamily: 'Roboto',
    ),
    appBarTheme: AppBarTheme(
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
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dividerColor: AppColors.border,
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
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

/// 小號等寬數字（券商列表用）
const kNumSm = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w600,
  fontSize: 11.5,
);
