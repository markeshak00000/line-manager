import 'package:flutter/material.dart';
class AppTheme {
  static const orange = Color(0xFFFF6B00);
  static const darkOrange = Color(0xFFE65100);
  static ThemeData light() => ThemeData(useMaterial3:true, brightness:Brightness.light, colorScheme: ColorScheme.fromSeed(seedColor: orange, brightness: Brightness.light), fontFamily: 'Cairo', appBarTheme: const AppBarTheme(centerTitle:true));
  static ThemeData dark() => ThemeData(useMaterial3:true, brightness:Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: orange, brightness: Brightness.dark), fontFamily: 'Cairo', appBarTheme: const AppBarTheme(centerTitle:true));
}
