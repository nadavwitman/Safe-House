import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/alert_ack_store.dart';
import '../../services/auth_state.dart';
import '../../services/insights_service.dart';

// ── Sensor presentation ───────────────────────────────────────────
// The server names a zone inconsistently depending on which producer wrote the
// alert: analyze_routes passes the AI's own sensor id, device_health passes the
// display name from SENSOR_NAMES ('Medication', 'Bedroom'), and the app elsewhere
// uses short ids ('meds', 'bed'). Keying on every form it can arrive in is cheaper
// than normalising on the server, and an unknown key just falls back to a bell.
class _SensorLook {
  final String name;
  final IconData icon;
  final String tone;
  const _SensorLook(this.name, this.icon, this.tone);
}

const _unknownSensor =
    _SensorLook('General monitoring', Icons.notifications_outlined, 'sage');

const _sensorLook = <String, _SensorLook>{
  'door': _SensorLook('Front Door', Icons.door_front_door_outlined, 'sage'),
  'Door': _SensorLook('Front Door', Icons.door_front_door_outlined, 'sage'),
  'Front Door': _SensorLook('Front Door', Icons.door_front_door_outlined, 'sage'),
  'kitchen': _SensorLook('Kitchen', Icons.kitchen_outlined, 'warm'),
  'Kitchen': _SensorLook('Kitchen', Icons.kitchen_outlined, 'warm'),
  'bath': _SensorLook('Bathroom', Icons.bathtub_outlined, 'sky'),
  'Bathroom': _SensorLook('Bathroom', Icons.bathtub_outlined, 'sky'),
  'toilet': _SensorLook('Toilet', Icons.water_drop_outlined, 'cream'),
  'Toilet': _SensorLook('Toilet', Icons.water_drop_outlined, 'cream'),
  'meds': _SensorLook('Medication Cabinet', Icons.medication_outlined, 'plum'),
  'Medication': _SensorLook('Medication Cabinet', Icons.medication_outlined, 'plum'),
  'Medication Cabinet':
      _SensorLook('Medication Cabinet', Icons.medication_outlined, 'plum'),
  'bed': _SensorLook('Bed', Icons.bed_outlined, 'sage'),
  'Bed': _SensorLook('Bed', Icons.bed_outlined, 'sage'),
  'Bedroom': _SensorLook('Bed', Icons.bed_outlined, 'sage'),
  'living': _SensorLook('Living Room', Icons.weekend_outlined, 'cream'),
  'Living Room': _SensorLook('Living Room', Icons.weekend_outlined, 'cream'),
  'Device': _SensorLook('Safe House device', Icons.router_outlined, 'cream'),
  'System_Vector': _unknownSensor,
};

// ── One alert, as the screen needs it ─────────────────────────────
class _Alert {
  final String id;
  final DateTime time;
  final bool isEmergency;
  final String sensorId;
  final String title;
  final String body;
  final IconData icon;

  const _Alert({
    required this.id,
    required this.time,
    required this.isEmergency,
    required this.sensorId,
    required this.title,
    required this.body,
    required this.icon,
  });

  _SensorLook get look => _sensorLook[sensorId] ?? _unknownSensor;

