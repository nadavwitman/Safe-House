import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';

// ── Safe House Logo (shield with house + checkmark) ────────────
class SafeHouseLogo extends StatelessWidget {
  final double size;
  const SafeHouseLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _LogoPainter(),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 32;
    final sy = size.height / 32;

    final shieldPath = Path()
      ..moveTo(16 * sx, 3 * sy)
      ..lineTo(28 * sx, 9 * sy)
      ..lineTo(28 * sx, 18 * sy)
      ..cubicTo(28 * sx, 23.5 * sy, 22.8 * sx, 28 * sy, 16 * sx, 30 * sy)
      ..cubicTo(9.2 * sx, 28 * sy, 4 * sx, 23.5 * sy, 4 * sx, 18 * sy)
      ..lineTo(4 * sx, 9 * sy)
      ..close();

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [const Color(0xFFA8C0A0), const Color(0xFF7A9B7E)],
    );
    canvas.drawPath(
      shieldPath,
      Paint()..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final strokePaint = Paint()
      ..color = const Color(0xFFFBF8F0)
      ..strokeWidth = 1.6 * sx
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(10.5 * sx, 18 * sy)
        ..lineTo(10.5 * sx, 14 * sy)
        ..lineTo(16 * sx, 10 * sy)
        ..lineTo(21.5 * sx, 14 * sy)
        ..lineTo(21.5 * sx, 18 * sy),
      strokePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(13.5 * sx, 17 * sy)
        ..lineTo(15.5 * sx, 19 * sy)
        ..lineTo(19 * sx, 15 * sy),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Wordmark ───────────────────────────────────────────────────
class Wordmark extends StatelessWidget {
  final String size; // 'sm' | 'md' | 'lg'
  const Wordmark({super.key, this.size = 'lg'});

  @override
  Widget build(BuildContext context) {
    final logoSize = size == 'sm' ? 22.0 : size == 'md' ? 28.0 : 34.0;
    final fontSize = size == 'sm' ? 20.0 : size == 'md' ? 26.0 : 32.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeHouseLogo(size: logoSize),
        const SizedBox(width: 10),
        Text(
          'Safe House',
          style: GoogleFonts.newsreader(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: AppColors.sage700,
            letterSpacing: -0.2,
            height: 1,
          ),
        ),
      ],
    );
  }
}

// ── App Button ─────────────────────────────────────────────────
enum AppButtonVariant { primary, soft, ghost, outline, danger, dangerSoft }
enum AppButtonSize { sm, md, lg }

class AppButton extends StatefulWidget {
  final AppButtonVariant variant;
  final AppButtonSize buttonSize;
  final Widget? child;
  final Widget? leading;
  final Widget? trailing;
  final bool full;
  final bool disabled;
  final VoidCallback? onPressed;
  final EdgeInsets? padding;

