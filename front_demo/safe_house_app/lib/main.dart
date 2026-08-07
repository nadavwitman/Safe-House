import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/colors.dart';
import 'screens/auth/sign_in_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const SafeHouseApp());
}

class SafeHouseApp extends StatelessWidget {
  const SafeHouseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Safe House',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bgCream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.sage600,
          surface: AppColors.bgCream,
        ),
        textTheme: GoogleFonts.manropeTextTheme().copyWith(
          displayLarge: GoogleFonts.newsreader(
            fontSize: 36, fontWeight: FontWeight.w500,
            color: AppColors.ink900, letterSpacing: -0.5,
          ),
          displayMedium: GoogleFonts.newsreader(
            fontSize: 28, fontWeight: FontWeight.w500,
            color: AppColors.ink900, letterSpacing: -0.3,
          ),
          displaySmall: GoogleFonts.newsreader(
            fontSize: 22, fontWeight: FontWeight.w500,
            color: AppColors.ink900,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
          filled: false,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.sage600,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        }),
      ),
      home: const SignInScreen(),
    );
  }
}