  /// Builds a display alert from a raw history record, or null if the record has
  /// no usable timestamp — a card with no time cannot be grouped under a day.
  ///
  /// Severity collapses to two values because the design has two. Only an AI
  /// anomaly can be an Emergency; a quiet device or a suspect sensor is a Warning,
  /// which is the honest reading — it means "the system may not be watching", not
  /// "something happened to the resident".
  static _Alert? from(Map<String, dynamic> raw) {
    final parsed = DateTime.tryParse(raw['time'] as String? ?? '');
    if (parsed == null) return null;

    final type = raw['type'] as String? ?? 'ai';
    final sensorId = raw['sensor_id'] as String? ?? '';
    final look = _sensorLook[sensorId] ?? _unknownSensor;

    switch (type) {
      case 'device_offline':
        final minutes = (raw['minutes_silent'] as num?)?.toInt();
        return _Alert(
          id: raw['id'] as String? ?? '',
          time: parsed.toLocal(),
          isEmergency: false,
          sensorId: sensorId,
          icon: Icons.wifi_off_rounded,
          title: 'Device not responding',
          body: minutes == null
              ? 'The Safe House device has stopped reporting. Please check that it '
                  'has power and Wi-Fi.'
              : 'No signal for $minutes minutes. Please check that the device has '
                  'power and Wi-Fi.',
        );
      case 'sensor_fault':
        final hours = (raw['hours_silent'] as num?)?.toInt();
        final span = hours == null ? 'a long time' : 'over $hours hours';
        return _Alert(
          id: raw['id'] as String? ?? '',
          time: parsed.toLocal(),
          isEmergency: false,
          sensorId: sensorId,
          icon: Icons.sensors_off_rounded,
          title: 'Possible sensor fault',
          body: "The ${look.name} sensor hasn't reported in $span. It may be "
              'faulty, disconnected, or out of battery.',
        );
      default:
        final isEmergency = raw['decision'] == 'Emergency';
        final title = raw['title'] as String?;
        final note = raw['note'] as String?;
        return _Alert(
          id: raw['id'] as String? ?? '',
          time: parsed.toLocal(),
          isEmergency: isEmergency,
          sensorId: sensorId,
          icon: isEmergency
              ? Icons.emergency_outlined
              : Icons.warning_amber_rounded,
          // The server composes a situation-specific message for AI anomalies.
          // The fallbacks only run against records written before it did.
          title: (title != null && title.isNotEmpty)
              ? title
              : (isEmergency
                  ? 'Emergency — ${look.name}'
                  : 'Warning — ${look.name}'),
          body: (note != null && note.isNotEmpty)
              ? note
              : (isEmergency
                  ? 'Extended lack of motion detected near ${look.name}.'
                  : 'Unusual pattern detected near ${look.name}.'),
        );
    }
  }
}

// ── Alerts Screen ─────────────────────────────────────────────────
class AlertsScreen extends StatefulWidget {
  /// The shell's current tab. The screen lives in an IndexedStack, so initState
  /// runs once for the life of the app — without this it would show whatever it
  /// loaded at launch until the process restarted.
  final ValueListenable<int> activeTab;
  final int tabIndex;

