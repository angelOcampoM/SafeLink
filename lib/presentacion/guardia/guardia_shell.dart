// CAPA: PRESENTACIÓN — View (contenedor)
// G-03 Navegación del guardia: barra inferior con Inicio, Alertas e Historial.
// No hace: no carga datos; cada pestaña tiene su propio ViewModel. Las pantallas
// del flujo de atención (entrante, detalle, navegación) se abren fuera de la barra.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GuardiaShell extends StatelessWidget {
  const GuardiaShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Inicio'),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Alertas',
          ),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history_rounded), label: 'Historial'),
        ],
      ),
    );
  }
}
