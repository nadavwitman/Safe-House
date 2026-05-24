import 'package:flutter/material.dart';
import '../../widgets/shared_widgets.dart';
import 'dashboard_screen.dart';
import 'summary_screen.dart';
import 'alerts_screen.dart';
import 'profile_screen.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  static const int _unreadAlerts = 2;

  final _screens = const [
    DashboardScreen(),
    SummaryScreen(),
    AlertsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return BottomNavShell(
      currentIndex: _index,
      onTap: (i) => setState(() => _index = i),
      items: customerNavItems,
      badgeIndex: 2,
      badgeCount: _unreadAlerts,
      child: IndexedStack(
        index: _index,
        children: _screens,
      ),
    );
  }
}
