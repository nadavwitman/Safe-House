import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/insights_service.dart';
import '../../services/auth_state.dart';
import '../../services/api_client.dart';

// ── Summary Screen ─────────────────────────────────────────────
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _generating = false;
  Map<String, dynamic>? _report;
  String? _error;
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
          ..repeat();
    _loadReport();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await InsightsService.getWeeklyReport(houseId);
      if (mounted) {
        setState(() {
          _loading = false;
          _report = data['status'] == 'success' ? data : null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load report.';
        });
      }
    }
  }

  Future<void> _generateReport() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final triggerResult =
          await InsightsService.triggerWeeklyReport(houseId);
      if (triggerResult['status'] == 'no_data' ||
          triggerResult['status'] == 'insufficient_data') {
        if (mounted) {
          setState(() => _generating = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              triggerResult['message'] as String? ??
                  'Not enough data to generate a report yet.',
              style: GoogleFonts.manrope(fontSize: 13),
            ),
            backgroundColor: AppColors.sage700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
        return;
      }
      await _loadReport();
      if (mounted) setState(() => _generating = false);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = 'Failed to generate report.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.bgCream,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LAST 7 DAYS',
                              style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink500,
                                  letterSpacing: 0.8)),
                          const SizedBox(height: 2),
                          Text('Weekly Summary',
                              style: GoogleFonts.newsreader(
                                  fontSize: 26,
                                  color: AppColors.ink900,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const Spacer(),
                      AppButton(
                        variant: AppButtonVariant.primary,
                        buttonSize: AppButtonSize.sm,
                        leading: const Icon(Icons.auto_awesome, size: 14),
                        onPressed:
                            (_loading || _generating) ? null : _generateReport,
                        child: const Text('Generate'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.sage700))
                      : _error != null
                          ? _ErrorState(
                              message: _error!, onRetry: _loadReport)
                          : _report == null
                              ? _EmptyState(onGenerate: _generateReport)
                              : _ReportBody(report: _report!),
                ),
              ],
            ),
          ),
        ),
        if (_generating) _GeneratingOverlay(spinController: _spinController),
      ],
    );
  }
}

