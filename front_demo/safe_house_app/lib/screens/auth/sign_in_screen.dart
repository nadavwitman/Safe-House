import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import 'sign_up_screen.dart';
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
  bool _hasError = false;

  void _signIn() {
    if (_email.isEmpty || _password.isEmpty) {
      setState(() => _hasError = true);
      return;
    }
    setState(() => _hasError = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const CustomerShell()),
    );
  }

  void _goAdmin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminShell()),
    );
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
            colors: [AppColors.sage500.withValues(alpha: 0.35), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: const Wordmark(size: 'md')),
                const SizedBox(height: 36),

                Text(
                  'Welcome back',
                  style: GoogleFonts.newsreader(fontSize: 30, fontWeight: FontWeight.w500, color: AppColors.ink900, height: 1.1),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to check on your loved one.',
                  style: GoogleFonts.manrope(fontSize: 14.5, color: AppColors.ink600, height: 1.5),
                ),

                if (_hasError) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.alertSoft,
                      border: Border.all(color: const Color(0xFFE6BFB1)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF7A3727)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("We couldn't sign you in",
                                  style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF7A3727))),
                              const SizedBox(height: 2),
                              Text('Invalid email or password.',
                                  style: GoogleFonts.manrope(fontSize: 13, color: const Color(0xFF7A3727))),
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
                  error: _hasError ? ' ' : null,
                ),
                const SizedBox(height: 14),
                AppInput(
                  label: 'Password',
                  icon: const Icon(Icons.lock_outline),
                  placeholder: 'Your password',
                  isPassword: true,
                  onChanged: (v) => setState(() => _password = v),
                  error: _hasError ? ' ' : null,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink600, decoration: TextDecoration.underline, decorationColor: AppColors.ink600),
                  ),
                ),
                const SizedBox(height: 18),
                AppButton(
                  variant: AppButtonVariant.primary,
                  buttonSize: AppButtonSize.lg,
                  full: true,
                  onPressed: _signIn,
                  trailing: const Icon(Icons.arrow_forward, size: 18),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'New here? ',
                      style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink600),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen())),
                            child: Text('Create an account',
                                style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.sage800, decoration: TextDecoration.underline, decorationColor: AppColors.sage800)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Admin mode toggle for demo
                Center(
                  child: GestureDetector(
                    onTap: _goAdmin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.card3,
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Sign in as Admin (demo)',
                          style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.ink600, fontWeight: FontWeight.w600)),
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
