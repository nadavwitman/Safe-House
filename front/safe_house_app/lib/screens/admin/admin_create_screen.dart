import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/admin_service.dart';
import '../../services/api_client.dart';

class AdminCreateScreen extends StatefulWidget {
  const AdminCreateScreen({super.key});

  @override
  State<AdminCreateScreen> createState() => _AdminCreateScreenState();
}

class _AdminCreateScreenState extends State<AdminCreateScreen> {
  String _resident = '';
  String _address = '';
  String _phone = '';

  String? _residentErr;
  String? _apiError;

  bool _loading = false;
  Map<String, dynamic>? _result;

  bool _validate() {
    setState(() {
      _residentErr =
          _resident.trim().isEmpty ? 'Resident name is required.' : null;
    });
    return _residentErr == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() {
      _loading = true;
      _apiError = null;
    });
    try {
      final data = await AdminService.createHouse(
        residentName: _resident,
        address: _address.trim().isEmpty ? null : _address,
        emergencyContactPhone: _phone.trim().isEmpty ? null : _phone,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _result = data;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _apiError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _apiError = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _result = null;
      _resident = '';
      _address = '';
      _phone = '';
      _residentErr = null;
      _apiError = null;
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
                  Text('ADMIN',
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink500,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text('Create House',
                      style: GoogleFonts.newsreader(
                          fontSize: 28,
                          color: AppColors.ink900,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: _result != null
                    ? _SuccessView(
                        houseId: _result!['house_id'] as String? ?? '',
                        inviteCode: _result!['invite_code'] as String? ?? '',
                        deviceToken:
                            _result!['device_token'] as String? ?? '',
                        onCreateAnother: _reset,
                      )
                    : _buildForm(),
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
          Text('House details',
              style: GoogleFonts.newsreader(
                  fontSize: 22,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            "We'll generate the credentials you need to hand off to the family and the hardware unit.",
            style: GoogleFonts.manrope(
                fontSize: 13.5, color: AppColors.ink600, height: 1.5),
          ),
          const SizedBox(height: 18),
          AppInput(
            label: 'Resident name *',
            icon: const Icon(Icons.person_outlined),
            placeholder: 'e.g. Walter Hayashi',
            value: _resident,
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
            value: _address,
            onChanged: (v) => _address = v,
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Emergency contact phone',
            icon: const Icon(Icons.phone_outlined),
            placeholder: '+1 (___) ___-____',
            keyboardType: TextInputType.phone,
            value: _phone,
            onChanged: (v) => _phone = v,
          ),
          if (_apiError != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.alertSoft,
                border: Border.all(color: const Color(0xFFE6BFB1)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Color(0xFF7A3727)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_apiError!,
                        style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: const Color(0xFF7A3727),
                            height: 1.4)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              AppButton(
                variant: AppButtonVariant.primary,
                trailing: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
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

// ── Success view ─────────────────────────────────────────────────
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
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                    color: AppColors.sage600, shape: BoxShape.circle),
                child: const Icon(Icons.check,
                    color: Color(0xFFFBF8F0), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('House created',
                        style: GoogleFonts.newsreader(
                            fontSize: 24,
                            color: AppColors.ink900,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text("Save these credentials — you'll need them now.",
                        style: GoogleFonts.manrope(
                            fontSize: 13.5, color: AppColors.ink600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                CopyChip(
                    label: 'House ID — admin reference',
                    value: houseId,
                    mono: false),
                const SizedBox(height: 12),
                CopyChip(
                    label: 'Invite code — share with family',
                    value: inviteCode,
                    mono: false),
                const SizedBox(height: 12),
                CopyChip(
                    label: 'Device token — program into the ESP32 unit',
                    value: deviceToken),
              ],
            ),
          ),
          const SizedBox(height: 14),

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
                const Icon(Icons.info_outline,
                    size: 16, color: Color(0xFF7A5419)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The device token is shown only once. Copy it to a safe place before closing this screen.',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: const Color(0xFF7A5419),
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

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