  const AlertsScreen({
    super.key,
    required this.activeTab,
    required this.tabIndex,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // The 7-day window is the server's, fixed and not a parameter — the header says
  // "Last 7 days" because that is all the endpoint will ever return.
  List<_Alert>? _alerts;
  Set<String> _acked = <String>{};
  String _filter = 'all';
  bool _loading = true;
  bool _fetching = false;
  String? _error;
  // Which house the loaded list belongs to, so switching houses re-fetches rather
  // than showing the previous resident's alerts.
  String? _loadedHouse;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.activeTab.value != widget.tabIndex) return;
    // The shell mutates the notifier inside its own setState, so this fires
    // mid-build. Defer, or _load's setState lands during the parent's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (_fetching) return;
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) {
      setState(() {
        _loading = false;
        _alerts = const [];
      });
      return;
    }
    // A house switch invalidates both the list and the acknowledgements, which are
    // stored per house. Blank them before the fetch so the old resident's alerts
    // are never on screen next to the new one's name — and drop the badge with
    // them, since a count for the previous house is worse than no count.
    final switched = _loadedHouse != null && _loadedHouse != houseId;
    _loadedHouse = houseId;
    if (switched) {
      AuthState.instance.unreadAlerts.value = 0;
      setState(() {
        _alerts = null;
        _acked = <String>{};
        _loading = true;
        _error = null;
      });
    }
    _fetching = true;
    try {
      final raw = await InsightsService.getAlerts(
        houseId,
        limit: 100,
        excludeNormal: true,
      );
      final alerts = _deduplicate(raw);
      // Only prune against a fetch that succeeded and covers the whole window —
      // pruning on a partial response would forget acknowledgements for alerts
      // still on screen and resurface them all as unread. The alert currently in
      // effect is spared even when it has aged out of the window, because the
      // dashboard banner is still showing it.
      final liveIds = alerts.map((a) => a.id).toSet();
      await AlertAckStore.prune(houseId, liveIds,
          keep: AuthState.instance.currentAlertId.value);
      final acked = await AlertAckStore.read(houseId);
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _acked = acked;
        _loading = false;
        _error = null;
      });
      _publishUnread();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Keep whatever is already on screen. A failed refresh should not blank a
        // list the user was reading.
        _error = _alerts == null
            ? "Couldn't load alerts. Pull down to try again."
            : "Couldn't refresh — showing what we last loaded.";
      });
    } finally {
      _fetching = false;
    }
  }

  /// Merges consecutive alerts of the same kind within five minutes.
  ///
  /// The producers can fire in bursts — a sensor-fault sweep re-checks on a timer,
  /// and an anomaly that flickers across the decision boundary writes an entry each
  /// time. Collapsing them here rather than on the server keeps the counters and
  /// the list telling the same story, since both read this list.
  List<_Alert> _deduplicate(List<Map<String, dynamic>> raw) {
    final result = <_Alert>[];
    for (final entry in raw) {
      final alert = _Alert.from(entry);
      if (alert == null || alert.id.isEmpty) continue;
      final prev = result.isEmpty ? null : result.last;
      if (prev != null &&
          prev.isEmergency == alert.isEmergency &&
          prev.sensorId == alert.sensorId &&
          prev.title == alert.title &&
          prev.time.difference(alert.time).abs().inMinutes < 5) {
        continue;
      }
      result.add(alert);
    }
    return result;
  }

  void _publishUnread() {
    final list = _alerts;
    if (list == null) return;
    AuthState.instance.unreadAlerts.value =
        list.where((a) => !_acked.contains(a.id)).length;
  }

  Future<void> _acknowledge(_Alert alert) async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    setState(() => _acked = {..._acked, alert.id});
    _publishUnread();
    await AlertAckStore.add(houseId, alert.id);
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final ok = await launchUrl(uri).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call to $phone')),
      );
    }
  }

  // ── Day grouping ────────────────────────────────────────────────
  /// "Today" / "Yesterday" / "Wed May 14", matching the design. Compared on
  /// calendar date rather than elapsed hours, so an alert at 23:50 last night reads
  /// as Yesterday at 00:30 rather than as "0 days ago".
  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE MMM d').format(t);
  }

  List<({String day, List<_Alert> items})> _group(List<_Alert> items) {
    final groups = <({String day, List<_Alert> items})>[];
    for (final a in items) {
      final label = _dayLabel(a.time);
      if (groups.isNotEmpty && groups.last.day == label) {
        groups.last.items.add(a);
      } else {
        groups.add((day: label, items: [a]));
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthState.instance;
    final activeId = auth.activeHouseId;
    final houses = auth.currentUser?.houses ?? [];
    final activeHouse = houses.isEmpty
        ? null
        : houses.firstWhere((h) => h['house_id'] == activeId,
            orElse: () => houses.first);
    final phone =
        (activeHouse?['emergency_contact_phone'] as String?)?.trim() ?? '';

    final all = _alerts ?? const <_Alert>[];
    final emergencies = all.where((a) => a.isEmergency).length;
    final warnings = all.length - emergencies;
    final unread = all.where((a) => !_acked.contains(a.id)).length;

    final filtered = all.where((a) {
      switch (_filter) {
        case 'unack':
          return !_acked.contains(a.id);
        case 'emergency':
          return a.isEmergency;
        case 'warning':
          return !a.isEmergency;
        default:
          return true;
      }
    }).toList();

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
                  Text('LAST 7 DAYS',
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink500,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text('Alerts',
                      style: GoogleFonts.newsreader(
                          fontSize: 28,
                          color: AppColors.ink900,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.sage800,
                child: SingleChildScrollView(
                  // Always scrollable, so pull-to-refresh still works when the
                  // content is shorter than the viewport (empty and error states).
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: _StatCard(
                                  'Total · 7 days', all.length, 'ok')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _StatCard(
                                  'Emergencies', emergencies, 'alert')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _StatCard('Warnings', warnings, 'warn')),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          AppFilterChip(
                            label: 'All',
                            count: all.length,
                            active: _filter == 'all',
                            onTap: () => setState(() => _filter = 'all'),
                            dotColor: AppColors.sage600,
                          ),
                          AppFilterChip(
                            label: 'Unread',
                            count: unread,
                            active: _filter == 'unack',
                            onTap: () => setState(() => _filter = 'unack'),
                            dotColor: AppColors.alert,
                          ),
                          AppFilterChip(
                            label: 'Emergency',
                            count: emergencies,
                            active: _filter == 'emergency',
                            onTap: () => setState(() => _filter = 'emergency'),
                            dotColor: AppColors.alert,
                          ),
                          AppFilterChip(
                            label: 'Warning',
                            count: warnings,
                            active: _filter == 'warning',
                            onTap: () => setState(() => _filter = 'warning'),
                            dotColor: AppColors.warn,
                          ),
                          // Not a filter — it swaps the list for an explainer. It
                          // sits in the same row because that is where a reader
                          // looking at an alert they don't understand already is,
                          // and it carries no count so it doesn't read as one.
                          AppFilterChip(
                            label: 'About',
                            active: _filter == 'about',
                            onTap: () => setState(() => _filter = 'about'),
                            dotColor: AppColors.ink400,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_error != null) ...[
                        _ErrorNote(_error!),
                        const SizedBox(height: 12),
                      ],
                      if (_filter == 'about')
                        const _AboutPanel()
                      else if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(36),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.sage700)),
                        )
                      else if (filtered.isEmpty)
                        _EmptyState(filter: _filter, hasAny: all.isNotEmpty)
                      else
                        for (final g in _group(filtered)) ...[
                          DayHeader(day: g.day, count: g.items.length),
                          const SizedBox(height: 8),
                          for (final a in g.items) ...[
                            _AlertItem(
                              alert: a,
                              acknowledged: _acked.contains(a.id),
                              onAcknowledge: () => _acknowledge(a),
                              onCall:
                                  phone.isEmpty ? null : () => _call(phone),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final String tone;
  const _StatCard(this.label, this.value, this.tone);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(tone: tone, size: 7),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label.toUpperCase(),
                    maxLines: 2,
                    style: GoogleFonts.manrope(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink500,
                        height: 1.3)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('$value',
              style: GoogleFonts.newsreader(
                  fontSize: 24,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500,
                  height: 1)),
        ],
      ),
    );
  }
}

// ── Single alert card ─────────────────────────────────────────────
class _AlertItem extends StatelessWidget {
  final _Alert alert;
  final bool acknowledged;
  final VoidCallback onAcknowledge;
  // Null when the house has no emergency contact number on file, which hides the
  // Call button rather than offering a dial that cannot go anywhere.
  final VoidCallback? onCall;

  const _AlertItem({
    required this.alert,
    required this.acknowledged,
    required this.onAcknowledge,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final isEmergency = alert.isEmergency;
    final look = alert.look;
    final sevBg = isEmergency ? AppColors.alertSoft : AppColors.warnSoft;
    final sevFg =
        isEmergency ? const Color(0xFF7A3727) : const Color(0xFF7A5419);
    final sevBd =
        isEmergency ? const Color(0xFFE6BFB1) : const Color(0xFFEAD7A4);
    final dotColor = isEmergency ? AppColors.alert : AppColors.warn;

    return Opacity(
      // Acknowledged alerts stay in the list as history but recede, so the eye
      // lands on what still needs attention.
      opacity: acknowledged ? 0.78 : 1.0,
      child: AppCard(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // The well carries the sensor's own colour and the alert's icon:
                // the severity is already said twice over, by the pill and by the
                // dot, so the well is free to say *where* instead.
                IconWell(tone: look.tone, size: 38, child: Icon(alert.icon)),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: sevBg,
                          border: Border.all(color: sevBd),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(isEmergency ? 'EMERGENCY' : 'WARNING',
                            style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: sevFg,
                                letterSpacing: 0.4)),
                      ),
                      Text(
                          '${look.name} · ${DateFormat('HH:mm').format(alert.time)}',
                          style: GoogleFonts.manrope(
                              fontSize: 12, color: AppColors.ink500)),
                      if (acknowledged)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check,
                                size: 12, color: AppColors.sage700),
                            const SizedBox(width: 4),
                            Text('Acknowledged',
                                style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    color: AppColors.ink500,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(alert.title,
                      style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink900,
                          height: 1.3)),
                  const SizedBox(height: 4),
                  Text(alert.body,
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppColors.ink700, height: 1.5)),
                  if (!acknowledged) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (onCall != null)
                          AppButton(
                            variant: isEmergency
                                ? AppButtonVariant.danger
                                : AppButtonVariant.soft,
                            buttonSize: AppButtonSize.sm,
                            leading: const Icon(Icons.phone, size: 14),
                            onPressed: onCall,
                            child: const Text('Call'),
                          ),
                        AppButton(
                          variant: isEmergency
                              ? AppButtonVariant.outline
                              : AppButtonVariant.soft,
                          buttonSize: AppButtonSize.sm,
                          onPressed: onAcknowledge,
                          child: const Text('Acknowledge'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String filter;
  // Distinguishes "this house had a calm week" from "this filter is empty",
  // which want different words.
  final bool hasAny;
  const _EmptyState({required this.filter, required this.hasAny});

  @override
  Widget build(BuildContext context) {
    final String message;
    if (!hasAny) {
      message = 'No alerts in the last 7 days. Everything has been calm.';
    } else if (filter == 'unack') {
      message = "You've acknowledged everything from the last 7 days.";
    } else {
      message = 'No alerts match this filter. Everything has been calm.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.sage50,
        border: Border.all(color: AppColors.sage200),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const IconWell(tone: 'sage', size: 56, child: Icon(Icons.check)),
          const SizedBox(height: 12),
          Text('All quiet',
              style: GoogleFonts.newsreader(
                  fontSize: 20,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 13.5, color: AppColors.ink700, height: 1.5)),
        ],
      ),
    );
  }
}

// ── Error note ────────────────────────────────────────────────────
class _ErrorNote extends StatelessWidget {
  final String message;
  const _ErrorNote(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnSoft,
        border: Border.all(color: const Color(0xFFEAD7A4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: Color(0xFF7A5419)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: const Color(0xFF7A5419),
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── About panel ───────────────────────────────────────────────────
/// What the alert types mean and how to keep them arriving. Behind a chip rather
/// than above the list: it answers a question a reader has once, and the list is
/// what they open this tab for every other time.
class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconWell(
                      tone: 'sage',
                      size: 44,
                      child: Icon(Icons.notifications_active_outlined)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Real-time push alerts',
                            style: GoogleFonts.newsreader(
                                fontSize: 18,
                                color: AppColors.ink900,
                                fontWeight: FontWeight.w500)),
                        Text('Delivered instantly to your device',
                            style: GoogleFonts.manrope(
                                fontSize: 12.5, color: AppColors.ink500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "When the system detects an unusual pattern — a missed medication, "
                "extended stillness, or a door left open — you'll receive a push "
                "notification immediately. Everything sent in the last 7 days is "
                "listed here.",
                style: GoogleFonts.manrope(
                    fontSize: 13.5, color: AppColors.ink700, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _TypeCard(
          icon: Icons.emergency_outlined,
          tone: 'coral',
          label: 'Emergency',
          description:
              'Critical situations needing immediate attention, such as a fall '
              'risk or prolonged inactivity. These cards offer a direct call to '
              'the emergency contact.',
        ),
        const SizedBox(height: 10),
        const _TypeCard(
          icon: Icons.warning_amber_rounded,
          tone: 'warm',
          label: 'Warning',
          description:
              "Non-critical anomalies — a routine that's slightly off, unusual "
              'timing, or a missed event. A call button is offered here too, '
              'in case you\'d rather check in directly.',
        ),
        const SizedBox(height: 10),
        const _TypeCard(
          icon: Icons.wifi_off_rounded,
          tone: 'cream',
          label: 'Device offline',
          description:
              'Sent when the Safe House device stops reporting for 30+ minutes. '
              'Listed as a warning, because it means the house is unwatched '
              'rather than that something has happened.',
        ),
        const SizedBox(height: 10),
        const _TypeCard(
          icon: Icons.sensors_off_rounded,
          tone: 'cream',
          label: 'Possible sensor fault',
          description:
              'Sent when one sensor goes quiet for an unusually long time — it '
              'may be faulty, disconnected, or out of battery.',
        ),
        const SizedBox(height: 10),
        const _TypeCard(
          icon: Icons.check_circle_outline,
          tone: 'sage',
          label: 'Acknowledging',
          description:
              'Acknowledging marks an alert as read on this device and removes it '
              'from Unread. It stays in the list as history, and it does not '
              "change the house's status — only the system can clear that.",
        ),
        const SizedBox(height: 10),
        const _TypeCard(
          icon: Icons.phone,
          tone: 'coral',
          label: 'Call button',
          description:
              "Dials the house's emergency contact directly from the alert card. "
              "It only appears when an emergency contact number is on file for "
              "the house, and only until the alert is acknowledged.",
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MAKE SURE NOTIFICATIONS ARE ON',
                  style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink500,
                      letterSpacing: 0.7)),
              const SizedBox(height: 10),
              for (final tip in const [
                'Allow notifications for Safe House in your phone settings.',
                'Keep the app installed — uninstalling stops alerts.',
                'Disable battery optimization for Safe House to ensure delivery.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: AppColors.sage700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tip,
                            style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.ink700,
                                height: 1.5)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  final IconData icon;
  final String tone, label, description;
  const _TypeCard({
    required this.icon,
    required this.tone,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconWell(tone: tone, size: 38, child: Icon(icon)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink900)),
                const SizedBox(height: 3),
                Text(description,
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: AppColors.ink600, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
