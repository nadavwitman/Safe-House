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
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      AdminSearchScreen(onNavigateToCreate: () => setState(() => _index = 1)),
      const AdminCreateScreen(),
    ];

    return BottomNavShell(
      currentIndex: _index,
      onTap: (i) => setState(() => _index = i),
      items: adminNavItems,
      child: IndexedStack(index: _index, children: screens),
    );
  }
}
