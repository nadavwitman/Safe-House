import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/user_service.dart';
import '../../services/api_client.dart';
import '../customer/customer_shell.dart';

class JoinHouseScreen extends StatefulWidget {
  const JoinHouseScreen({super.key});

  @override
  State<JoinHouseScreen> createState() => _JoinHouseScreenState();
}

class _JoinHouseScreenState extends State<JoinHouseScreen> {
  String _code = '';
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _joinResult;

  Future<void> _join() async {
    setState(() => _error = null);
    if (_code.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final result = await UserService.joinHouse(_code);
      if (mounted) {
        setState(() {
          _loading = false;
          _joinResult = result;
        });
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 60),
          child: Column(
            children: [
              const Wordmark(size: 'sm'),
              const SizedBox(height: 24),
              if (_joinResult == null) _buildForm(),
              if (_joinResult != null) _buildSuccess(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        _JoinIllustration(),
        const SizedBox(height: 22),
        Text(
          "You're not part of any house yet",
          textAlign: TextAlign.center,
          style: GoogleFonts.newsreader(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: AppColors.ink900,
              height: 1.15),
        ),
        const SizedBox(height: 10),
        Text(
          'Ask a family member or caregiver for the invite code from their Safe House admin.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
              fontSize: 14.5, color: AppColors.ink600, height: 1.5),
        ),
        const SizedBox(height: 24),
        AppInput(
          label: 'Invite code',
          icon: const Icon(Icons.home_outlined),
          placeholder: 'Enter your invite code',
          value: _code,
          onChanged: (v) => setState(() {
            _code = v.toUpperCase();
            _error = null;
          }),
          error: _error,
        ),
        const SizedBox(height: 16),
        AppButton(
          variant: AppButtonVariant.primary,
          buttonSize: AppButtonSize.lg,
          full: true,
          onPressed: _loading ? null : _join,
          trailing: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.arrow_forward, size: 18),
          child: Text(_loading ? 'Joining…' : 'Join house'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final residentName =
        _joinResult?['resident_name'] as String? ?? 'your house';
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.sage300),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.sage100,
                border: Border.all(color: AppColors.sage300, width: 2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 56, color: AppColors.sage800),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text("You're in.",
            style: GoogleFonts.newsreader(
                fontSize: 26,
                fontWeight: FontWeight.w500,
                color: AppColors.ink900)),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text('NOW WATCHING OVER',
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.ink500,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
              const SizedBox(height: 6),
              Text("$residentName's House",
                  style: GoogleFonts.newsreader(
                      fontSize: 24,
                      color: AppColors.sage800,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('$residentName · joined as Family',
                  style: GoogleFonts.manrope(
                      fontSize: 14, color: AppColors.ink700)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppButton(
          variant: AppButtonVariant.primary,
          buttonSize: AppButtonSize.lg,
          full: true,
          onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const CustomerShell())),
          trailing: const Icon(Icons.arrow_forward, size: 18),
          child: const Text('Take me to the dashboard'),
        ),
      ],
    );
  }
}

class _JoinIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppColors.sage500.withValues(alpha: 0.35),
                  Colors.transparent
                ],
              ),
              shape: BoxShape.circle,
            ),
          ),
          for (final d in [140.0, 100.0, 70.0])
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.sage300),
                shape: BoxShape.circle,
              ),
            ),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: AppColors.sage100,
              border: Border.all(color: AppColors.sage200),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.home_outlined,
                size: 42, color: AppColors.sage800),
          ),
        ],
      ),
    );
  }
}
