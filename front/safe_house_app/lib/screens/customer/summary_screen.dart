import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// `show` keeps intl's own TextDirection out of scope — the chart painters below
// use dart:ui's, and importing intl wholesale makes the two collide.
import 'package:intl/intl.dart' show DateFormat;
import 'dart:math' as math;
import 'dart:ui';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/insights_service.dart';
import '../../services/auth_state.dart';
import '../../services/api_client.dart';
import '../../services/weekly_report_cache.dart';

// ── Summary Screen ─────────────────────────────────────────────
class SummaryScreen extends StatefulWidget {
  /// The shell's current tab. Watched so the screen can re-check for a newer
  /// report when the user comes back to it — the IndexedStack keeps this widget
  /// alive, so initState fires only once for the life of the app.
  final ValueListenable<int> activeTab;

  /// This screen's own position in [activeTab].
  final int tabIndex;

  const SummaryScreen({
    super.key,
    required this.activeTab,
    required this.tabIndex,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen>
    with SingleTickerProviderStateMixin {
  /// Minimum time the overlay stays up once shown. A cached-report fetch can
  /// resolve in a couple of hundred milliseconds, and an overlay that appears
  /// and vanishes reads as a glitch rather than as progress.
  static const _minOverlay = Duration(milliseconds: 600);

  /// The report currently on screen — from the device cache at startup, replaced
  /// by the server's copy whenever the two disagree.
  Map<String, dynamic>? _report;

  /// Which house [_report] belongs to, so switching houses can't leave another
  /// resident's summary on screen while the new one loads.
  String? _reportHouse;

  /// True only while there is nothing to show. With a cached report up we fetch
  /// silently underneath it and swap when the new one lands.
  bool _loading = false;

  /// Guards against overlapping fetches — a tab switch and a signal change can
  /// arrive within the same frame.
  bool _fetching = false;

  String? _error;
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    widget.activeTab.addListener(_onTabChanged);
    AuthState.instance.weeklyReportAt.addListener(_onSignalChanged);
    _restoreThenSync();
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onTabChanged);
    AuthState.instance.weeklyReportAt.removeListener(_onSignalChanged);
    _spinController.dispose();
    super.dispose();
  }

  // ── Refresh triggers ─────────────────────────────────────────

  void _onTabChanged() {
    if (widget.activeTab.value != widget.tabIndex) return;
    // The shell mutates the notifier inside its own setState, so this fires
    // mid-build. Defer, or the sync's setState lands during the parent's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreThenSync();
    });
  }

  void _onSignalChanged() {
    // The dashboard poll saw a different generated_at than we hold. Fetch now
    // rather than waiting for the tab to be opened — it costs one request a week
    // and means the report is already in place when the user gets here.
    if (mounted) _syncIfStale();
  }

  /// Loads the cached report for the active house if we aren't already showing
  /// it, then reconciles against the server's timestamp.
  Future<void> _restoreThenSync() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    if (_reportHouse != houseId) {
      final cached = await WeeklyReportCache.read(houseId);
      if (!mounted) return;
      setState(() {
        _report = cached;
        _reportHouse = houseId;
        _error = null;
      });
    }
    await _syncIfStale();
  }

  /// Downloads the report only when the device copy is provably not the current
  /// one. This is the whole point of the caching scheme: on a normal open, the
  /// cached generated_at matches what the dashboard poll reported and nothing
  /// leaves the device.
  Future<void> _syncIfStale() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;

    final signal = AuthState.instance.weeklyReportAt.value;
    final cachedAt = _report?['generated_at'] as String?;

    // No signal yet — the first poll hasn't returned, or we're offline. Show
    // what we have and wait to be told it's stale; only reach out when there is
    // nothing on screen at all.
    if (signal == null) {
      if (_report == null) await _fetch(houseId);
      return;
    }
    if (signal == cachedAt) return;
    await _fetch(houseId);
  }

  /// Forced re-fetch, ignoring the cache comparison. Only the error state's
  /// Retry uses this — everything else goes through [_syncIfStale].
  Future<void> _retry() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId != null) await _fetch(houseId);
  }

  // ── Manual refresh ───────────────────────────────────────────

  /// The header's Refresh button: re-reads the stored report and shows it if it
  /// differs from what's on screen. Nothing more.
  ///
  /// It cannot produce a report — generation is the server's alone, run by the
  /// weekly job and by the catch-up that job's failures trigger. So this is the
  /// same comparison the tab already makes on focus, offered as an explicit
  /// action for a reader who wants to check rather than assume.
  Future<void> _onRefresh() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null || _fetching) return;

    final before = _report?['generated_at'] as String?;
    await _fetch(houseId);
    if (!mounted) return;

    // A newer report needs no announcement — it's on screen. Silence is only
    // ambiguous when nothing changed, which is the case worth confirming.
    if ((_report?['generated_at'] as String?) != before) return;
    _toast(_report == null
        ? "No summary yet — one will appear here when it's ready."
        : 'Your summary is up to date.');
  }

  /// Single owner of the overlay's spinner, so it is never left running behind a
  /// dismissed overlay.
  void _syncSpinner() {
    if (_loading && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!_loading && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.manrope(fontSize: 13)),
      backgroundColor: AppColors.sage700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _fetch(String houseId) async {
    if (_fetching) return;
    _fetching = true;

    final showOverlay = _report == null;
    if (showOverlay) {
      setState(() {
        _loading = true;
        _error = null;
      });
      _syncSpinner();
    }
    final startedAt = DateTime.now();

    try {
      final data = await InsightsService.getWeeklyReport(houseId);
      if (data['status'] == 'success') {
        await WeeklyReportCache.write(houseId, data);
        if (!mounted) return;
        setState(() {
          _report = data;
          _reportHouse = houseId;
          _error = null;
        });
      } else {
        // The server is authoritative about whether a report exists. Keeping a
        // cached copy alive past a no_report would make a reset or deleted
        // report impossible to clear from the device.
        await WeeklyReportCache.clear(houseId);
        if (!mounted) return;
        setState(() {
          _report = null;
          _reportHouse = houseId;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      // A failed refresh must not blank a report we already have — the cached
      // copy stays up and the freshness line shows its real age.
      if (mounted && _report == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _report == null) {
        setState(() => _error = 'Failed to load report.');
      }
    } finally {
      _fetching = false;
      if (showOverlay) {
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed < _minOverlay) {
          await Future.delayed(_minOverlay - elapsed);
        }
        if (mounted) {
          setState(() => _loading = false);
          _syncSpinner();
        }
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
                      Expanded(
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
                            Text('Weekly Summary',
                                style: GoogleFonts.newsreader(
                                    fontSize: 26,
                                    color: AppColors.ink900,
                                    fontWeight: FontWeight.w500)),
                            // The old Generate button's slot now answers "is
                            // this current?" instead — the question a reader
                            // actually has about a report they didn't ask for.
                            if (_report != null) ...[
                              const SizedBox(height: 4),
                              Text(_metaLine(_report!),
                                  style: GoogleFonts.manrope(
                                      fontSize: 12, color: AppColors.ink500)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Refresh, never Generate: one document read that shows a
                      // newer report if the server has one. It cannot cause a
                      // report to be written.
                      AppButton(
                        variant: AppButtonVariant.primary,
                        buttonSize: AppButtonSize.sm,
                        leading: const Icon(Icons.refresh, size: 14),
                        onPressed:
                            (_loading || _fetching) ? null : _onRefresh,
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _error != null && _report == null
                      ? _ErrorState(message: _error!, onRetry: _retry)
                      : _report == null
                          ? const _EmptyState()
                          : _ReportBody(report: _report!),
                ),
              ],
            ),
          ),
        ),
        // Only ever raised by a cold load with nothing to show.
        if (_loading) _GeneratingOverlay(spinController: _spinController),
      ],
    );
  }

  // ── Header meta line ─────────────────────────────────────────

  /// "Aug 10 → Aug 16 · Generated Sun 6:02 AM"
  static String _metaLine(Map<String, dynamic> report) {
    final parts = <String>[];
    final period = report['period'] as Map<String, dynamic>?;
    final start = _shortDate(period?['start'] as String?);
    final end = _shortDate(period?['end'] as String?);
    if (start != null && end != null) parts.add('$start → $end');

    final at = DateTime.tryParse(report['generated_at'] as String? ?? '')
        ?.toLocal();
    if (at != null) parts.add(_generatedLabel(at));

    return parts.join(' · ');
  }

  /// 'YYYY-MM-DD' → 'Aug 10'.
  static String? _shortDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? null : DateFormat('MMM d').format(d);
  }

  /// How the report's age reads. A weekday is only meaningful while it's still
  /// this week's report — past that it flatters a stale report by making it look
  /// recent, so the age takes over and says so outright.
  static String _generatedLabel(DateTime at) {
    final now = DateTime.now();
    final days = now.difference(at).inDays;
    if (days >= 7) return 'Generated $days days ago';

    final time = DateFormat('h:mm a').format(at);
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay
        ? 'Generated $time'
        : 'Generated ${DateFormat('E').format(at)} $time';
  }
}

// ── Empty / Error States ───────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // A clock, not a sparkle: there is nothing to trigger here, only
          // something to wait for.
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
                color: AppColors.sage100, shape: BoxShape.circle),
            child: const Icon(Icons.schedule,
                size: 36, color: AppColors.sage800),
          ),
          const SizedBox(height: 16),
          Text('No report yet',
              style: GoogleFonts.newsreader(
                  fontSize: 22,
                  color: AppColors.ink900,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          // Sets an expectation rather than offering an action — reports are
          // written server-side, so there is no button that could honestly make
          // one appear sooner. No day is promised: the weekly job runs Sunday,
          // but the catch-up can produce a first report earlier than that.
          Text(
            'Your first weekly summary appears once there are at least 5 days of activity to look at.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 14, color: AppColors.ink600, height: 1.6),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        children: [
          // The period used to be repeated here; it now lives in the header
          // alongside the report's age, where the two read as one statement.
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
              // The old copy described the AI writing the report, which is no
              // longer what's happening here — the report already exists and
              // this is the app collecting it.
              Text(
                "This may take a moment. We're putting together the last 7 days of activity.",
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
