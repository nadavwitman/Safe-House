import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/admin_service.dart';
import '../../services/api_client.dart';

class AdminCreateScreen extends StatefulWidget {
  /// Leaves this tab for House Search — where a house created here shows up,
  /// and where its credentials can be looked up again.
  final VoidCallback? onNavigateToSearch;
  const AdminCreateScreen({super.key, this.onNavigateToSearch});

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

  /// Finishing — as opposed to creating another — means leaving for the list,
  /// where the house that was just made is now waiting.
  void _done() {
    _reset();
    widget.onNavigateToSearch?.call();
  }

  /// Clears whatever has been typed as a side effect of leaving the screen.
  /// Wiping the form in place would look like the button had misfired.
  void _cancel() => _done();

  /// Any edit means the admin is responding to the failure, so the banner has
  /// done its job — leaving it up reads as though the form is still rejected.
  void _clearApiError() {
    if (_apiError != null) setState(() => _apiError = null);
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
                        onDone: _done,
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
              _clearApiError();
              if (_residentErr != null) setState(() => _residentErr = null);
            },
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Address',
            icon: const Icon(Icons.home_outlined),
            placeholder: 'Street, city, state',
            value: _address,
            onChanged: (v) {
              _address = v;
              _clearApiError();
            },
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'Emergency contact phone',
            icon: const Icon(Icons.phone_outlined),
            placeholder: '+1 (___) ___-____',
            keyboardType: TextInputType.phone,
            value: _phone,
            onChanged: (v) {
              _phone = v;
              _clearApiError();
            },
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
          // Wrap, not Row: at a large text scale these two buttons are wider
          // than the card and a Row would overflow rather than reflow.
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
              AppButton(
                variant: AppButtonVariant.ghost,
                onPressed: _loading ? null : _cancel,
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
  final VoidCallback onDone;
  const _SuccessView({
    required this.houseId,
    required this.inviteCode,
    required this.deviceToken,
    required this.onCreateAnother,
    required this.onDone,
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
                // House ID and device token both get pasted into the unit's
                // config.h, so the labels say so rather than calling the ID a
                // mere reference and leaving the installer to guess.
                CopyChip(
                    label: 'House ID — goes in the ESP32 config',
                    value: houseId,
                    mono: false),
                const SizedBox(height: 12),
                CopyChip(
                    label: 'Invite code — share with family',
                    value: inviteCode,
                    mono: false),
                const SizedBox(height: 12),
                CopyChip(
                    label: 'Device token — goes in the ESP32 config',
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
                    'Copy the House ID and device token into the unit’s config, '
                    'then power it on. The house stays Inactive until its first '
                    'sensor reading arrives. You can look these credentials up '
                    'again under House Search.',
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

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(
                variant: AppButtonVariant.primary,
                onPressed: onDone,
                child: const Text('Done'),
              ),
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
