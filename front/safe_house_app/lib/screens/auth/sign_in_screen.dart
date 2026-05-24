import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import '../../services/auth_state.dart';
import '../../services/api_client.dart';
import 'sign_up_screen.dart';
import 'join_house_screen.dart';
import '../customer/customer_shell.dart';
import '../admin/admin_shell.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  String _email = '';
  String _password = '';
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    if (_email.isEmpty || _password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.signIn(_email, _password);
      await UserService.getProfile();
      if (!mounted) return;
      final auth = AuthState.instance;
      if (auth.isAdmin) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminShell()));
      } else if (auth.currentUser!.houses.isEmpty) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const JoinHouseScreen()));
      } else {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CustomerShell()));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1, -1),
            radius: 1.5,
            colors: [
              AppColors.sage500.withValues(alpha: 0.35),
              Colors.transparent
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: Wordmark(size: 'md')),
                const SizedBox(height: 36),
                Text(
                  'Welcome back',
                  style: GoogleFonts.newsreader(
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      color: AppColors.ink900,
                      height: 1.1),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to check on your loved one.',
                  style: GoogleFonts.manrope(
                      fontSize: 14.5, color: AppColors.ink600, height: 1.5),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.alertSoft,
                      border:
                          Border.all(color: const Color(0xFFE6BFB1)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: Color(0xFF7A3727)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("We couldn't sign you in",
                                  style: GoogleFonts.manrope(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF7A3727))),
                              const SizedBox(height: 2),
                              Text(_error!,
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      color: const Color(0xFF7A3727))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                AppInput(
                  label: 'Email',
                  icon: const Icon(Icons.mail_outline),
                  placeholder: 'you@email.com',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() => _email = v),
                ),
                const SizedBox(height: 14),
                AppInput(
                  label: 'Password',
                  icon: const Icon(Icons.lock_outline),
                  placeholder: 'Your password',
                  isPassword: true,
                  onChanged: (v) => setState(() => _password = v),
                ),
                const SizedBox(height: 20),
                AppButton(
                  variant: AppButtonVariant.primary,
                  buttonSize: AppButtonSize.lg,
                  full: true,
                  onPressed: _loading ? null : _signIn,
                  trailing: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_forward, size: 18),
                  child: Text(_loading ? 'Signing in…' : 'Sign in'),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'New here? ',
                      style: GoogleFonts.manrope(
                          fontSize: 13.5, color: AppColors.ink600),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const SignUpScreen())),
                            child: Text('Create an account',
                                style: GoogleFonts.manrope(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.sage800,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.sage800)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
