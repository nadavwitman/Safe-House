import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../auth/sign_in_screen.dart';

// ── Helpers ──────────────────────────────────────────────────────
String _formatDateTime(String? date, String? time) {
  if (date == null) return '—';
  final parts = date.split('-').map(int.parse).toList();
  final dt = DateTime(parts[0], parts[1], parts[2]);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var s = '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  if (time != null) {
    final tp = time.split(':').map(int.parse).toList();
    final h = tp[0]; final m = tp[1];
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    s += ' · $h12:${m.toString().padLeft(2, '0')} $ap';
  }
  return s;
}

String _relDays(String? date) {
  if (date == null) return '';
  final parts = date.split('-').map(int.parse).toList();
  final dt = DateTime(parts[0], parts[1], parts[2]);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = dt.difference(today).inDays;
  if (diff < 0) return '${-diff} day${-diff == 1 ? '' : 's'} ago';
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return 'in $diff days';
}

const _houses = [
  (id: 'h1', resident: 'Eleanor Reyes', address: '24 Linden St · Apt 3B'),
  (id: 'h2', resident: 'Walter Hayashi', address: '178 Larch Ave'),
  (id: 'h3', resident: 'Margarita Conti', address: 'Via Lucina 9 · Roma'),
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _activeHouse = 'h1';
  bool _vacationOn = false;
  Map<String, dynamic>? _schedule;

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
                  Text('ACCOUNT', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink500, letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text('Profile', style: GoogleFonts.newsreader(fontSize: 28, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User info card
                    AppCard(
                      padding: EdgeInsets.zero,
                      clip: true,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                            color: AppColors.card3,
                            child: Row(
                              children: [
                                Container(
                                  width: 56, height: 56,
                                  decoration: const BoxDecoration(color: AppColors.sage200, shape: BoxShape.circle),
                                  child: Center(
                                    child: Text('MR', style: GoogleFonts.newsreader(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.sage800)),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Mara Reyes', style: GoogleFonts.newsreader(fontSize: 20, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                                      Text('mara@family.com', style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink600)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ProfileRow(label: 'Username', value: 'mara_r', action: AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm, child: const Text('Edit'))),
                          _ProfileRow(label: 'Password', value: '••••••••••', action: AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm, child: const Text('Change'))),
                          _ProfileRow(label: 'Notifications', value: 'Push & SMS enabled', action: AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm, child: const Text('Manage'))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Houses
                    Text('HOUSES', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    _HouseSwitcher(
                      value: _activeHouse,
                      onChange: (v) => setState(() => _activeHouse = v),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text('You belong to ${_houses.length} houses.', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500)),
                    ),
                    const SizedBox(height: 16),

                    // Vacation mode
                    _VacationCard(
                      on: _vacationOn,
                      onChanged: (v) => setState(() => _vacationOn = v),
                      schedule: _schedule,
                      onScheduleChanged: (s) => setState(() => _schedule = s),
                    ),
                    const SizedBox(height: 16),

                    // Sign out
                    AppButton(
                      variant: AppButtonVariant.ghost,
                      full: true,
                      leading: const Icon(Icons.logout, size: 18, color: AppColors.alert),
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const SignInScreen()), (_) => false),
                      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
                      child: const Text('Sign out'),
                    ),
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

// ── Profile Row ─────────────────────────────────────────────────
class _ProfileRow extends StatelessWidget {
  final String label, value;
  final Widget action;
  const _ProfileRow({required this.label, required this.value, required this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.7)),
                const SizedBox(height: 3),
                Text(value, style: GoogleFonts.manrope(fontSize: 15, color: AppColors.ink900)),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}

// ── House Switcher ──────────────────────────────────────────────
class _HouseSwitcher extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChange;
  const _HouseSwitcher({required this.value, required this.onChange});

  @override
  State<_HouseSwitcher> createState() => _HouseSwitcherState();
}

class _HouseSwitcherState extends State<_HouseSwitcher> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cur = _houses.firstWhere((h) => h.id == widget.value);
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                IconWell(tone: 'sage', size: 36, child: const Icon(Icons.home_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE HOUSE', style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.7)),
                      const SizedBox(height: 2),
                      Text("${cur.resident}'s House", style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink900)),
                    ],
                  ),
                ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: AppColors.ink500),
              ],
            ),
          ),
        ),
        if (_open)
          AppCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: _houses.map((h) => GestureDetector(
                onTap: () { widget.onChange(h.id); setState(() => _open = false); },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: h.id == widget.value ? AppColors.sage50 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      IconWell(tone: 'sage', size: 30, child: const Icon(Icons.home_outlined)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.resident, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink900)),
                            Text(h.address, style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500)),
                          ],
                        ),
                      ),
                      if (h.id == widget.value) const Icon(Icons.check, size: 16, color: AppColors.sage700),
                    ],
                  ),
                ),
              )).toList(),
            ),
          ),
      ],
    );
  }
}

