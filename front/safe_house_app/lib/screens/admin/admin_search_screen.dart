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

enum _Mode { loading, list, loadingDetail, detail, listError }

// ── Screen ───────────────────────────────────────────────────────
class AdminSearchScreen extends StatefulWidget {
  final VoidCallback? onNavigateToCreate;
  final ValueNotifier<int> activeTab;
  final int tabIndex;
  const AdminSearchScreen({
    super.key,
    required this.activeTab,
    required this.tabIndex,
    this.onNavigateToCreate,
  });

  @override
  State<AdminSearchScreen> createState() => _AdminSearchScreenState();
}

class _AdminSearchScreenState extends State<AdminSearchScreen> {
  final _controller = TextEditingController();

  _Mode _mode = _Mode.loading;
  List<Map<String, dynamic>> _allHouses = [];
  List<Map<String, dynamic>> _filtered = [];
  Map<String, dynamic>? _detailHouse;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    widget.activeTab.addListener(_onTabChanged);
    _loadList();
  }

  /// The shell keeps this screen alive in an IndexedStack, so coming back from
  /// Create House never re-runs initState — a house made on the other tab would
  /// stay missing from the list. Reload whenever the tab becomes visible, but
  /// leave an open house detail alone; the admin is in the middle of something.
  void _onTabChanged() {
    if (widget.activeTab.value != widget.tabIndex) return;
    if (_mode != _Mode.list && _mode != _Mode.listError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadList();
    });
  }

  Future<void> _loadList() async {
    setState(() => _mode = _Mode.loading);
    try {
      final houses = await AdminService.listHouses();
      if (mounted) {
        setState(() {
          _allHouses = houses;
          // Keep whatever is typed in the box applied, so a reload after a
          // delete or a create never shows a list that contradicts the query.
          _filtered = _matching(houses);
          _mode = _Mode.list;
          _errorMsg = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _mode = _Mode.listError;
          _errorMsg = 'Could not load houses. Check your connection.';
        });
      }
    }
  }

  List<Map<String, dynamic>> _matching(List<Map<String, dynamic>> houses) {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) return houses;
    return houses.where((h) {
      return (h['resident_name'] as String? ?? '').toLowerCase().contains(q) ||
          (h['house_id'] as String? ?? '').toLowerCase().contains(q) ||
          (h['address'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _onQueryChanged() {
    if (_mode != _Mode.list) return;
    setState(() => _filtered = _matching(_allHouses));
  }

  Future<void> _selectHouse(String houseId) async {
    setState(() {
      _mode = _Mode.loadingDetail;
      _errorMsg = null;
    });
    try {
      final house = await AdminService.getHouse(houseId);
      if (mounted) {
        setState(() {
          _detailHouse = house;
          _mode = _Mode.detail;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _mode = _Mode.list;
          _errorMsg = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _mode = _Mode.list;
          _errorMsg = 'Could not load house details.';
        });
      }
    }
  }

  void _backToList() {
    setState(() {
      _detailHouse = null;
      _mode = _Mode.list;
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
    widget.activeTab.removeListener(_onTabChanged);
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
            // Header
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

            // Body
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _Mode.loading:
        return const Center(child: CircularProgressIndicator());

      case _Mode.listError:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: AppColors.ink400),
                const SizedBox(height: 16),
                Text(_errorMsg ?? 'An error occurred.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                        fontSize: 14, color: AppColors.ink600)),
                const SizedBox(height: 20),
                AppButton(
                  variant: AppButtonVariant.primary,
                  onPressed: _loadList,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );

      case _Mode.loadingDetail:
        return const Center(child: CircularProgressIndicator());

      case _Mode.detail:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back link
              GestureDetector(
                onTap: _backToList,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios,
                          size: 13, color: AppColors.sage600),
                      const SizedBox(width: 4),
                      Text('All houses',
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.sage600)),
                    ],
                  ),
                ),
              ),
              _FoundCard(
                house: _detailHouse!,
                onDeleted: () {
                  _backToList();
                  _loadList();
                },
              ),
            ],
          ),
        );

      case _Mode.list:
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search field
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  border: Border.all(color: AppColors.line2, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Icon(Icons.search,
                          color: AppColors.ink500, size: 20),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: GoogleFonts.manrope(
                            fontSize: 14, color: AppColors.ink900),
                        decoration: InputDecoration(
                          hintText: 'Search by name, address or ID…',
                          hintStyle: GoogleFonts.manrope(
                              fontSize: 14, color: AppColors.ink400),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => _controller.clear(),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Icons.close,
                              color: AppColors.ink400, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Count / error inline. When the list is empty the card below
              // says so in full, so a count here would only repeat it.
              if (_errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(_errorMsg!,
                      style: GoogleFonts.manrope(
                          fontSize: 12, color: const Color(0xFF7A3727))),
                )
              else if (_filtered.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                      '${_filtered.length} house${_filtered.length == 1 ? '' : 's'}',
                      style: GoogleFonts.manrope(
                          fontSize: 12, color: AppColors.ink500)),
                )
              else
                const SizedBox(height: 4),

              // House list
              if (_allHouses.isEmpty)
                // A brand-new admin has nothing to search. Point at the only
                // useful next step instead of leaving the screen bare.
                _EmptyStateCard(
                  icon: Icons.home_outlined,
                  title: 'No houses yet',
                  body: 'Create your first house to generate the invite code '
                      'and device token for a new installation.',
                  onCreateNew: widget.onNavigateToCreate,
                )
              else if (_filtered.isEmpty)
                _EmptyStateCard(
                  icon: Icons.search,
                  title: 'No houses match',
                  body:
                      'Try a different name or address, or create a new house.',
                  onCreateNew: widget.onNavigateToCreate,
                )
              else
                for (int i = 0; i < _filtered.length; i++) ...[
                  _HouseSummaryTile(
                    house: _filtered[i],
                    onTap: () => _selectHouse(
                        _filtered[i]['house_id'] as String? ?? ''),
                  ),
                  if (i < _filtered.length - 1) const SizedBox(height: 10),
                ],
            ],
          ),
        );
    }
  }
}

