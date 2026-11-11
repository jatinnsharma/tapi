import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/journal/presentation/adventure_detail_screen.dart';
import '../../features/journal/presentation/journal_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/journal/presentation/calendar_screen.dart';
import '../../features/memories/presentation/community_memories_screen.dart';
import '../../features/memories/presentation/memories_gallery_screen.dart';
import '../../features/preferences/presentation/preferences_screen.dart';
import '../../features/social/data/social_repository.dart';
import '../../features/social/presentation/activity_feed_screen.dart';
import '../../features/social/presentation/footprint_screen.dart';
import '../../features/social/presentation/leaderboard_screen.dart';
import '../../features/social/presentation/group_adventures_screen.dart';
import '../../features/social/presentation/group_chat_screen.dart';
import '../../features/social/presentation/group_detail_screen.dart';
import '../../features/social/presentation/group_live_map_screen.dart';
import '../../features/social/presentation/groups_screen.dart';
import '../../features/wishlist/presentation/wishlist_screen.dart';
import '../../features/profile/achievements_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/social/presentation/social_screen.dart';
import '../../features/tracking/domain/directions.dart';
import '../../features/tracking/presentation/tracking_screen.dart';
import '../config/feature_flags.dart';
import '../../features/ecosystem/presentation/ecosystem_screen.dart';
import '../../features/ecosystem/presentation/events_screen.dart';
import '../../features/ecosystem/presentation/gear_screen.dart';
import '../../features/ecosystem/presentation/guides_screen.dart';
import '../../features/ecosystem/presentation/accommodation_screen.dart';
import '../../features/ecosystem/presentation/transport_screen.dart';
import '../../features/ecosystem/presentation/creator_mode_screen.dart';
import '../../features/ecosystem/presentation/rewards_screen.dart';
import '../../features/onboarding/application/onboarding_service.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/explore/presentation/city_detail_screen.dart';
import '../../features/planner/presentation/trip_planner_screen.dart';
import '../../features/planner/presentation/my_trips_screen.dart';
import 'main_layout.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ref.watch(onboardingCompletedProvider);

  return GoRouter(
    initialLocation: onboardingDone ? '/explore' : '/onboarding',
    redirect: (context, state) {
      final done = ref.read(onboardingCompletedProvider);
      if (!done && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/city/:cityId',
        builder: (context, state) {
          final cityId = state.pathParameters['cityId']!;
          return CityDetailScreen(cityId: cityId);
        },
      ),
      GoRoute(
        path: '/trip-planner',
        builder: (context, state) {
          final destination = state.uri.queryParameters['destination'];
          final cityId = state.uri.queryParameters['cityId'];
          return TripPlannerScreen(
            initialDestination: destination,
            initialCityId: cityId,
          );
        },
      ),
      GoRoute(
        path: '/my-trips',
        builder: (context, state) => const MyTripsScreen(),
      ),
      GoRoute(
        path: '/tracking',
        builder: (context, state) {
          final title = state.uri.queryParameters['title'] ?? 'New Adventure';

          // Started from a place: carries the destination so the screen can
          // guide there step by step, and `autostart` skips the start view.
          final query = state.uri.queryParameters;
          final lat = double.tryParse(query['destLat'] ?? '');
          final lng = double.tryParse(query['destLng'] ?? '');
          final destination = (lat == null || lng == null)
              ? null
              : Destination(
                  id: query['destId'] ?? 'place',
                  name: query['destName'] ?? title,
                  latitude: lat,
                  longitude: lng,
                  xpReward: int.tryParse(query['destXp'] ?? '') ?? 50,
                );

          return TrackingScreen(
            title: title,
            destination: destination,
            autoStart: query['autostart'] == '1',
          );
        },
      ),
      GoRoute(
        path: '/memories',
        builder: (context, state) => const MemoriesGalleryScreen(),
      ),
      GoRoute(
        path: '/community-memories',
        builder: (context, state) => const CommunityMemoriesScreen(),
      ),
      GoRoute(
        path: '/preferences',
        builder: (context, state) => const PreferencesScreen(),
      ),
      GoRoute(
        path: '/wishlist',
        builder: (context, state) => const WishlistScreen(),
      ),
      GoRoute(
        path: '/activity-feed',
        builder: (context, state) => const ActivityFeedScreen(),
      ),
      GoRoute(
        path: '/group-adventures',
        builder: (context, state) => const GroupAdventuresScreen(),
        routes: [
          GoRoute(
            path: ':adventureId/chat',
            builder: (context, state) {
              final adventureId = state.pathParameters['adventureId']!;
              final name = state.uri.queryParameters['name'] ?? 'Group Chat';
              return GroupChatScreen(
                parent: ChatParent.groupAdventure,
                parentId: adventureId,
                title: name,
              );
            },
          ),
          GoRoute(
            path: ':adventureId/live-map',
            builder: (context, state) {
              final adventureId = state.pathParameters['adventureId']!;
              final name =
                  state.uri.queryParameters['name'] ?? 'Group Adventure';
              return GroupLiveMapScreen(
                adventureId: adventureId,
                adventureName: name,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/achievements',
        builder: (context, state) => const AchievementsScreen(),
      ),
      GoRoute(
        path: '/leaderboard',
        builder: (context, state) => const LeaderboardScreen(),
      ),
      GoRoute(
        path: '/footprint/:uid',
        builder: (context, state) {
          final uid = state.pathParameters['uid']!;
          final name = state.uri.queryParameters['name'] ?? 'Explorer';
          return FootprintScreen(uid: uid, name: name);
        },
      ),
      GoRoute(
        path: '/groups',
        builder: (context, state) => const GroupsScreen(),
        routes: [
          GoRoute(
            path: ':groupId',
            builder: (context, state) {
              final groupId = state.pathParameters['groupId']!;
              final name = state.uri.queryParameters['name'] ?? 'Group';
              return GroupDetailScreen(groupId: groupId, groupName: name);
            },
            routes: [
              GoRoute(
                path: 'chat',
                builder: (context, state) {
                  final groupId = state.pathParameters['groupId']!;
                  final name =
                      state.uri.queryParameters['name'] ?? 'Group Chat';
                  return GroupChatScreen(
                    parent: ChatParent.group,
                    parentId: groupId,
                    title: name,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      if (FeatureFlags.ecosystem)
        GoRoute(
          path: '/ecosystem',
          builder: (context, state) => const EcosystemScreen(),
          routes: [
            GoRoute(
              path: 'guides',
              builder: (context, state) => const GuidesScreen(),
            ),
            GoRoute(
              path: 'gear',
              builder: (context, state) => const GearScreen(),
            ),
            GoRoute(
              path: 'events',
              builder: (context, state) => const EventsScreen(),
            ),
            GoRoute(
              path: 'accommodation',
              builder: (context, state) => const AccommodationScreen(),
            ),
            GoRoute(
              path: 'transport',
              builder: (context, state) => const TransportScreen(),
            ),
            GoRoute(
              path: 'creator-mode',
              builder: (context, state) => const CreatorModeScreen(),
            ),
            GoRoute(
              path: 'rewards',
              builder: (context, state) => const RewardsScreen(),
            ),
          ],
        ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/journal',
        builder: (context, state) => const JournalScreen(),
        routes: [
          GoRoute(
            path: ':adventureId',
            builder: (context, state) {
              final adventureId = state.pathParameters['adventureId']!;
              return AdventureDetailScreen(adventureId: adventureId);
            },
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainLayout(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/social',
                builder: (context, state) => const SocialScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/passport',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
