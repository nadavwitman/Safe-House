import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';

class AdminCreateScreen extends StatefulWidget {
  const AdminCreateScreen({super.key});

  @override
  State<AdminCreateScreen> createState() => _AdminCreateScreenState();
}

class _AdminCreateScreenState extends State<AdminCreateScreen> {
  String _resident = '';

  String? _residentErr;

  bool _loading = false;
  bool _submitted = false;

  late String _houseId;
  late String _inviteCode;
  late String _deviceToken;

  bool _validate() {
    setState(() {
      _residentErr = _resident.trim().isEmpty ? 'Resident name is required.' : null;
    });
    return _residentErr == null;
  }

  void _submit() async {
    if (!_validate()) return;
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 1200));

    final ts = DateTime.now().millisecondsSinceEpoch;
    final initials = _resident.trim().split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    final num4 = ((ts % 9000) + 1000).toString().substring(0, 4);
    final num4b = ((ts ~/ 7 % 9000) + 1000).toString().substring(0, 4);

    setState(() {
      _loading = false;
      _submitted = true;
      _houseId = 'AHE-$num4-$initials';
      _inviteCode = '$initials-INV-$num4b';
      _deviceToken = 'esp32_${ts.toRadixString(16).padLeft(16, '0')}';
    });
  }

  void _reset() {
    setState(() {
      _submitted = false;
      _resident = '';
      _residentErr = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ADMIN', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink500, letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text('Create House', style: GoogleFonts.newsreader(fontSize: 28, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: _submitted ? _SuccessView(
                  houseId: _houseId,
                  inviteCode: _inviteCode,
                  deviceToken: _deviceToken,
                  onCreateAnother: _reset,
                ) : _buildForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('House details', style: GoogleFonts.newsreader(fontSize: 22, color: AppColors.ink900, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            'We\'ll generate the credentials you need to hand off to the family and the hardware unit.',
            style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink600, height: 1.5),
          ),
          const SizedBox(height: 18),
          AppInput(
            label: 'Resident name *',
            icon: const Icon(Icons.person_outlined),
            placeholder: 'e.g. Walter Hayashi',
            error: _residentErr,
            onChanged: (v) {
              _resident = v;
              if (_residentErr != null) setState(() => _residentErr = null);
            },
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Address',
            icon: const Icon(Icons.home_outlined),
            placeholder: 'Street, city, state',
            onChanged: (_) {},
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Emergency contact phone',
            icon: const Icon(Icons.phone_outlined),
            placeholder: '+1 (___) ___-____',
            keyboardType: TextInputType.phone,
            onChanged: (_) {},
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              AppButton(
                variant: AppButtonVariant.primary,
                trailing: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.arrow_forward, size: 16),
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Creating…' : 'Create house'),
              ),
              const SizedBox(width: 10),
              AppButton(
                variant: AppButtonVariant.ghost,
                onPressed: _loading ? null : _reset,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Success view ──────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final String houseId, inviteCode, deviceToken;
  final VoidCallback onCreateAnother;
  const _SuccessView({
    required this.houseId,
    required this.inviteCode,
    required this.deviceToken,
    required this.onCreateAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.sage50, AppColors.card],
          stops: [0.0, 0.6],
        ),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success header
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: AppColors.sage600, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Color(0xFFFBF8F0), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('House created', style: GoogleFonts.newsreader(fontSize: 24, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('Save these credentials — you\'ll need them now.',
                        style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Credentials
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                CopyChip(label: 'House ID — admin reference', value: houseId, mono: false),
                const SizedBox(height: 12),
                CopyChip(label: 'Invite code — share with family', value: inviteCode, mono: false),
                const SizedBox(height: 12),
                CopyChip(label: 'Device token — program into the ESP32 unit', value: deviceToken),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Warning banner
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.warnSoft,
              border: Border.all(color: const Color(0xFFEAD7A4)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFF7A5419)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The device token is shown only once. Copy it to a safe place before closing this screen.',
                    style: GoogleFonts.manrope(fontSize: 12.5, color: const Color(0xFF7A5419), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Actions
          Row(
            children: [
              AppButton(
                variant: AppButtonVariant.primary,
                onPressed: onCreateAnother,
                child: const Text('Done'),
              ),
              const SizedBox(width: 10),
              AppButton(
                variant: AppButtonVariant.outline,
                leading: const Icon(Icons.add, size: 16),
                onPressed: onCreateAnother,
                child: const Text('Create another'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
