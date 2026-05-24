import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

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
                      Text('NOTIFICATIONS',
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
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.sage50,
                        border: Border.all(color: AppColors.sage200),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: AppColors.sage100,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.notifications_active_outlined,
                                    size: 22,
                                    color: AppColors.sage800),
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
                                            fontSize: 12.5,
                                            color: AppColors.ink500)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'When the system detects an unusual pattern — a missed medication, extended stillness, or a door left open — you\'ll receive a push notification immediately.',
                            style: GoogleFonts.manrope(
                                fontSize: 13.5,
                                color: AppColors.ink700,
                                height: 1.6),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Alert type cards
                    _AlertTypeCard(
                      icon: Icons.warning_amber_rounded,
                      tone: 'warn',
                      label: 'Warning',
                      description:
                          "Non-critical anomalies — a routine that's slightly off, unusual timing, or a missed event.",
                    ),
                    const SizedBox(height: 10),
                    _AlertTypeCard(
                      icon: Icons.emergency_outlined,
                      tone: 'alert',
                      label: 'Emergency',
                      description:
                          'Critical situations requiring immediate attention, such as a fall risk or prolonged inactivity.',
                    ),
                    const SizedBox(height: 20),

                    // Tips
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
    final isAlert = tone == 'alert';
    final bg = isAlert ? AppColors.alertSoft : AppColors.warnSoft;
    final bd = isAlert
        ? const Color(0xFFE6BFB1)
        : const Color(0xFFEAD7A4);
    final fg = isAlert
        ? const Color(0xFF7A3727)
        : const Color(0xFF7A5419);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: bd,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: GoogleFonts.manrope(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: fg,
                        letterSpacing: 0.6)),
                const SizedBox(height: 4),
                Text(description,
                    style: GoogleFonts.manrope(
                        fontSize: 13, color: fg, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