// ── Vacation Card ───────────────────────────────────────────────
class _VacationCard extends StatefulWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  final Map<String, dynamic>? schedule;
  final ValueChanged<Map<String, dynamic>?> onScheduleChanged;

  const _VacationCard({required this.on, required this.onChanged, this.schedule, required this.onScheduleChanged});

  @override
  State<_VacationCard> createState() => _VacationCardState();
}

class _VacationCardState extends State<_VacationCard> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final paused = widget.on;
    final bg = paused ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF3DDB8), Color(0xFFECCB8E)]) : null;
    final bd = paused ? const Color(0xFFE2B664) : AppColors.line;
    final fg = paused ? const Color(0xFF5C3F12) : AppColors.ink900;
    final bodyFg = paused ? const Color(0xFF6E5119) : AppColors.ink700;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: bg,
        color: bg == null ? AppColors.card : null,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: paused ? const Color(0xFFF8E9C9) : AppColors.sage100,
                  border: Border.all(color: paused ? const Color(0xFFE2B664) : AppColors.sage200),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.luggage_outlined, size: 22, color: paused ? const Color(0xFF8C6420) : AppColors.sage800),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vacation Mode', style: GoogleFonts.newsreader(fontSize: 22, color: fg, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    AppTag(
                      label: paused ? 'Paused' : widget.schedule != null ? 'Scheduled' : 'Active',
                      tone: paused ? 'warn' : 'sage',
                      icon: StatusDot(tone: paused ? 'warn' : 'ok'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      paused
                          ? 'No alerts will fire until you turn this back off.'
                          : widget.schedule != null
                              ? 'Monitoring will pause automatically when the trip starts.'
                              : 'Pauses anomaly detection while Eleanor is away. Schedule a trip ahead, or toggle on instantly.',
                      style: GoogleFonts.manrope(fontSize: 13.5, color: bodyFg, height: 1.5),
                    ),
                  ],
                ),
              ),
              AppToggle(value: paused, onChanged: widget.onChanged, size: 'lg'),
            ],
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: paused ? Colors.white.withValues(alpha: 0.5) : AppColors.bgSoft,
              border: Border.all(color: paused ? const Color(0xFFE2B664).withValues(alpha: 0.6) : AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(paused ? Icons.nightlight_round : Icons.shield_outlined, size: 16, color: bodyFg),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  paused ? 'Monitoring paused — vacation mode is on' : 'Monitoring active',
                  style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w600, color: bodyFg),
                )),
              ],
            ),
          ),

          // Schedule section
          const SizedBox(height: 14),
          Divider(color: paused ? const Color(0xFFE2B664).withValues(alpha: 0.55) : AppColors.line2, thickness: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: bodyFg),
              const SizedBox(width: 9),
              Expanded(child: Text(
                widget.schedule != null ? 'Trip scheduled' : 'Schedule a trip ahead',
                style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg),
              )),
              if (!_editing)
                widget.schedule != null
                    ? Row(children: [
                        AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm,
                            onPressed: () => setState(() => _editing = true), child: const Text('Edit')),
                        AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm,
                            onPressed: () => widget.onScheduleChanged(null), child: const Text('Cancel trip')),
                      ])
                    : AppButton(variant: AppButtonVariant.soft, buttonSize: AppButtonSize.sm,
                        leading: const Icon(Icons.add, size: 14),
                        onPressed: () => setState(() => _editing = true),
                        child: const Text('Plan a trip')),
            ],
          ),

          if (widget.schedule != null && !_editing) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: paused ? Colors.white.withValues(alpha: 0.55) : AppColors.bgSoft,
                border: Border.all(color: paused ? const Color(0xFFE2B664).withValues(alpha: 0.6) : AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('STARTS', style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w700, color: bodyFg, letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateTime(widget.schedule!['startDate'], widget.schedule!['startTime']),
                      style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                    ),
                    Text(
                      _relDays(widget.schedule!['startDate']),
                      style: GoogleFonts.manrope(fontSize: 11, color: bodyFg),
                    ),
                  ])),
                  Icon(Icons.arrow_forward, size: 16, color: bodyFg),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('ENDS', style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w700, color: bodyFg, letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateTime(widget.schedule!['endDate'], widget.schedule!['endTime']),
                      style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                      textAlign: TextAlign.end,
                    ),
                    Text(
                      _relDays(widget.schedule!['endDate']),
                      style: GoogleFonts.manrope(fontSize: 11, color: bodyFg),
                      textAlign: TextAlign.end,
                    ),
                  ])),
                ],
              ),
            ),
          ],

          if (_editing) ...[
            const SizedBox(height: 12),
            _ScheduleEditor(
              initial: widget.schedule,
              onCancel: () => setState(() => _editing = false),
              onSave: (s) { widget.onScheduleChanged(s); setState(() => _editing = false); },
            ),
          ],

          if (!widget.schedule.hasValue && !_editing) ...[
            const SizedBox(height: 8),
            Text('Set start and end times — we\'ll pause and resume monitoring automatically.',
                style: GoogleFonts.manrope(fontSize: 12, color: bodyFg, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

extension _NullableExt on Map<String, dynamic>? {
  bool get hasValue => this != null;
}

// ── Schedule Editor ─────────────────────────────────────────────
class _ScheduleEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final VoidCallback onCancel;
  final ValueChanged<Map<String, dynamic>> onSave;
  const _ScheduleEditor({this.initial, required this.onCancel, required this.onSave});

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  DateTime? _startDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _endDate;
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      final sd = init['startDate'] as String?;
      final st = init['startTime'] as String?;
      final ed = init['endDate'] as String?;
      final et = init['endTime'] as String?;
      if (sd != null) {
        final p = sd.split('-').map(int.parse).toList();
        _startDate = DateTime(p[0], p[1], p[2]);
      }
      if (st != null) {
        final p = st.split(':').map(int.parse).toList();
        _startTime = TimeOfDay(hour: p[0], minute: p[1]);
      }
      if (ed != null) {
        final p = ed.split('-').map(int.parse).toList();
        _endDate = DateTime(p[0], p[1], p[2]);
      }
      if (et != null) {
        final p = et.split(':').map(int.parse).toList();
        _endTime = TimeOfDay(hour: p[0], minute: p[1]);
      }
    }
  }

  String _fmtDate(DateTime? d) => d == null ? 'Pick a date' : () {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }();

  String _fmtTime(TimeOfDay t) {
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h12:$m $ap';
  }

  String _timeStr(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _dateStr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _startDT() => _startDate == null ? null
      : DateTime(_startDate!.year, _startDate!.month, _startDate!.day, _startTime.hour, _startTime.minute);

  DateTime? _endDT() => _endDate == null ? null
      : DateTime(_endDate!.year, _endDate!.month, _endDate!.day, _endTime.hour, _endTime.minute);

  bool get _invalid {
    final s = _startDT(); final e = _endDT();
    return s != null && e != null && !e.isAfter(s);
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.sage700, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) { _startDate = picked; } else { _endDate = picked; }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (ctx) => _CustomTimePickerDialog(initial: isStart ? _startTime : _endTime),
    );
    if (picked != null) {
      setState(() {
        if (isStart) { _startTime = picked; } else { _endTime = picked; }
      });
    }
  }

  void _presetWeekend() {
    final now = DateTime.now();
    final daysUntilSat = (6 - now.weekday + 7) % 7;
    final sat = now.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));
    final sun = sat.add(const Duration(days: 1));
    setState(() {
      _startDate = DateTime(sat.year, sat.month, sat.day);
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endDate = DateTime(sun.year, sun.month, sun.day);
      _endTime = const TimeOfDay(hour: 18, minute: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card2, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monitoring will pause automatically at the start time and resume at the end time.',
              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink700, height: 1.5)),
          const SizedBox(height: 12),

          // Starts
          _DateTimeField(
            label: 'Starts',
            dateValue: _fmtDate(_startDate),
            timeValue: _fmtTime(_startTime),
            onDateTap: () => _pickDate(true),
            onTimeTap: () => _pickTime(true),
          ),
          const SizedBox(height: 12),

          // Ends
          _DateTimeField(
            label: 'Ends',
            dateValue: _fmtDate(_endDate),
            timeValue: _fmtTime(_endTime),
            onDateTap: () => _pickDate(false),
            onTimeTap: () => _pickTime(false),
          ),

          if (_invalid) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF9C4A38)),
              const SizedBox(width: 6),
              Text('End must be after start.', style: GoogleFonts.manrope(fontSize: 12.5, color: const Color(0xFF9C4A38))),
            ]),
          ],

          // Quick fill
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Quick fill:', style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.ink500)),
              const SizedBox(width: 7),
              GestureDetector(
                onTap: _presetWeekend,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.line2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('This weekend', style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.ink700)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.line),
          const SizedBox(height: 12),
          Row(
            children: [
              AppButton(
                variant: AppButtonVariant.primary,
                buttonSize: AppButtonSize.sm,
                disabled: _startDate == null || _endDate == null || _invalid,
                onPressed: () => widget.onSave({
                  'startDate': _dateStr(_startDate!),
                  'startTime': _timeStr(_startTime),
                  'endDate': _dateStr(_endDate!),
                  'endTime': _timeStr(_endTime),
                }),
                child: const Text('Save schedule'),
              ),
              const SizedBox(width: 8),
              AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm, onPressed: widget.onCancel, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Date + Time field ───────────────────────────────────────────
class _DateTimeField extends StatelessWidget {
  final String label, dateValue, timeValue;
  final VoidCallback onDateTap, onTimeTap;
  const _DateTimeField({
    required this.label,
    required this.dateValue,
    required this.timeValue,
    required this.onDateTap,
    required this.onTimeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink700, letterSpacing: 0.2)),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(child: _FieldTrigger(icon: Icons.calendar_today_outlined, value: dateValue, onTap: onDateTap)),
            const SizedBox(width: 8),
            SizedBox(width: 112, child: _FieldTrigger(icon: Icons.access_time, value: timeValue, onTap: onTimeTap)),
          ],
        ),
      ],
    );
  }
}

