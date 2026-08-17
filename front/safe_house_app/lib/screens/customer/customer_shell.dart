import 'package:flutter/material.dart';
import '../../services/auth_state.dart';
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
  // The tabs live in an IndexedStack, so each screen is built once at launch and
  // kept alive — initState never fires again when the user navigates back to it.
  // Screens that need to refresh on becoming visible listen to this instead.
  final _activeTab = ValueNotifier<int>(0);

  static const _summaryTab = 1;
  static const _alertsTab = 2;
  static const _profileTab = 3;

  late final _screens = <Widget>[
    const DashboardScreen(),
    SummaryScreen(activeTab: _activeTab, tabIndex: _summaryTab),
    AlertsScreen(activeTab: _activeTab, tabIndex: _alertsTab),
    ProfileScreen(activeTab: _activeTab, tabIndex: _profileTab),
  ];

  @override
  void dispose() {
    _activeTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The unread count is owned by the Alerts tab — it is the screen holding the
    // alerts and the acknowledgements the count is derived from. Listening here
    // rebuilds the nav bar alone when it changes, without the shell needing to
    // know anything about how an alert is counted.
    return ValueListenableBuilder<int>(
      valueListenable: AuthState.instance.unreadAlerts,
      builder: (context, unread, _) => BottomNavShell(
        currentIndex: _activeTab.value,
        onTap: (i) => setState(() => _activeTab.value = i),
        items: customerNavItems,
        badgeIndex: _alertsTab,
        badgeCount: unread,
        child: IndexedStack(
          index: _activeTab.value,
          children: _screens,
        ),
      ),
    );
  }
}
