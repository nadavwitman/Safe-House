import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';

class AlertModel {
  final String id, day, time, severity, sensor, title, body;
  final bool ack;
  const AlertModel({required this.id, required this.day, required this.time,
    required this.severity, required this.sensor, required this.title,
    required this.body, required this.ack});
}

const _alerts = [
  AlertModel(id: 'a1', day: 'Today', time: '14:32', severity: 'warning', sensor: 'meds',
    title: 'Medication cabinet not opened',
    body: 'Evening dose hasn\'t been taken yet. Usual time: 9:00 PM.', ack: false),
  AlertModel(id: 'a2', day: 'Today', time: '02:14', severity: 'emergency', sensor: 'door',
    title: 'Front door opened, no return',
    body: 'Door opened at 02:14 AM and no return motion detected for 2 hours.', ack: false),
  AlertModel(id: 'a3', day: 'Yesterday', time: '21:48', severity: 'warning', sensor: 'kitchen',
    title: 'No dinner activity detected',
    body: 'Kitchen has been quiet since 5:12 PM. Usually active between 6–7 PM.', ack: true),
  AlertModel(id: 'a4', day: 'Wed May 14', time: '03:42', severity: 'warning', sensor: 'bed',
    title: 'Restless night',
    body: '4 bed exits between midnight and 4 AM — outside Eleanor\'s pattern.', ack: true),
  AlertModel(id: 'a5', day: 'Tue May 13', time: '17:20', severity: 'warning', sensor: 'living',
    title: 'Unusually long stillness',
    body: 'No motion in the living room for 3h 12m during typical active hours.', ack: true),
  AlertModel(id: 'a6', day: 'Sun May 11', time: '09:08', severity: 'emergency', sensor: 'bath',
    title: 'Fall risk: long stillness in bathroom',
    body: 'No motion in bathroom for 18 minutes after entry. Resolved when motion resumed.', ack: true),
];

