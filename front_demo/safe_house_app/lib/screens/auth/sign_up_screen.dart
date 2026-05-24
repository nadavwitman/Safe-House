import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import 'join_house_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  String _username = '';
  String _email = '';
  String _password = '';
  bool _submitted = false;

  String? get _emailError => _submitted && _email.isEmpty ? 'Email is required.' : null;
  String? get _pwError => _submitted && _password.length < 6 ? 'Password must be at least 6 characters.' : null;

  void _submit() {
    setState(() => _submitted = true);
    if (_username.isNotEmpty && _email.isNotEmpty && _password.length >= 6) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const JoinHouseScreen()),
      );
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
            radius: 1.4,
            colors: [AppColors.sage500.withValues(alpha: 0.30), Colors.transparent],
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

                Text('Create an account',
                    style: GoogleFonts.newsreader(fontSize: 30, fontWeight: FontWeight.w500, color: AppColors.ink900, height: 1.1)),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    text: "Join the people watching over ",
                    style: GoogleFonts.manrope(fontSize: 14.5, color: AppColors.ink600, height: 1.5),
                    children: [
                      TextSpan(text: "'home'", style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.sage800)),
                      TextSpan(text: ' together.', style: GoogleFonts.manrope(fontSize: 14.5, color: AppColors.ink600)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AppInput(
                  label: 'Username',
                  icon: const Icon(Icons.person_outline),
                  placeholder: 'mara_b',
                  onChanged: (v) => setState(() => _username = v),
                ),
                const SizedBox(height: 14),
                AppInput(
                  label: 'Email',
                  icon: const Icon(Icons.mail_outline),
                  placeholder: 'you@email.com',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() => _email = v),
                  error: _emailError,
                ),
                const SizedBox(height: 14),
                AppInput(
                  label: 'Password',
                  icon: const Icon(Icons.lock_outline),
                  placeholder: 'At least 6 characters',
                  isPassword: true,
                  onChanged: (v) => setState(() => _password = v),
                  error: _pwError,
                  hint: _pwError == null ? 'Use 6+ characters with a mix of letters and numbers.' : null,
                ),
                const SizedBox(height: 20),
                AppButton(
                  variant: AppButtonVariant.primary,
                  buttonSize: AppButtonSize.lg,
                  full: true,
                  onPressed: _submit,
                  trailing: const Icon(Icons.arrow_forward, size: 18),
                  child: const Text('Create account'),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink600),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Text('Sign in',
                                style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.sage800,
                                    decoration: TextDecoration.underline, decorationColor: AppColors.sage800)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.sage50,
                    border: Border.all(color: AppColors.sage200),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, size: 18, color: AppColors.sage700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'We never record video or audio. Only ambient signals — when a door opens, a bed is occupied — are processed.',
                          style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.ink700, height: 1.5),
                        ),
                      ),
                    ],
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
