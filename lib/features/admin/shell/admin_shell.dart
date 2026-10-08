import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Barra inferior del administrador: Inicio, Guardias, Escaladas, Historial.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge_rounded), label: 'Guardias'),
          NavigationDestination(icon: Icon(Icons.priority_high_rounded), label: 'Escaladas'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Historial'),
        ],
      ),
    );
  }
}