// ── House summary tile (list view) ───────────────────────────────
class _HouseSummaryTile extends StatelessWidget {
  final Map<String, dynamic> house;
  final VoidCallback onTap;
  const _HouseSummaryTile({required this.house, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = house['resident_name'] as String? ?? '—';
    final address = house['address'] as String? ?? '';
    final userCount = house['user_count'] as int? ?? 0;
    final isActive = house['is_active'] as bool? ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const IconWell(
                tone: 'sage',
                size: 44,
                child: Icon(Icons.home_outlined, size: 20)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.newsreader(
                          fontSize: 17,
                          color: AppColors.ink900,
                          fontWeight: FontWeight.w500)),
                  if (address.isNotEmpty)
                    Text(address,
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.ink500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      AppTag(
                        label: isActive ? 'Active' : 'Inactive',
                        tone: isActive ? 'sage' : 'cream',
                        icon: StatusDot(tone: isActive ? 'ok' : 'off'),
                      ),
                      const SizedBox(width: 8),
                      Text('$userCount user${userCount == 1 ? '' : 's'}',
                          style: GoogleFonts.manrope(
                              fontSize: 11.5, color: AppColors.ink500)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.ink400),
          ],
        ),
      ),
    );
  }
}

// ── Empty state (nothing to search, or nothing matched) ──────────
class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onCreateNew;
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.body,
    this.onCreateNew,
  });

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
              border: Border.all(color: AppColors.line2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppColors.ink500),
          ),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.newsreader(
                  fontSize: 22,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 14, color: AppColors.ink600, height: 1.55),
          ),
          if (onCreateNew != null) ...[
            const SizedBox(height: 18),
            AppButton(
              variant: AppButtonVariant.primary,
              buttonSize: AppButtonSize.sm,
              leading: const Icon(Icons.add, size: 14),
              onPressed: onCreateNew,
              child: const Text('Create new house'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Found card (full detail) ─────────────────────────────────────
class _FoundCard extends StatefulWidget {
  final Map<String, dynamic> house;
  final VoidCallback? onDeleted;
  const _FoundCard({required this.house, this.onDeleted});

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
  bool _deleteLoading = false;
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

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.manrope(fontSize: 13)),
        backgroundColor: error ? AppColors.alert : AppColors.sage700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  /// Every action here is a two-tap confirm on something destructive. Failing
  /// quietly would leave the admin believing a token was rotated or a user
  /// removed when nothing happened, so say so.
  void _reportFailure(Object error, String fallback) {
    _showSnack(error is ApiException ? error.message : fallback, error: true);
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
    } catch (e) {
      if (mounted) {
        setState(() => _regenLoading = false);
        _reportFailure(e, 'Could not regenerate the invite code.');
      }
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
    } catch (e) {
      if (mounted) {
        setState(() => _rotateLoading = false);
        _reportFailure(e, 'Could not rotate the device token.');
      }
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
        _showSnack('User removed from this house');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _removingUsers.remove(userId));
        _reportFailure(e, 'Could not remove that user.');
      }
    }
  }

  Future<void> _deleteHouse() async {
    final residentName =
        widget.house['resident_name'] as String? ?? 'this house';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete house?',
            style: GoogleFonts.newsreader(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: AppColors.ink900)),
        content: Text(
          'Are you sure you want to permanently delete $residentName and all its data? This cannot be undone.',
          style:
              GoogleFonts.manrope(fontSize: 14, color: AppColors.ink700, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: AppColors.ink600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete permanently',
                style: GoogleFonts.manrope(
                    color: const Color(0xFF7A3727),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleteLoading = true);
    try {
      await AdminService.deleteHouse(_houseId);
      if (mounted) widget.onDeleted?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _deleteLoading = false);
        _reportFailure(e, 'Failed to delete house. Please try again.');
      }
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
    } catch (e) {
      if (mounted) {
        setState(() => _maskSaving = false);
        _reportFailure(e, 'Could not save the sensor mask.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final residentName = widget.house['resident_name'] as String? ?? '—';
    final address = widget.house['address'] as String?;
    final isActive = widget.house['is_active'] as bool? ?? false;

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
                // A house stays inactive until its ESP32 first reports in, so
                // this has to read the flag — the list tile already does.
                AppTag(
                    label: isActive ? 'Active' : 'Inactive',
                    tone: isActive ? 'sage' : 'cream',
                    icon: StatusDot(tone: isActive ? 'ok' : 'off')),
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
                CopyChip(label: 'Invite code', value: _inviteCode, mono: false),
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
                Text('Active users · ${_users.length}',
                    style: GoogleFonts.newsreader(
                        fontSize: 17,
                        color: AppColors.ink900,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                if (_users.isEmpty)
                  Text('No users joined yet.',
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppColors.ink500)),
                for (final u in _users) ...[
                  _UserRow(
                    user: u,
                    removing:
                        _removingUsers.contains(u['user_id'] as String? ?? ''),
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
                const SizedBox(height: 28),
                Container(height: 1, color: AppColors.line),
                const SizedBox(height: 20),
                _deleteLoading
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : AppButton(
                        variant: AppButtonVariant.ghost,
                        leading: const Icon(Icons.delete_outline,
                            size: 16, color: Color(0xFF7A3727)),
                        onPressed: _deleteHouse,
                        child: Text(
                          'Delete house',
                          style: GoogleFonts.manrope(
                              color: const Color(0xFF7A3727),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
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
                      color:
                          enabled ? AppColors.sage700 : AppColors.ink500,
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