  const AppButton({
    super.key,
    this.variant = AppButtonVariant.primary,
    this.buttonSize = AppButtonSize.md,
    this.child,
    this.leading,
    this.trailing,
    this.full = false,
    this.disabled = false,
    this.onPressed,
    this.padding,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  (Color bg, Color fg, Color? bd, List<BoxShadow>) _style() {
    switch (widget.variant) {
      case AppButtonVariant.primary:
        return (
          AppColors.sage600,
          const Color(0xFFFBF8F0),
          null,
          [BoxShadow(color: const Color(0xFF6B8B6E).withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4))],
        );
      case AppButtonVariant.soft:
        return (AppColors.sage100, AppColors.sage800, AppColors.sage200, []);
      case AppButtonVariant.ghost:
        return (Colors.transparent, AppColors.ink700, null, []);
      case AppButtonVariant.outline:
        return (AppColors.card, AppColors.ink800, AppColors.line2,
            [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))]);
      case AppButtonVariant.danger:
        return (AppColors.alert, const Color(0xFFFBF8F0), null,
            [BoxShadow(color: AppColors.alert.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 4))]);
      case AppButtonVariant.dangerSoft:
        return (AppColors.alertSoft, const Color(0xFF7A3727), const Color(0xFFE6BFB1), []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd, shadows) = _style();
    final pad = widget.padding ?? (
      widget.buttonSize == AppButtonSize.sm
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : widget.buttonSize == AppButtonSize.lg
              ? const EdgeInsets.symmetric(horizontal: 22, vertical: 16)
              : const EdgeInsets.symmetric(horizontal: 18, vertical: 13)
    );
    final fontSize = widget.buttonSize == AppButtonSize.sm ? 13.5 : widget.buttonSize == AppButtonSize.lg ? 16.0 : 15.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); if (!widget.disabled) widget.onPressed?.call(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Opacity(
          opacity: widget.disabled ? 0.55 : 1.0,
          child: Container(
            width: widget.full ? double.infinity : null,
            decoration: BoxDecoration(
              color: bg,
              border: bd != null ? Border.all(color: bd) : null,
              borderRadius: BorderRadius.circular(999),
              boxShadow: shadows,
            ),
            padding: pad,
            child: Row(
              mainAxisSize: widget.full ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.leading != null) ...[
                  IconTheme(data: IconThemeData(color: fg, size: fontSize + 2), child: widget.leading!),
                  const SizedBox(width: 8),
                ],
                if (widget.child != null)
                  Text(
                    (widget.child as Text).data ?? '',
                    style: GoogleFonts.manrope(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      letterSpacing: -0.05,
                    ),
                  ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 8),
                  IconTheme(data: IconThemeData(color: fg, size: fontSize + 2), child: widget.trailing!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── App Input ──────────────────────────────────────────────────
class AppInput extends StatefulWidget {
  final String? label;
  final Widget? icon;
  final String? error;
  final String? hint;
  final bool isPassword;
  final String? value;
  final ValueChanged<String>? onChanged;
  final String? placeholder;
  final Widget? trailing;
  final bool autofocus;
  final TextInputType keyboardType;

  const AppInput({
    super.key,
    this.label,
    this.icon,
    this.error,
    this.hint,
    this.isPassword = false,
    this.value,
    this.onChanged,
    this.placeholder,
    this.trailing,
    this.autofocus = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  bool _focused = false;
  bool _showPassword = false;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(AppInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != _controller.text) {
      _controller.text = widget.value!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.error != null
        ? const Color(0xFFD88A78)
        : _focused
            ? AppColors.sage600
            : AppColors.line2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              widget.label!,
              style: GoogleFonts.manrope(
                fontSize: 12.5, fontWeight: FontWeight.w600,
                color: AppColors.ink700, letterSpacing: 0.1,
              ),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.card2,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: _focused
                ? [BoxShadow(color: AppColors.sage600.withValues(alpha: 0.18), blurRadius: 0, spreadRadius: 4)]
                : [],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                IconTheme(
                  data: IconThemeData(
                    color: widget.error != null ? const Color(0xFFB95F4A) : AppColors.ink500,
                    size: 18,
                  ),
                  child: widget.icon!,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Focus(
                  onFocusChange: (v) => setState(() => _focused = v),
                  child: TextField(
                    controller: _controller,
                    onChanged: widget.onChanged,
                    obscureText: widget.isPassword && !_showPassword,
                    autofocus: widget.autofocus,
                    keyboardType: widget.keyboardType,
                    style: GoogleFonts.manrope(fontSize: 15, color: AppColors.ink900),
                    decoration: InputDecoration(
                      hintText: widget.placeholder,
                      hintStyle: GoogleFonts.manrope(fontSize: 15, color: AppColors.ink400),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (widget.isPassword)
                GestureDetector(
                  onTap: () => setState(() => _showPassword = !_showPassword),
                  child: Icon(
                    _showPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18, color: AppColors.ink500,
                  ),
                ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFF9C4A38)),
                const SizedBox(width: 6),
                Flexible(child: Text(widget.error!, style: GoogleFonts.manrope(fontSize: 12.5, color: const Color(0xFF9C4A38)))),
              ],
            ),
          )
        else if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(widget.hint!, style: GoogleFonts.manrope(fontSize: 12.5, color: AppColors.ink500)),
          ),
      ],
    );
  }
}

// ── App Card ───────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final int elevation; // 0, 1, 2
  final Color? color;
  final double borderRadius;
  final bool clip;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.elevation = 1,
    this.color,
    this.borderRadius = 20,
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    final List<BoxShadow> shadow = elevation == 0
        ? []
        : elevation == 2
            ? [
                BoxShadow(color: const Color(0xFF3C4837).withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
                BoxShadow(color: const Color(0xFF3C4837).withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
              ]
            : [
                BoxShadow(color: const Color(0xFF3C4837).withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1)),
                BoxShadow(color: const Color(0xFF3C4837).withValues(alpha: 0.04), blurRadius: 1, offset: const Offset(0, 1)),
              ];
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadow,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );
  }
}

// ── Status Dot ─────────────────────────────────────────────────
class StatusDot extends StatefulWidget {
  final String tone; // 'ok' | 'warn' | 'alert' | 'off'
  final double size;
  final bool pulse;

  const StatusDot({super.key, this.tone = 'ok', this.size = 8, this.pulse = false});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  Color get _color {
    switch (widget.tone) {
      case 'ok':    return AppColors.sage600;
      case 'warn':  return AppColors.warn;
      case 'alert': return AppColors.alert;
      default:      return const Color(0xFFC2BCA8);
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _scale = Tween(begin: 1.0, end: 2.4).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween(begin: 0.35, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    if (widget.pulse) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 6,
      height: widget.size + 6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulse)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => Transform.scale(
                scale: _scale.value,
                child: Opacity(
                  opacity: _opacity.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

// ── Icon Well ──────────────────────────────────────────────────
class IconWell extends StatelessWidget {
  final Widget child;
  final String tone;
  final double size;

  const IconWell({super.key, required this.child, this.tone = 'sage', this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.iconWellBg(tone),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: IconTheme(
          data: IconThemeData(color: AppColors.iconWellFg(tone), size: size * 0.48),
          child: child,
        ),
      ),
    );
  }
}

// ── Tag ────────────────────────────────────────────────────────
class AppTag extends StatelessWidget {
  final String label;
  final String tone; // 'sage' | 'warn' | 'alert' | 'neutral'
  final Widget? icon;

  const AppTag({super.key, required this.label, this.tone = 'sage', this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (tone) {
      'warn'    => (AppColors.warnSoft, const Color(0xFF7A5419), const Color(0xFFEAD7A4)),
      'alert'   => (AppColors.alertSoft, const Color(0xFF7E3A28), const Color(0xFFE8C2B5)),
      'neutral' => (AppColors.card3, AppColors.ink700, AppColors.line),
      _         => (AppColors.sage100, AppColors.sage800, AppColors.sage200),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 5)],
          Text(label, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ── App Toggle ─────────────────────────────────────────────────
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool disabled;
  final String size; // 'sm' | 'md' | 'lg'

  const AppToggle({super.key, required this.value, this.onChanged, this.disabled = false, this.size = 'md'});

  @override
  Widget build(BuildContext context) {
    final w = size == 'lg' ? 56.0 : size == 'sm' ? 36.0 : 44.0;
    final h = size == 'lg' ? 32.0 : size == 'sm' ? 22.0 : 26.0;
    final d = h - 6;
    return GestureDetector(
      onTap: disabled ? null : () => onChanged?.call(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: w, height: h,
        decoration: BoxDecoration(
          color: value ? AppColors.sage600 : const Color(0xFFD8D2BF),
          borderRadius: BorderRadius.circular(h),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              top: 3,
              left: value ? w - d - 3 : 3,
              child: Container(
                width: d, height: d,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF8F0),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 3, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom Navigation Shell ─────────────────────────────────────
class BottomNavShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavItem> items;
  final Widget child;
  final int? badgeIndex;
  final int badgeCount;

  const BottomNavShell({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.child,
    this.badgeIndex,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [AppColors.bgCream, AppColors.bgCream.withValues(alpha: 0)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final item = items[i];
                final isActive = i == currentIndex;
                final showBadge = i == badgeIndex && badgeCount > 0;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(item.icon, size: 22, color: isActive ? AppColors.sage800 : AppColors.ink500),
                            if (showBadge)
                              Positioned(
                                top: -3, right: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  height: 16,
                                  constraints: const BoxConstraints(minWidth: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.alert,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: AppColors.bgCream, width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$badgeCount',
                                      style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, height: 1.0),
                                      textHeightBehavior: const TextHeightBehavior(
                                        leadingDistribution: TextLeadingDistribution.even,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: isActive ? AppColors.sage800 : AppColors.ink500,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        if (isActive)
                          Container(width: 18, height: 2, decoration: BoxDecoration(color: AppColors.sage700, borderRadius: BorderRadius.circular(2))),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class NavItem {
  final String label;
  final IconData icon;
  const NavItem(this.label, this.icon);
}

// Predefined nav item sets
final customerNavItems = [
  NavItem('Home', Icons.home_outlined),
  NavItem('Summary', Icons.bar_chart_outlined),
  NavItem('Alerts', Icons.notifications_outlined),
  NavItem('Profile', Icons.person_outlined),
];

final adminNavItems = [
  NavItem('House Search', Icons.search),
  NavItem('Create House', Icons.add_circle_outline),
];

// ── App Filter Chip ────────────────────────────────────────────
class AppFilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool active;
  final VoidCallback? onTap;
  final Color dotColor;

  const AppFilterChip({
    super.key,
    required this.label,
    this.count,
    this.active = false,
    this.onTap,
    this.dotColor = AppColors.sage600,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.sage100 : AppColors.card,
          border: Border.all(color: active ? AppColors.sage700 : AppColors.line2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(label, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: active ? AppColors.sage800 : AppColors.ink700)),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                height: 18,
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: active ? AppColors.sage200 : AppColors.bgSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text('$count', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: active ? AppColors.sage800 : AppColors.ink600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section Header (day group divider) ─────────────────────────
class DayHeader extends StatelessWidget {
  final String day;
  final int count;
  const DayHeader({super.key, required this.day, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(day, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.8)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: AppColors.line)),
        const SizedBox(width: 8),
        Text('$count ${count == 1 ? 'alert' : 'alerts'}',
            style: GoogleFonts.manrope(fontSize: 11, color: AppColors.ink500)),
      ],
    );
  }
}

// ── Copy Chip ──────────────────────────────────────────────────
class CopyChip extends StatefulWidget {
  final String? label;
  final String value;
  final bool mono;

  const CopyChip({super.key, this.label, required this.value, this.mono = true});

  @override
  State<CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<CopyChip> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.label!.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.ink500, letterSpacing: 0.8,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgSoft,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.value,
                  style: widget.mono
                      ? const TextStyle(
                          fontFamily: 'monospace', fontSize: 13,
                          color: AppColors.ink900, height: 1.3,
                        )
                      : GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _copy,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _copied ? AppColors.sage100 : AppColors.card,
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 13,
                        color: _copied ? AppColors.sage800 : AppColors.ink700,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _copied ? 'Copied' : 'Copy',
                        style: GoogleFonts.manrope(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: _copied ? AppColors.sage800 : AppColors.ink700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Confirm Button (two-tap to fire) ──────────────────────────
class ConfirmButton extends StatefulWidget {
  final String label;
  final String confirm;
  final Widget? icon;
  final bool danger;
  final VoidCallback? onConfirmed;

  const ConfirmButton({
    super.key,
    required this.label,
    this.confirm = 'Confirm',
    this.icon,
    this.danger = false,
    this.onConfirmed,
  });

  @override
  State<ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<ConfirmButton> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    if (!_confirming) {
      return AppButton(
        variant: widget.danger ? AppButtonVariant.dangerSoft : AppButtonVariant.soft,
        buttonSize: AppButtonSize.sm,
        leading: widget.icon,
        onPressed: () => setState(() => _confirming = true),
        child: Text(widget.label),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Are you sure?',
          style: GoogleFonts.manrope(
            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink600,
          ),
        ),
        const SizedBox(width: 6),
        AppButton(
          variant: widget.danger ? AppButtonVariant.danger : AppButtonVariant.primary,
          buttonSize: AppButtonSize.sm,
          onPressed: () {
            setState(() => _confirming = false);
            widget.onConfirmed?.call();
          },
          child: Text(widget.confirm),
        ),
        const SizedBox(width: 4),
        AppButton(
          variant: AppButtonVariant.ghost,
          buttonSize: AppButtonSize.sm,
          onPressed: () => setState(() => _confirming = false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
