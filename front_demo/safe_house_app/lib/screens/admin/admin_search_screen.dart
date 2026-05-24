import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../screens/auth/sign_in_screen.dart';

// ── Data ─────────────────────────────────────────────────────

class _SensorDef {
  final String id, label, tone;
  final IconData icon;
  const _SensorDef(this.id, this.icon, this.label, this.tone);
}

const _sensorList = [
  _SensorDef('door',    Icons.door_front_door_outlined, 'Front Door',         'sage'),
  _SensorDef('kitchen', Icons.kitchen_outlined,          'Kitchen',            'warm'),
  _SensorDef('bed',     Icons.bed_outlined,              'Bedroom',            'sage'),
  _SensorDef('bath',    Icons.bathtub_outlined,          'Bathroom',           'sky'),
  _SensorDef('toilet',  Icons.water_drop_outlined,       'Toilet',             'sky'),
  _SensorDef('meds',    Icons.medication_outlined,       'Medication Cabinet', 'plum'),
  _SensorDef('living',  Icons.weekend_outlined,          'Living Room',        'sage'),
];

final _mockUsers = [
  {'name': 'Mara Reyes',       'email': 'mara@family.com',     'role': 'Family'},
  {'name': 'David Reyes',      'email': 'david.r@family.com',  'role': 'Family'},
  {'name': 'Care Aide · Ines', 'email': 'ines@careco.io',      'role': 'Caregiver'},
];

enum _SearchState { empty, noresult, found }

// ── Screen ───────────────────────────────────────────────────

