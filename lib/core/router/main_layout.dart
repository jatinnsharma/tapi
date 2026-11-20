import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/social/application/friend_requests.dart';

import '../../features/tracking/presentation/active_adventure_bar.dart';
import '../theme/components.dart';

/// The five tabs, in the same order as the shell branches in
/// app_router.dart.
const _tabs = [
  (icon: Icons.explore_outlined, selected: Icons.explore, label: 'Explore'),
  (icon: Icons.map_outlined, selected: Icons.map, label: 'Map'),
  (icon: Icons.luggage_outlined, selected: Icons.luggage, label: 'Trips'),
  (icon: Icons.people_outline, selected: Icons.people, label: 'Friends'),
  (icon: Icons.person_outline, selected: Icons.person, label: 'You'),
];

/// Index of the Map tab: the only one that uses the full width on tablets.
const _mapTab = 1;

class MainLayout extends ConsumerWidget {
  const MainLayout({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// From this width (tablets, foldables, landscape), tabs move to a side
  /// rail and pages stop stretching.
  static const railBreakpoint = 600.0;

  /// Reading pages are capped at this width on large screens.
  static const maxContentWidth = 720.0;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    // People waiting for you to accept: the badge on Friends.
    final requests = ref.watch(incomingRequestCountProvider);
    // Always the same widgets around the shell (only the limit changes), so
    // switching tabs never rebuilds the tabs and loses their state.
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: index == _mapTab ? double.infinity : maxContentWidth,
        ),
        child: navigationShell,
      ),
    );

    // Back from another tab goes to Explore first, then leaves the app.
    Widget home(Widget scaffold) => PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: scaffold,
    );

    if (MediaQuery.sizeOf(context).width >= railBreakpoint) {
      return home(
        Scaffold(
          body: Row(
            children: [
              SafeArea(
                right: false,
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: _onTap,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.6,
                  destinations: [
                    for (final tab in _tabs)
                      NavigationRailDestination(
                        icon: Badge(
                          isLabelVisible:
                              tab.label == 'Friends' && requests > 0,
                          label: Text('$requests'),
                          child: Icon(tab.icon),
                        ),
                        selectedIcon: Icon(tab.selected),
                        label: Text(tab.label),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: content),
                    // Resume and SOS on every tab while a trip runs.
                    const ActiveAdventureBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return home(
      Scaffold(
        body: content,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resume and SOS on every tab while a trip runs.
            const ActiveAdventureBar(),
            FloatingNavBar(
              selectedIndex: index,
              onSelected: _onTap,
              items: [
                for (final tab in _tabs)
                  FloatingNavItem(
                    icon: tab.icon,
                    selectedIcon: tab.selected,
                    label: tab.label,
                    badgeCount: tab.label == 'Friends' ? requests : 0,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
