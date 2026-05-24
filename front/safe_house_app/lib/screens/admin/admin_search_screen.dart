import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../auth/sign_in_screen.dart';

// ── Sensor definitions (indices match API sensor_mask order) ─────
class _SensorDef {
  final String id, label, tone;
  final IconData icon;
  const _SensorDef(this.id, this.icon, this.label, this.tone);
}

const _sensorList = [
  _SensorDef('door', Icons.door_front_door_outlined, 'Front Door', 'sage'),
  _SensorDef('kitchen', Icons.kitchen_outlined, 'Kitchen', 'warm'),
  _SensorDef('bath', Icons.bathtub_outlined, 'Bathroom', 'sky'),
  _SensorDef('toilet', Icons.water_drop_outlined, 'Toilet', 'sky'),
  _SensorDef('meds', Icons.medication_outlined, 'Medication Cabinet', 'plum'),
  _SensorDef('bed', Icons.bed_outlined, 'Bedroom', 'sage'),
  _SensorDef('living', Icons.weekend_outlined, 'Living Room', 'sage'),
];

enum _SearchState { empty, searching, noresult, found, error }

// ── Screen ───────────────────────────────────────────────────────
class AdminSearchScreen extends StatefulWidget {
  final VoidCallback? onNavigateToCreate;
  const AdminSearchScreen({super.key, this.onNavigateToCreate});

  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> {
  final _controller = TextEditingController();
  _SearchState _state = _SearchState.empty;
  Map<String, dynamic>? _house;
  String? _errorMsg;

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _state = _SearchState.searching;
      _house = null;
      _errorMsg = null;
    });
    try {
      final house = await AdminService.getHouse(q);
      if (mounted) {
        setState(() {
          _house = house;
          _state = _SearchState.found;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        setState(() => _state = _SearchState.noresult);
      } else {
        setState(() {
          _state = _SearchState.error;
          _errorMsg = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = _SearchState.error;
          _errorMsg = 'Could not reach the server. Check your connection.';
        });
      }
    }
  }

  void _reset() {
    setState(() {
      _controller.clear();
      _state = _SearchState.empty;
      _house = null;
      _errorMsg = null;
    });
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ADMIN',
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink500,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Text('House Search',
                          style: GoogleFonts.newsreader(
                              fontSize: 28,
                              color: AppColors.ink900,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _signOut,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: AppColors.card,
                          border: Border.all(color: AppColors.line),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.logout,
                          size: 17, color: AppColors.ink700),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: Column(
                  children: [
                    // Search row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card2,
                              border: Border.all(
                                  color: AppColors.line2, width: 1.5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 14),
                                  child: Icon(Icons.search,
                                      color: AppColors.ink500, size: 20),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    onSubmitted: (_) => _search(),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        color: AppColors.ink900),
                                    decoration: InputDecoration(
                                      hintText: 'Enter house ID',
                                      hintStyle: GoogleFonts.manrope(
                                          fontSize: 14,
                                          color: AppColors.ink400),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AppButton(
                          variant: AppButtonVariant.primary,
                          leading: _state == _SearchState.searching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.search, size: 16),
                          onPressed: _state == _SearchState.searching
                              ? null
                              : _search,
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_state == _SearchState.noresult)
                      _NoResultCard(
                        onRetry: _reset,
                        onCreateNew: widget.onNavigateToCreate,
                      ),
                    if (_state == _SearchState.error)
                      _ErrorCard(message: _errorMsg ?? 'An error occurred.', onRetry: _reset),
                    if (_state == _SearchState.found && _house != null)
                      _FoundCard(house: _house!),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── No-result card ───────────────────────────────────────────────
class _NoResultCard extends StatelessWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onCreateNew;
  const _NoResultCard({this.onRetry, this.onCreateNew});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.bgSoft,
              border:
                  Border.all(color: AppColors.line2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search, size: 28, color: AppColors.ink500),
          ),
          const SizedBox(height: 14),
          Text('No house found with this ID',
              style: GoogleFonts.newsreader(
                  fontSize: 22,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            "Double-check the ID for typos, or create a new house if one hasn't been set up yet.",
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 14, color: AppColors.ink600, height: 1.55),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton(
                variant: AppButtonVariant.outline,
                buttonSize: AppButtonSize.sm,
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
              const SizedBox(width: 10),
              AppButton(
                variant: AppButtonVariant.primary,
                buttonSize: AppButtonSize.sm,
                leading: const Icon(Icons.add, size: 14),
                onPressed: onCreateNew,
                child: const Text('Create new house'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Error card ───────────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorCard({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.alertSoft,
        border: Border.all(color: const Color(0xFFE6BFB1)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFF7A3727)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        color: const Color(0xFF7A3727),
                        height: 1.5)),
                const SizedBox(height: 10),
                AppButton(
                  variant: AppButtonVariant.ghost,
                  buttonSize: AppButtonSize.sm,
                  onPressed: onRetry,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Found card ───────────────────────────────────────────────────
class _FoundCard extends StatefulWidget {
  final Map<String, dynamic> house;
  const _FoundCard({required this.house});

  @override
  State<_FoundCard> createState() => _FoundCardState();
}

class _FoundCardState extends State<_FoundCard> {
  late String _inviteCode;
  late String _deviceToken;
  late List<Map<String, dynamic>> _users;
  late List<bool> _mask;
  bool _maskDirty = false;
  bool _regenLoading = false;
  bool _rotateLoading = false;
  bool _maskSaving = false;
  final Set<String> _removingUsers = {};

  @override
  void initState() {
    super.initState();
    _inviteCode = widget.house['invite_code'] as String? ?? '';
    _deviceToken = widget.house['device_token'] as String? ?? '';
    _users = (widget.house['users'] as List? ?? [])
        .map((u) => Map<String, dynamic>.from(u as Map))
        .toList();
    final rawMask = widget.house['sensor_mask'] as List?;
    _mask = rawMask != null
        ? rawMask.map((v) => (v as int) == 1).toList()
        : List.filled(7, true);
  }

  String get _houseId => widget.house['house_id'] as String? ?? '';

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.manrope(fontSize: 13)),
      backgroundColor: AppColors.sage700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _regenerate() async {
    setState(() => _regenLoading = true);
    try {
      final code = await AdminService.regenerateInviteCode(_houseId);
      if (mounted) {
        setState(() {
          _inviteCode = code;
          _regenLoading = false;
        });
        _showSnack('Invite code regenerated');
      }
    } catch (_) {
      if (mounted) setState(() => _regenLoading = false);
    }
  }

  Future<void> _rotate() async {
    setState(() => _rotateLoading = true);
    try {
      final token = await AdminService.rotateDeviceToken(_houseId);
      if (mounted) {
        setState(() {
          _deviceToken = token;
          _rotateLoading = false;
        });
        _showSnack('Device token rotated');
      }
    } catch (_) {
      if (mounted) setState(() => _rotateLoading = false);
    }
  }

  Future<void> _removeUser(String userId) async {
    setState(() => _removingUsers.add(userId));
    try {
      await AdminService.removeUser(_houseId, userId);
      if (mounted) {
        setState(() {
          _users.removeWhere((u) => u['user_id'] == userId);
          _removingUsers.remove(userId);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _removingUsers.remove(userId));
    }
  }

  Future<void> _saveMask() async {
    setState(() => _maskSaving = true);
    try {
      await AdminService.setSensorMask(
          _houseId, _mask.map((b) => b ? 1 : 0).toList());
      if (mounted) {
        setState(() {
          _maskSaving = false;
          _maskDirty = false;
        });
        _showSnack('Sensor mask saved');
      }
    } catch (_) {
      if (mounted) setState(() => _maskSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final residentName =
        widget.house['resident_name'] as String? ?? '—';
    final address = widget.house['address'] as String?;

    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            color: AppColors.card3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconWell(
                    tone: 'sage',
                    size: 48,
                    child: Icon(Icons.home_outlined, size: 22)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('House · $_houseId',
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink500,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 3),
                      Text(residentName,
                          style: GoogleFonts.newsreader(
                              fontSize: 22,
                              color: AppColors.ink900,
                              fontWeight: FontWeight.w500)),
                      if (address != null && address.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(address,
                            style: GoogleFonts.manrope(
                                fontSize: 13, color: AppColors.ink600)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AppTag(label: 'Active', tone: 'sage', icon: StatusDot(tone: 'ok')),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.line),

          // Body
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Credentials
                CopyChip(
                    label: 'Invite code',
                    value: _inviteCode,
                    mono: false),
                const SizedBox(height: 12),
                CopyChip(label: 'Device token', value: _deviceToken),
                const SizedBox(height: 14),

                // Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _regenLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : ConfirmButton(
                            label: 'Regenerate invite code',
                            icon: const Icon(Icons.refresh, size: 14),
                            onConfirmed: () => _regenerate(),
                          ),
                    _rotateLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : ConfirmButton(
                            label: 'Rotate device token',
                            icon: const Icon(Icons.refresh, size: 14),
                            danger: true,
                            onConfirmed: () => _rotate(),
                          ),
                  ],
                ),
                const SizedBox(height: 22),

                // Users
                Row(
                  children: [
                    Text('Active users · ${_users.length}',
                        style: GoogleFonts.newsreader(
                            fontSize: 17,
                            color: AppColors.ink900,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 10),
                if (_users.isEmpty)
                  Text('No users joined yet.',
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppColors.ink500)),
                for (final u in _users) ...[
                  _UserRow(
                    user: u,
                    removing: _removingUsers.contains(
                        u['user_id'] as String? ?? ''),
                    onRemove: () =>
                        _removeUser(u['user_id'] as String? ?? ''),
                  ),
                  if (u != _users.last) const SizedBox(height: 8),
                ],
                const SizedBox(height: 22),

                // Sensor mask
                Row(
                  children: [
                    Text('Sensor mask',
                        style: GoogleFonts.newsreader(
                            fontSize: 17,
                            color: AppColors.ink900,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Text('Toggle sensors on or off',
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.ink500)),
                  ],
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < _sensorList.length; i++) ...[
                  _SensorRow(
                    sensor: _sensorList[i],
                    enabled: i < _mask.length ? _mask[i] : true,
                    onChanged: (v) => setState(() {
                      _mask[i] = v;
                      _maskDirty = true;
                    }),
                  ),
                  if (i < _sensorList.length - 1) const SizedBox(height: 8),
                ],
                if (_maskDirty) ...[
                  const SizedBox(height: 14),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    buttonSize: AppButtonSize.sm,
                    onPressed: _maskSaving ? null : _saveMask,
                    trailing: _maskSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : null,
                    child: const Text('Save sensor mask'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── User row ─────────────────────────────────────────────────────
class _UserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool removing;
  final VoidCallback onRemove;
  const _UserRow(
      {required this.user, required this.removing, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final role = user['role'] as String? ?? '';
    final initials = username
        .split(RegExp(r'[\s_]+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.bgSoft,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
                color: AppColors.sage100, shape: BoxShape.circle),
            child: Center(
              child: Text(initials,
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.sage800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink900)),
                Text('$email · $role',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.ink500)),
              ],
            ),
          ),
          removing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : ConfirmButton(
                  label: 'Remove',
                  confirm: 'Remove',
                  danger: true,
                  onConfirmed: onRemove,
                ),
        ],
      ),
    );
  }
}

// ── Sensor row ───────────────────────────────────────────────────
class _SensorRow extends StatelessWidget {
  final _SensorDef sensor;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SensorRow(
      {required this.sensor, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1.0 : 0.7,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.bgSoft,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            IconWell(
                tone: enabled ? sensor.tone : 'cream',
                size: 36,
                child: Icon(sensor.icon, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sensor.label,
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink900)),
                  Text(
                    enabled ? 'Enabled' : 'Disabled',
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: enabled ? AppColors.sage700 : AppColors.ink500,
                    ),
                  ),
                ],
              ),
            ),
            AppToggle(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