// ── Field Trigger (shared for date & time) ───────────────────────
class _FieldTrigger extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  const _FieldTrigger({required this.icon, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPlaceholder = value.startsWith('Pick');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.card2,
          border: Border.all(color: AppColors.line2, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.ink500),
            const SizedBox(width: 8),
            Expanded(child: Text(
              value,
              style: GoogleFonts.manrope(fontSize: 13.5, color: isPlaceholder ? AppColors.ink500 : AppColors.ink900),
              overflow: TextOverflow.ellipsis,
            )),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.ink500),
          ],
        ),
      ),
    );
  }
}

// ── Custom Time Picker Dialog ────────────────────────────────────
class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay initial;
  const _CustomTimePickerDialog({required this.initial});

  @override
  State<_CustomTimePickerDialog> createState() => _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
  late int _hour12;
  late int _minute;
  late bool _isAm;

  @override
  void initState() {
    super.initState();
    final h = widget.initial.hour;
    _isAm = h < 12;
    _hour12 = h % 12 == 0 ? 12 : h % 12;
    _minute = (widget.initial.minute / 5).round() * 5 % 60;
  }

  TimeOfDay get _result {
    final h24 = (_hour12 % 12) + (_isAm ? 0 : 12);
    return TimeOfDay(hour: h24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(12, (i) => i + 1);
    final mins = List.generate(12, (i) => i * 5);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.card2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Preview
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sage50,
                border: Border.all(color: AppColors.sage200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: RichText(text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$_hour12:${_minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.manrope(fontSize: 22, color: AppColors.sage800, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '  ${_isAm ? 'AM' : 'PM'}',
                      style: GoogleFonts.manrope(fontSize: 14, color: AppColors.sage800, fontWeight: FontWeight.w600),
                    ),
                  ],
                )),
              ),
            ),
            const SizedBox(height: 10),

            // Wheels row
            SizedBox(
              height: 168,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _WheelColumn(
                    items: hours,
                    selected: _hour12,
                    onSelect: (v) => setState(() => _hour12 = v),
                  )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(child: Text(':', style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink500))),
                  ),
                  Expanded(child: _WheelColumn(
                    items: mins,
                    selected: _minute,
                    onSelect: (v) => setState(() => _minute = v),
                  )),
                  const SizedBox(width: 6),
                  // AM / PM column
                  SizedBox(
                    width: 56,
                    child: Column(
                      children: ['AM', 'PM'].map((p) {
                        final active = _isAm ? p == 'AM' : p == 'PM';
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: p == 'AM' ? 6 : 0),
                            child: GestureDetector(
                              onTap: () => setState(() => _isAm = p == 'AM'),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: active ? AppColors.sage700 : AppColors.card,
                                  border: Border.all(color: AppColors.line),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(p, style: GoogleFonts.manrope(
                                    fontSize: 13, fontWeight: FontWeight.w700,
                                    color: active ? const Color(0xFFFBF8F0) : AppColors.ink800,
                                  )),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Done
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(_result),
                child: Text('Done', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Wheel Column ─────────────────────────────────────────────────
class _WheelColumn extends StatefulWidget {
  final List<int> items;
  final int selected;
  final ValueChanged<int> onSelect;
  const _WheelColumn({required this.items, required this.selected, required this.onSelect});

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late final ScrollController _ctrl;
  static const double _itemH = 34.0;

  @override
  void initState() {
    super.initState();
    final idx = widget.items.indexOf(widget.selected);
    final offset = (idx * _itemH - (168 / 2 - _itemH / 2)).clamp(0.0, double.infinity);
    _ctrl = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSoft,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        controller: _ctrl,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: widget.items.length,
        itemExtent: _itemH,
        itemBuilder: (ctx, i) {
          final v = widget.items[i];
          final active = v == widget.selected;
          return GestureDetector(
            onTap: () => widget.onSelect(v),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: active ? AppColors.sage700 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  v.toString().padLeft(2, '0'),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? const Color(0xFFFBF8F0) : AppColors.ink800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
