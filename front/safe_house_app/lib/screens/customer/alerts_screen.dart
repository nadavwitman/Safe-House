import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/insights_service.dart';
import '../../services/auth_state.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>>? _alerts;
  bool _loading = true;
  int _visibleCount = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) { setState(() => _loading = false); return; }
    try {
      final raw = await InsightsService.getAlerts(houseId);
      if (mounted) setState(() { _alerts = _deduplicate(raw); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _alerts = []; _loading = false; });
    }
  }

  // Merge alerts of the same type+decision within a 5-minute window into one.
  List<Map<String, dynamic>> _deduplicate(List<Map<String, dynamic>> raw) {
    final result = <Map<String, dynamic>>[];
    for (final a in raw) {
      if (result.isEmpty) { result.add(a); continue; }
      final prev = result.last;
      if (prev['decision'] == a['decision'] &&
          prev['type'] == a['type']) {
        try {
          final tPrev = DateTime.parse(prev['time'] as String);
          final tCur  = DateTime.parse(a['time'] as String);
          if (tPrev.difference(tCur).abs().inMinutes < 5) continue;
        } catch (_) {}
      }
      result.add(a);
    }
    return result;
  }

  static String _friendlySensor(String id) {
    const map = {
      'System_Vector': 'General monitoring',
      'door': 'Front Door', 'Door': 'Front Door',
      'kitchen': 'Kitchen', 'Kitchen': 'Kitchen',
      'bath': 'Bathroom', 'Bathroom': 'Bathroom',
      'toilet': 'Toilet', 'Toilet': 'Toilet',
      'meds': 'Medication Cabinet', 'Medication Cabinet': 'Medication Cabinet',
      'bed': 'Bed', 'Bed': 'Bed',
      'living': 'Living Room', 'Living Room': 'Living Room',
      'Device': 'Device',
    };
    return map[id] ?? id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 32, 22, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              AppCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: const BoxDecoration(
                              color: AppColors.sage100, shape: BoxShape.circle),
                          child: const Icon(Icons.notifications_active_outlined,
                              size: 22, color: AppColors.sage800),
                        ),
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
                      "When the system detects an unusual pattern — a missed medication, extended stillness, or a door left open — you'll receive a push notification immediately.",
                      style: GoogleFonts.manrope(
                          fontSize: 13.5, color: AppColors.ink700, height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Alert types ──────────────────────────────────────
              _AlertTypeCard(
                icon: Icons.warning_amber_rounded,
                tone: 'warn',
                label: 'Warning',
                description: "Non-critical anomalies — a routine that's slightly off, unusual timing, or a missed event.",
              ),
              const SizedBox(height: 10),
              _AlertTypeCard(
                icon: Icons.emergency_outlined,
                tone: 'alert',
                label: 'Emergency',
                description: 'Critical situations requiring immediate attention, such as a fall risk or prolonged inactivity.',
              ),
              const SizedBox(height: 10),
              _AlertTypeCard(
                icon: Icons.wifi_off_rounded,
                tone: 'warn',
                label: 'Device offline',
                description: 'Sent when the Safe House device stops reporting for 30+ minutes.',
              ),
              const SizedBox(height: 10),
              _AlertTypeCard(
                icon: Icons.sensors_off_rounded,
                tone: 'warn',
                label: 'Possible sensor fault',
                description: 'Sent when a specific sensor goes quiet for an unusually long time — it may be faulty or out of battery.',
              ),
              const SizedBox(height: 20),

              // ── Tips ────────────────────────────────────────────
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
                    for (final tip in [
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
              const SizedBox(height: 28),

              // ── Recent alerts ────────────────────────────────────
              Row(
                children: [
                  Text('Recent alerts',
                      style: GoogleFonts.newsreader(
                          fontSize: 20,
                          color: AppColors.ink900,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() { _loading = true; _visibleCount = 5; });
                      _load();
                    },
                    child: const Icon(Icons.refresh, size: 18, color: AppColors.ink400),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_alerts == null || _alerts!.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 18, color: AppColors.sage700),
                      const SizedBox(width: 12),
                      Text('All quiet — no alerts yet.',
                          style: GoogleFonts.manrope(
                              fontSize: 14, color: AppColors.ink600)),
                    ],
                  ),
                )
              else ...[
                for (final alert in _alerts!.take(_visibleCount)) ...[
                  _AlertRow(alert: alert),
                  const SizedBox(height: 10),
                ],
                if (_alerts!.length > _visibleCount)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _visibleCount += 5),
                      child: Text(
                        'Load more (${_alerts!.length - _visibleCount} remaining)',
                        style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            color: AppColors.sage800,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Alert type info card ──────────────────────────────────────────
class _AlertTypeCard extends StatelessWidget {
  final IconData icon;
  final String tone, label, description;
  const _AlertTypeCard({
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
          IconWell(tone: tone, size: 38, child: Icon(icon, size: 18)),
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

// ── Single alert row ──────────────────────────────────────────────
class _AlertRow extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final type = alert['type'] as String? ?? 'ai';
    final decision = alert['decision'] as String? ?? '';
    final sensorId = alert['sensor_id'] as String? ?? '';
    final minutesSilent = (alert['minutes_silent'] as num?)?.toInt();
    final hoursSilent = (alert['hours_silent'] as num?)?.toInt();
    // Server-composed, situation-specific message (present on AI anomaly alerts).
    final serverTitle = alert['title'] as String?;
    final serverNote = alert['note'] as String?;

    final isOffline = type == 'device_offline';
    final isFault = type == 'sensor_fault';
    final isEmergency = decision == 'Emergency';
    final friendlyName = _AlertsScreenState._friendlySensor(sensorId);

    final IconData icon;
    final String tone;
    final String title;
    final String body;

    if (isOffline) {
      icon = Icons.wifi_off_rounded;
      tone = 'warn';
      title = 'Device not responding';
      body = 'No signal for ${minutesSilent ?? '?'} minutes. Please check the device.';
    } else if (isFault) {
      icon = Icons.sensors_off_rounded;
      tone = 'warn';
      title = 'Possible sensor fault';
      final dur = hoursSilent != null ? 'over $hoursSilent hours' : 'a long time';
      body = "The $friendlyName sensor hasn't reported in $dur. "
          'It may be faulty, disconnected, or out of battery.';
    } else {
      // AI anomaly — prefer the server's focused message; fall back to a generic line.
      icon = isEmergency ? Icons.emergency_outlined : Icons.warning_amber_rounded;
      tone = isEmergency ? 'alert' : 'warn';
      title = (serverTitle != null && serverTitle.isNotEmpty)
          ? serverTitle
          : (isEmergency ? 'Emergency — $friendlyName' : 'Warning — $friendlyName');
      body = (serverNote != null && serverNote.isNotEmpty)
          ? serverNote
          : (isEmergency
              ? 'Extended lack of motion detected near $friendlyName.'
              : 'Unusual pattern detected near $friendlyName.');
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconWell(tone: tone, size: 40, child: Icon(icon, size: 20)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink900)),
                    ),
                    Text(_relTime(alert['time'] as String?),
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.ink400)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body,
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: AppColors.ink600, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _relTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}';
    } catch (_) { return ''; }
  }
}
