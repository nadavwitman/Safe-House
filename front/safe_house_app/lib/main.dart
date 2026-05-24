import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/colors.dart';
import 'services/auth_state.dart';
import 'services/user_service.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/join_house_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/admin/admin_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await AuthState.instance.loadFromStorage();

  if (AuthState.instance.accessToken != null) {
    try {
      await UserService.getProfile();
    } catch (_) {
      await AuthState.instance.clear();
    }
  }

  runApp(const SafeHouseApp());
}

class SafeHouseApp extends StatelessWidget {
  const SafeHouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (AuthState.instance.isLoggedIn) {
      if (AuthState.instance.isAdmin) {
        home = const AdminShell();
      } else if (AuthState.instance.currentUser!.houses.isEmpty) {
        home = const JoinHouseScreen();
      } else {
        home = const CustomerShell();
      }
    } else {
      home = const SignInScreen();
    }

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
            fontSize: 36,
            fontWeight: FontWeight.w500,
            color: AppColors.ink900,
            letterSpacing: -0.5,
          ),
          displayMedium: GoogleFonts.newsreader(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: AppColors.ink900,
            letterSpacing: -0.3,
          ),
          displaySmall: GoogleFonts.newsreader(
            fontSize: 22,
            fontWeight: FontWeight.w500,
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
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
      home: home,
    );
  }
}
