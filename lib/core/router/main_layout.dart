import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/components.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tabs must stay in the same order as the shell branches in
    // app_router.dart.
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: navigationShell.currentIndex,
        onSelected: _onTap,
        items: const [
          FloatingNavItem(
            icon: Icons.explore_outlined,
            selectedIcon: Icons.explore,
            label: 'Explore',
          ),
          FloatingNavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: 'Map',
          ),
          FloatingNavItem(
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            label: 'Social',
          ),
          FloatingNavItem(
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            label: 'Passport',
          ),
        ],
      ),
    );
  }
}
