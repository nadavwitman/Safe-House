import 'package:flutter/material.dart';
import '../../widgets/shared_widgets.dart';
import 'admin_search_screen.dart';
import 'admin_create_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  // The tabs live in an IndexedStack, so each screen is built once and kept
  // alive — initState never fires again on the way back. A screen that needs
  // fresh data when it becomes visible listens to this instead.
  final _activeTab = ValueNotifier<int>(0);

  static const _searchTab = 0;
  static const _createTab = 1;

  late final _screens = <Widget>[
    AdminSearchScreen(
      activeTab: _activeTab,
      tabIndex: _searchTab,
      onNavigateToCreate: () => _goTo(_createTab),
    ),
    AdminCreateScreen(onNavigateToSearch: () => _goTo(_searchTab)),
  ];

  void _goTo(int i) => setState(() => _activeTab.value = i);

  @override
  void dispose() {
    _activeTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavShell(
      currentIndex: _activeTab.value,
      onTap: _goTo,
      items: adminNavItems,
      child: IndexedStack(index: _activeTab.value, children: _screens),
    );
  }
}