// ── Empty / Error States ───────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onGenerate;
  const _EmptyState({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
                color: AppColors.sage100, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome,
                size: 36, color: AppColors.sage800),
          ),
          const SizedBox(height: 16),
          Text('No report yet',
              style: GoogleFonts.newsreader(
                  fontSize: 22,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            'Tap "Generate" to create this week\'s wellness summary. Requires at least 5 days of sensor data.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 14, color: AppColors.ink600, height: 1.6),
          ),
          const SizedBox(height: 20),
          AppButton(
            variant: AppButtonVariant.primary,
            leading: const Icon(Icons.auto_awesome, size: 16),
            onPressed: onGenerate,
            child: const Text('Generate report'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 14, color: AppColors.ink600)),
            const SizedBox(height: 16),
            AppButton(
              variant: AppButtonVariant.outline,
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Report Body ────────────────────────────────────────────────
class _ReportBody extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final metrics = report['metrics'] as Map<String, dynamic>?;
    final aiOutput = report['ai_output'] as Map<String, dynamic>?;
    final wa = metrics?['weekly_averages'] as Map<String, dynamic>?;
    final deltas = metrics?['deltas'] as Map<String, dynamic>?;
    final days = (metrics?['days'] as List?)
            ?.map((d) => d as Map<String, dynamic>)
            .toList() ??
        [];

    final computedMetrics = _buildMetrics(wa, deltas);
    final sleepData = _buildSleepData(days);
    final activityData = _buildActivityData(days);
    final insights = aiOutput?['insights'] as Map<String, dynamic>?;
    final recommendations =
        (aiOutput?['recommendations'] as List?)?.cast<String>() ?? [];
    final summary = aiOutput?['summary'] as String? ?? '';
    final period = report['period'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        children: [
          if (period != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Text(
                    '${period['start']} → ${period['end']}',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.ink500),
                  ),
                ],
              ),
            ),
          ],
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.45),
            itemCount: 4,
            itemBuilder: (_, i) => _MetricCard(metric: computedMetrics[i]),
          ),
          const SizedBox(height: 12),
          if (sleepData.isNotEmpty)
            _ChartCard(
              title: 'Sleep',
              subtitle: 'Hours slept + overnight interruptions',
              legend: [
                (color: AppColors.sage800, label: 'Hours'),
                (color: AppColors.warn, label: 'Interruptions'),
              ],
              child: SizedBox(
                  height: 170,
                  child: CustomPaint(
                    painter: _SleepChartPainter(sleepData),
                    size: const Size(double.infinity, 170),
                  )),
            ),
          const SizedBox(height: 12),
          if (activityData.isNotEmpty)
            _ChartCard(
              title: 'Activity',
              subtitle: 'Transitions, kitchen events, outside minutes',
              legend: [
                (color: AppColors.sage700, label: 'Transitions'),
                (color: AppColors.warn, label: 'Kitchen'),
                (color: const Color(0xFF704863), label: 'Outside (min)'),
              ],
              child: SizedBox(
                  height: 170,
                  child: CustomPaint(
                    painter: _ActivityChartPainter(activityData),
                    size: const Size(double.infinity, 170),
                  )),
            ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.45),
            itemCount: 2,
            itemBuilder: (_, i) =>
                _MetricCard(metric: computedMetrics[i + 4]),
          ),
          const SizedBox(height: 12),
          _AIInsightsBlock(
            summary: summary,
            insights: insights,
            recommendations: recommendations,
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────

  static List<_MetricData> _buildMetrics(
    Map<String, dynamic>? wa,
    Map<String, dynamic>? deltas,
  ) {
    double? delta(String key) => (deltas?[key] as num?)?.toDouble();
    double? avg(String key) => (wa?[key] as num?)?.toDouble();

    String fmtSleep(double? h) {
      if (h == null) return 'N/A';
      final hrs = h.floor();
      final mins = ((h - hrs) * 60).round();
      return '${hrs}h ${mins}m';
    }

    String fmtDelta(double? v, {String suffix = ''}) {
      if (v == null) return '—';
      final sign = v >= 0 ? '+' : '';
      return '$sign${v.toStringAsFixed(1)}$suffix';
    }

    String dir(double? v) => v == null
        ? 'neutral'
        : v > 0
            ? 'up'
            : 'down';

    return [
      _MetricData(
        title: 'Sleep',
        icon: Icons.nightlight_round,
        tone: 'sage',
        value: fmtSleep(avg('avg_sleep_hours')),
        sub: 'avg, ${avg('avg_interruptions')?.toStringAsFixed(1) ?? '?'} interruptions/night',
        deltaV: fmtDelta(delta('sleep_hours'), suffix: 'h'),
        dir: dir(delta('sleep_hours')),
        state: (delta('sleep_hours') ?? 0) < -0.5 ? 'warn' : 'ok',
      ),
      _MetricData(
        title: 'Mobility',
        icon: Icons.arrow_forward,
        tone: 'sage',
        value: avg('avg_transitions')?.toStringAsFixed(1) ?? 'N/A',
        sub: 'transitions / day',
        deltaV: fmtDelta(delta('transitions')),
        dir: dir(delta('transitions')),
        state: (delta('transitions') ?? 0) < -3 ? 'warn' : 'ok',
      ),
      _MetricData(
        title: 'Nutrition',
        icon: Icons.kitchen_outlined,
        tone: 'warm',
        value: avg('avg_kitchen_triggers')?.toStringAsFixed(1) ?? 'N/A',
        sub: 'kitchen triggers / day',
        deltaV: fmtDelta(delta('kitchen_triggers')),
        dir: dir(delta('kitchen_triggers')),
        state: (delta('kitchen_triggers') ?? 0) < -1.5 ? 'warn' : 'ok',
      ),
      _MetricData(
        title: 'Hygiene',
        icon: Icons.bathtub_outlined,
        tone: 'sky',
        value:
            '${((avg('avg_bath_duration') ?? 0) + (avg('avg_toilet_duration') ?? 0)).round()} min',
        sub: 'bath + toilet / day',
        deltaV: '—',
        dir: 'neutral',
        state: 'ok',
      ),
      _MetricData(
        title: 'Medications',
        icon: Icons.medication_outlined,
        tone: 'plum',
        value: avg('avg_meds_count')?.toStringAsFixed(1) ?? 'N/A',
        sub: 'sessions / day',
        deltaV: fmtDelta(delta('meds_count')),
        dir: dir(delta('meds_count')),
        state: (delta('meds_count') ?? 0) < -0.5 ? 'warn' : 'ok',
      ),
      _MetricData(
        title: 'Outside',
        icon: Icons.luggage_outlined,
        tone: 'cream',
        value:
            '${avg('avg_outside_duration')?.round() ?? 'N/A'} min',
        sub: 'outside time / day',
        deltaV: fmtDelta(delta('outside_duration'), suffix: 'min'),
        dir: dir(delta('outside_duration')),
        state: (delta('outside_duration') ?? 0) < -15
            ? 'alert'
            : (delta('outside_duration') ?? 0) < -5
                ? 'warn'
                : 'ok',
      ),
    ];
  }

  static List<({String day, double hours, int interruptions})> _buildSleepData(
      List<Map<String, dynamic>> days) {
    return days.map((d) {
      final dt = DateTime.tryParse(d['date'] as String? ?? '');
      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final label =
          dt != null ? labels[dt.weekday - 1] : (d['date'] as String? ?? '?');
      return (
        day: label,
        hours: (d['sleep_hours'] as num?)?.toDouble() ?? 0.0,
        interruptions: (d['interruptions'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  static List<
      ({String day, double transitions, double kitchen, double outside})> _buildActivityData(
      List<Map<String, dynamic>> days) {
    return days.map((d) {
      final dt = DateTime.tryParse(d['date'] as String? ?? '');
      const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final label =
          dt != null ? labels[dt.weekday - 1] : (d['date'] as String? ?? '?');
      return (
        day: label,
        transitions: (d['transitions'] as num?)?.toDouble() ?? 0.0,
        kitchen: (d['kitchen_triggers'] as num?)?.toDouble() ?? 0.0,
        outside: (d['outside_duration'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }
}

// ── Metric data model ──────────────────────────────────────────
class _MetricData {
  final String title, tone, value, sub, deltaV, dir, state;
  final IconData icon;
  const _MetricData({
    required this.title,
    required this.icon,
    required this.tone,
    required this.value,
    required this.sub,
    required this.deltaV,
    required this.dir,
    required this.state,
  });
}

// ── Generating Overlay ─────────────────────────────────────────
class _GeneratingOverlay extends StatelessWidget {
  final AnimationController spinController;
  const _GeneratingOverlay({required this.spinController});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        color: const Color(0xDCF2EDDF),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RotationTransition(
                      turns: spinController,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.sage200, width: 3),
                        ),
                        child: CustomPaint(painter: _SpinnerArcPainter()),
                      ),
                    ),
                    const Icon(Icons.auto_awesome,
                        size: 28, color: AppColors.sage800),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Generating your report',
                  style: GoogleFonts.newsreader(
                      fontSize: 22,
                      color: AppColors.ink900,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(
                "This may take a moment. We're reviewing the last 7 days of activity and writing a fresh summary.",
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 13.5, color: AppColors.ink600, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinnerArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.sage700
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromLTWH(0, 0, size.width, size.height),
        -math.pi / 2, math.pi * 0.6, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Metric Card ────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final _MetricData metric;
  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (metric.state) {
      'warn' => (
          AppColors.warnSoft,
          const Color(0xFF7A5419),
          const Color(0xFFEAD7A4)
        ),
      'alert' => (
          AppColors.alertSoft,
          const Color(0xFF7E3A28),
          const Color(0xFFE8C2B5)
        ),
      _ => (AppColors.sage100, AppColors.sage800, AppColors.sage200),
    };
    final arrowIcon = metric.dir == 'up'
        ? Icons.arrow_upward
        : metric.dir == 'down'
            ? Icons.arrow_downward
            : Icons.remove;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconWell(tone: metric.tone, size: 30, child: Icon(metric.icon)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(metric.title,
                      style: GoogleFonts.manrope(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink500,
                          letterSpacing: 0.6),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(metric.value,
                    style: GoogleFonts.newsreader(
                        fontSize: 22,
                        color: AppColors.ink900,
                        fontWeight: FontWeight.w500,
                        height: 1.05)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: bd),
                    borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(arrowIcon, size: 10, color: fg),
                    const SizedBox(width: 3),
                    Text(metric.deltaV,
                        style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: fg)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(metric.sub,
              style: GoogleFonts.manrope(
                  fontSize: 11.5, color: AppColors.ink600, height: 1.4),
              maxLines: 2),
        ],
      ),
    );
  }
}

// ── Chart Card ─────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final List<({Color color, String label})> legend;
  final Widget child;
  const _ChartCard(
      {required this.title,
      required this.subtitle,
      required this.legend,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.newsreader(
                  fontSize: 18,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: GoogleFonts.manrope(
                  fontSize: 12, color: AppColors.ink500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: legend
                .map((l) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: l.color,
                                borderRadius: BorderRadius.circular(2.5))),
                        const SizedBox(width: 5),
                        Text(l.label,
                            style: GoogleFonts.manrope(
                                fontSize: 11.5, color: AppColors.ink700)),
                      ],
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (_, constraints) => child),
        ],
      ),
    );
  }
}

// ── Sleep Chart Painter ────────────────────────────────────────
class _SleepChartPainter extends CustomPainter {
  final List<({String day, double hours, int interruptions})> data;
  const _SleepChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const padL = 32.0, padR = 12.0, padT = 10.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    const maxHrs = 10.0, maxInt = 5.0;
    final innerInset = w * 0.04;
    final stepX = (w - innerInset * 2) / (data.length - 1).clamp(1, 99);

    double xAt(int i) => padL + innerInset + i * stepX;
    double yAt(double v) => padT + h - (v / maxHrs) * h;

    final gridPaint = Paint()..color = AppColors.line..strokeWidth = 1;
    for (final v in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]) {
      final y = yAt(v);
      final dashPath = Path()..moveTo(padL, y);
      double x = padL;
      while (x < padL + w) {
        dashPath.lineTo(x + 2, y);
        x += 6;
        dashPath.moveTo(x, y);
      }
      canvas.drawPath(dashPath, gridPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: '${v.toInt()}h',
            style: const TextStyle(
                fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }

    final barW = stepX * 0.38;
    final barMaxH = h * 0.78;
    final barPaint = Paint()..color = AppColors.warn;
    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final bh = d.interruptions == 0
          ? 4.0
          : math.max(8.0, (d.interruptions / maxInt) * barMaxH);
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(xAt(i) - barW / 2, padT + h - bh, barW, bh),
          const Radius.circular(3));
      barPaint.color =
          AppColors.warn.withValues(alpha: d.interruptions == 0 ? 0.18 : 0.7);
      canvas.drawRRect(rect, barPaint);
    }

    final pts =
        List.generate(data.length, (i) => Offset(xAt(i), yAt(data[i].hours)));
    final areaPath = Path()..moveTo(pts.first.dx, padT + h);
    for (final p in pts) {
      areaPath.lineTo(p.dx, p.dy);
    }
    areaPath.lineTo(pts.last.dx, padT + h);
    areaPath.close();
    canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.sage600.withValues(alpha: 0.25),
              AppColors.sage600.withValues(alpha: 0.0)
            ],
          ).createShader(Rect.fromLTWH(0, padT, size.width, h)));

    final linePaint = Paint()
      ..color = AppColors.sage800
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      linePath.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    for (int i = 0; i < data.length; i++) {
      canvas.drawCircle(pts[i], 4.5, Paint()..color = const Color(0xFFFBF8F0));
      canvas.drawCircle(
          pts[i],
          4.5,
          Paint()
            ..color = AppColors.sage800
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8);
      final tp = TextPainter(
        text: TextSpan(
            text: data[i].day,
            style: const TextStyle(
                fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xAt(i) - tp.width / 2, padT + h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ── Activity Chart Painter ─────────────────────────────────────
class _ActivityChartPainter extends CustomPainter {
  final List<
      ({String day, double transitions, double kitchen, double outside})> data;
  const _ActivityChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const padL = 32.0, padR = 12.0, padT = 10.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    const maxVal = 80.0;
    final groupW = w / data.length;
    final barW = (groupW - 8) / 3;
    final colors = [
      AppColors.sage700,
      AppColors.warn,
      const Color(0xFF704863)
    ];

    final gridPaint = Paint()..color = AppColors.line..strokeWidth = 1;
    for (final v in [0.0, 20.0, 40.0, 60.0, 80.0]) {
      final y = padT + h - (v / maxVal) * h;
      final dashPath = Path()..moveTo(padL, y);
      double x = padL;
      while (x < padL + w) {
        dashPath.lineTo(x + 2, y);
        x += 6;
        dashPath.moveTo(x, y);
      }
      canvas.drawPath(dashPath, gridPaint);
      final tp = TextPainter(
        text: TextSpan(
            text: '${v.toInt()}',
            style: const TextStyle(
                fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final groupX = padL + i * groupW + 4;
      final values = [d.transitions, d.kitchen, d.outside];
      for (int j = 0; j < 3; j++) {
        final bh = (values[j].clamp(0, maxVal) / maxVal) * h;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
              groupX + j * barW, padT + h - bh, barW - 1.5, bh),
          const Radius.circular(3),
        );
        canvas.drawRRect(
            rect,
            Paint()
              ..color = colors[j]
                  .withValues(alpha: values[j] == 0 ? 0.2 : 0.92));
      }
      final tp = TextPainter(
        text: TextSpan(
            text: d.day,
            style: const TextStyle(
                fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(groupX + (groupW - 8) / 2 - tp.width / 2, padT + h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ── AI Insights Block ──────────────────────────────────────────
class _AIInsightsBlock extends StatelessWidget {
  final String summary;
  final Map<String, dynamic>? insights;
  final List<String> recommendations;
  const _AIInsightsBlock({
    required this.summary,
    required this.insights,
    required this.recommendations,
  });

  @override
  Widget build(BuildContext context) {
    final insightEntries = <({String title, String body})>[];
    if (insights != null) {
      final order = ['sleep', 'mobility', 'nutrition', 'cognitive', 'meds', 'social'];
      for (final key in order) {
        final val = insights![key];
        if (val is String && val.isNotEmpty) {
          insightEntries.add((
            title: key[0].toUpperCase() + key.substring(1),
            body: val,
          ));
        }
      }
    }

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconWell(
                  tone: 'sage',
                  size: 32,
                  child: const Icon(Icons.auto_awesome, size: 16)),
              const SizedBox(width: 10),
              Text('AI Insights',
                  style: GoogleFonts.newsreader(
                      fontSize: 20,
                      color: AppColors.ink900,
                      fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              const AppTag(label: 'Personalized', tone: 'sage'),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(summary,
                style: GoogleFonts.manrope(
                    fontSize: 14, color: AppColors.ink800, height: 1.65)),
          ],
          if (insightEntries.isNotEmpty) ...[
            const SizedBox(height: 18),
            for (final s in insightEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.bgSoft,
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title.toUpperCase(),
                          style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.sage800,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      Text(s.body,
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.ink700,
                              height: 1.55)),
                    ],
                  ),
                ),
              ),
          ],
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('RECOMMENDED ACTIONS',
                style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink500,
                    letterSpacing: 0.8)),
            const SizedBox(height: 8),
            for (int i = 0; i < recommendations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          color: AppColors.sage100, shape: BoxShape.circle),
                      child: Center(
                        child: Text('${i + 1}',
                            style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.sage800)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(recommendations[i],
                            style: GoogleFonts.manrope(
                                fontSize: 13.5,
                                color: AppColors.ink800,
                                height: 1.5))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