const _sensorIcons = {
  'door':    (Icons.door_front_door_outlined, 'sage'),
  'kitchen': (Icons.kitchen_outlined, 'warm'),
  'bath':    (Icons.bathtub_outlined, 'sky'),
  'toilet':  (Icons.water_drop_outlined, 'cream'),
  'meds':    (Icons.medication_outlined, 'plum'),
  'bed':     (Icons.bed_outlined, 'sage'),
  'living':  (Icons.weekend_outlined, 'cream'),
};
const _sensorNames = {
  'door': 'Front Door', 'kitchen': 'Kitchen', 'bath': 'Bathroom',
  'toilet': 'Toilet', 'meds': 'Medication Cabinet', 'bed': 'Bed', 'living': 'Living Room',
};

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _filter = 'all';

  List<AlertModel> get _filtered => _alerts.where((a) {
    if (_filter == 'all') return true;
    if (_filter == 'unack') return !a.ack;
    return a.severity == _filter;
  }).toList();

  List<({String day, List<AlertModel> items})> get _grouped {
    final List<({String day, List<AlertModel> items})> groups = [];
    for (final a in _filtered) {
      if (groups.isNotEmpty && groups.last.day == a.day) {
        groups.last.items.add(a);
      } else {
        groups.add((day: a.day, items: [a]));
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final total = _alerts.length;
    final emergencies = _alerts.where((a) => a.severity == 'emergency').length;
    final warnings = _alerts.where((a) => a.severity == 'warning').length;
    final unread = _alerts.where((a) => !a.ack).length;
    final groups = _grouped;

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
                      Text('LAST 7 DAYS', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink500, letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Text('Alerts', style: GoogleFonts.newsreader(fontSize: 28, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), shape: BoxShape.circle),
                    child: const Icon(Icons.settings_outlined, size: 17, color: AppColors.ink700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary row
                    Row(
                      children: [
                        Expanded(child: _StatCard('Total · 7 days', total, 'ok')),
                        const SizedBox(width: 10),
                        Expanded(child: _StatCard('Emergencies', emergencies, 'alert')),
                        const SizedBox(width: 10),
                        Expanded(child: _StatCard('Warnings', warnings, 'warn')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Filter chips
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        AppFilterChip(label: 'All', count: total, active: _filter == 'all', onTap: () => setState(() => _filter = 'all'), dotColor: AppColors.sage600),
                        AppFilterChip(label: 'Unread', count: unread, active: _filter == 'unack', onTap: () => setState(() => _filter = 'unack'), dotColor: AppColors.alert),
                        AppFilterChip(label: 'Emergency', count: emergencies, active: _filter == 'emergency', onTap: () => setState(() => _filter = 'emergency'), dotColor: AppColors.alert),
                        AppFilterChip(label: 'Warning', count: warnings, active: _filter == 'warning', onTap: () => setState(() => _filter = 'warning'), dotColor: AppColors.warn),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (groups.isEmpty)
                      _EmptyState()
                    else
                      for (final g in groups) ...[
                        DayHeader(day: g.day, count: g.items.length),
                        const SizedBox(height: 8),
                        for (final a in g.items) ...[
                          _AlertItem(alert: a),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 10),
                      ],
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              StatusDot(tone: tone, size: 7),
              const SizedBox(width: 6),
              Expanded(child: Text(label.toUpperCase(), style: GoogleFonts.manrope(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0, height: 1.3), maxLines: 2, overflow: TextOverflow.visible)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$value', style: GoogleFonts.newsreader(fontSize: 24, color: AppColors.ink900, fontWeight: FontWeight.w500, height: 1)),
        ],
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final AlertModel alert;
  const _AlertItem({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isEmergency = alert.severity == 'emergency';
    final (sensorIcon, sensorTone) = _sensorIcons[alert.sensor] ?? (Icons.notifications_outlined, 'sage');
    final sensorName = _sensorNames[alert.sensor] ?? alert.sensor;
    final sevBg = isEmergency ? AppColors.alertSoft : AppColors.warnSoft;
    final sevFg = isEmergency ? const Color(0xFF7A3727) : const Color(0xFF7A5419);
    final sevBd = isEmergency ? const Color(0xFFE6BFB1) : const Color(0xFFEAD7A4);
    final dotColor = isEmergency ? AppColors.alert : AppColors.warn;

    return Opacity(
      opacity: alert.ack ? 0.78 : 1.0,
      child: AppCard(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconWell(tone: sensorTone, size: 38, child: Icon(sensorIcon)),
                Positioned(
                  top: -2, right: -2,
                  child: Container(width: 14, height: 14, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle, border: Border.all(color: AppColors.card, width: 2))),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8, runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: sevBg, border: Border.all(color: sevBd), borderRadius: BorderRadius.circular(999)),
                        child: Text(isEmergency ? 'EMERGENCY' : 'WARNING',
                            style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w700, color: sevFg, letterSpacing: 0.4)),
                      ),
                      Text('$sensorName · ${alert.time}',
                          style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500)),
                      if (alert.ack)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 12, color: AppColors.sage700),
                            const SizedBox(width: 4),
                            Text('Acknowledged', style: GoogleFonts.manrope(fontSize: 11, color: AppColors.ink500, fontWeight: FontWeight.w600)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(alert.title, style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink900, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(alert.body, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink700, height: 1.5)),
                  if (!alert.ack) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        if (isEmergency)
                          AppButton(variant: AppButtonVariant.danger, buttonSize: AppButtonSize.sm,
                              leading: const Icon(Icons.phone, size: 14), child: const Text('Call Eleanor')),
                        AppButton(variant: isEmergency ? AppButtonVariant.outline : AppButtonVariant.soft,
                            buttonSize: AppButtonSize.sm, child: const Text('View details')),
                        AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm, child: const Text('Acknowledge')),
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

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: AppColors.sage50, border: Border.all(color: AppColors.sage200), borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          IconWell(tone: 'sage', size: 56, child: const Icon(Icons.check, size: 26)),
          const SizedBox(height: 12),
          Text('All quiet', style: GoogleFonts.newsreader(fontSize: 20, color: AppColors.ink900, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('No alerts match this filter. Everything has been calm.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink700, height: 1.5)),
        ],
      ),
    );
  }
}