class AdminSearchScreen extends StatefulWidget {
  final VoidCallback? onNavigateToCreate;
  const AdminSearchScreen({super.key, this.onNavigateToCreate});

  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> {
  final _controller = TextEditingController();
  _SearchState _state = _SearchState.empty;

  void _search() {
    final q = _controller.text.trim().toUpperCase();
    if (q.isEmpty) return;
    setState(() {
      _state = q == 'AHE-4421-EL' ? _SearchState.found : _SearchState.noresult;
    });
  }

  void _reset() {
    setState(() {
      _controller.clear();
      _state = _SearchState.empty;
    });
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
                      Text('ADMIN', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink500, letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Text('House Search', style: GoogleFonts.newsreader(fontSize: 28, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const SignInScreen()),
                    ),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), shape: BoxShape.circle),
                      child: const Icon(Icons.logout, size: 17, color: AppColors.ink700),
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
                              border: Border.all(color: AppColors.line2, width: 1.5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 14),
                                  child: Icon(Icons.search, color: AppColors.ink500, size: 20),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    onSubmitted: (_) => _search(),
                                    textCapitalization: TextCapitalization.characters,
                                    style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink900),
                                    decoration: InputDecoration(
                                      hintText: 'Search by House ID (e.g. AHE-4421-EL)',
                                      hintStyle: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink400),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
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
                          leading: const Icon(Icons.search, size: 16),
                          onPressed: _search,
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
                    if (_state == _SearchState.found)
                      _FoundCard(initialUsers: _mockUsers),
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

// ── No-result card ────────────────────────────────────────────

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
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.bgSoft,
              border: Border.all(color: AppColors.line2, style: BorderStyle.solid),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search, size: 28, color: AppColors.ink500),
          ),
          const SizedBox(height: 14),
          Text('No house found with this ID', style: GoogleFonts.newsreader(fontSize: 22, color: AppColors.ink900, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            'Double-check the ID for typos, or create a new house if one hasn\'t been set up yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink600, height: 1.55),
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

// ── Found card ────────────────────────────────────────────────

class _FoundCard extends StatefulWidget {
  final List<Map<String, String>> initialUsers;
  const _FoundCard({required this.initialUsers});

  @override
  State<_FoundCard> createState() => _FoundCardState();
}

class _FoundCardState extends State<_FoundCard> {
  late List<Map<String, String>> _users;
  late Map<String, bool> _sensors;

  @override
  void initState() {
    super.initState();
    _users = List.from(widget.initialUsers);
    _sensors = {
      'door': true, 'kitchen': true, 'bed': true,
      'bath': true, 'toilet': true, 'meds': true, 'living': false,
    };
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.manrope(fontSize: 13)),
      backgroundColor: AppColors.sage700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            color: AppColors.card3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconWell(tone: 'sage', size: 48, child: const Icon(Icons.home_outlined, size: 22)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('House · AHE-4421-EL',
                          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.8)),
                      const SizedBox(height: 3),
                      Text('Eleanor Reyes',
                          style: GoogleFonts.newsreader(fontSize: 22, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('24 Linden St · Apt 3B · Brooklyn, NY',
                          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink600)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AppTag(label: 'Active', tone: 'sage', icon: StatusDot(tone: 'ok')),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.line),

          // ── Body
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Credentials
                const CopyChip(label: 'Invite code', value: 'AHE-7842-FAM', mono: false),
                const SizedBox(height: 12),
                const CopyChip(label: 'Device token', value: 'esp32_5dc9f1a4-3b88-4f2e-91ce-7a01c2b9ee70'),
                const SizedBox(height: 14),

                // Confirm actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ConfirmButton(
                      label: 'Regenerate invite code',
                      icon: const Icon(Icons.refresh, size: 14),
                      onConfirmed: () => _showSnack('Invite code regenerated'),
                    ),
                    ConfirmButton(
                      label: 'Rotate device token',
                      icon: const Icon(Icons.refresh, size: 14),
                      danger: true,
                      onConfirmed: () => _showSnack('Device token rotated'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Active users
                Row(
                  children: [
                    Text('Active users · ${_users.length}',
                        style: GoogleFonts.newsreader(fontSize: 17, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    AppButton(
                      variant: AppButtonVariant.ghost,
                      buttonSize: AppButtonSize.sm,
                      leading: const Icon(Icons.add, size: 14),
                      onPressed: () {},
                      child: const Text('Invite'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final u in _users) ...[
                  _UserRow(
                    user: u,
                    onRemove: () => setState(() => _users.remove(u)),
                  ),
                  if (u != _users.last) const SizedBox(height: 8),
                ],
                const SizedBox(height: 22),

                // Sensor mask
                Row(
                  children: [
                    Text('Sensor mask',
                        style: GoogleFonts.newsreader(fontSize: 17, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Text('Toggle sensors on or off',
                        style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500)),
                  ],
                ),
                const SizedBox(height: 10),
                for (final s in _sensorList) ...[
                  _SensorRow(
                    sensor: s,
                    enabled: _sensors[s.id] ?? true,
                    onChanged: (v) => setState(() => _sensors[s.id] = v),
                  ),
                  if (s != _sensorList.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── User row ──────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  final Map<String, String> user;
  final VoidCallback onRemove;
  const _UserRow({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final initials = (user['name'] ?? '')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
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
            width: 36, height: 36,
            decoration: const BoxDecoration(color: AppColors.sage100, shape: BoxShape.circle),
            child: Center(
              child: Text(initials, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sage800)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['name'] ?? '', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink900)),
                Text(
                  '${user['email']} · ${user['role']}',
                  style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500),
                ),
              ],
            ),
          ),
          AppButton(
            variant: AppButtonVariant.ghost,
            buttonSize: AppButtonSize.sm,
            onPressed: onRemove,
            child: Text('Remove', style: TextStyle(color: AppColors.alert)),
          ),
        ],
      ),
    );
  }
}

// ── Sensor row ────────────────────────────────────────────────

class _SensorRow extends StatelessWidget {
  final _SensorDef sensor;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _SensorRow({required this.sensor, required this.enabled, required this.onChanged});

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
            IconWell(tone: enabled ? sensor.tone : 'cream', size: 36, child: Icon(sensor.icon, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sensor.label, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink900)),
                  Text(
                    enabled ? 'Enabled' : 'Disabled',
                    style: GoogleFonts.manrope(
                      fontSize: 11.5, fontWeight: FontWeight.w600,
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
