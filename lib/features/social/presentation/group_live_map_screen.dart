import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/components.dart';
import '../../auth/application/auth_service.dart';
import '../../map/osm_tiles.dart';
import '../data/social_repository.dart';
import '../domain/group_radar.dart';
import '../domain/live_location.dart';

final _groupLiveProvider = StreamProvider.autoDispose
    .family<List<LiveLocation>, String>(
      (ref, adventureId) => ref
          .watch(socialRepositoryProvider)
          .watchGroupLiveLocations(adventureId),
    );

final _groupLeaderProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, adventureId) =>
      ref.watch(socialRepositoryProvider).getGroupAdventureLeader(adventureId),
);

/// Ring colour of a member on the radar.
Color radarColor(RadarStatus status) => switch (status) {
  RadarStatus.near => const Color(0xFF1B8A3A),
  RadarStatus.drifting => AppTheme.amber,
  RadarStatus.separated => const Color(0xFFD32F2F),
  RadarStatus.stale => Colors.grey,
};

/// Live group radar for a Group Adventure: where everyone is, who has
/// strayed from the leader, and quick pings to the group.
class GroupLiveMapScreen extends ConsumerStatefulWidget {
  const GroupLiveMapScreen({
    super.key,
    required this.adventureId,
    required this.adventureName,
  });

  final String adventureId;
  final String adventureName;

  @override
  ConsumerState<GroupLiveMapScreen> createState() => _GroupLiveMapScreenState();
}

class _GroupLiveMapScreenState extends ConsumerState<GroupLiveMapScreen> {
  /// Redraws every 30 s so "stale" and ping ages stay true between updates.
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 30),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _ping(String uid) async {
    final note = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in radarPings)
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(p),
                onTap: () => Navigator.of(ctx).pop(p),
              ),
          ],
        ),
      ),
    );
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(socialRepositoryProvider).setLiveStatus(uid, note);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Share your live location on your trip first, then the group '
            'sees your pings.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(_groupLiveProvider(widget.adventureId));
    final leaderUid = ref.watch(_groupLeaderProvider(widget.adventureId)).value;
    final uid = ref.watch(authStateProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.adventureName} — Radar')),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _ping(uid),
              backgroundColor: AppTheme.forest,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Ping group'),
            ),
      body: liveAsync.when(
        loading: () => const Padding(
          padding: AppSpacing.page,
          child: Shimmer(child: SkeletonBox(height: 320, radius: 28)),
        ),
        error: (error, stack) => Padding(
          padding: AppSpacing.page,
          child: EmptyStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load live locations',
            message: 'Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: () =>
                ref.invalidate(_groupLiveProvider(widget.adventureId)),
          ),
        ),
        data: (locations) {
          if (locations.isEmpty) {
            return const Padding(
              padding: AppSpacing.page,
              child: EmptyStateCard(
                icon: Icons.location_off_outlined,
                title: 'Nobody is live right now',
                message:
                    'Start this group adventure as a trip and turn on "Share '
                    'live location" to appear on the radar.',
              ),
            );
          }
          final now = DateTime.now();
          final members = groupRadar(locations, leaderUid: leaderUid, now: now);
          final strayed = [
            for (final m in members)
              if (m.status == RadarStatus.separated) m,
          ];
          final points = [
            for (final l in locations) LatLng(l.latitude, l.longitude),
          ];

          return Column(
            children: [
              if (strayed.isNotEmpty)
                MaterialBanner(
                  backgroundColor: const Color(0xFFFDECEA),
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD32F2F),
                  ),
                  content: Text(
                    '${strayed.map((m) => m.location.displayName).join(', ')} '
                    '${strayed.length == 1 ? 'is' : 'are'} more than '
                    '${radarSeparatedMeters.round()} m from the group.',
                  ),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(64),
                      maxZoom: 17,
                    ),
                  ),
                  children: [
                    osmTileLayer(),
                    MarkerLayer(
                      markers: [
                        for (final m in members)
                          Marker(
                            point: LatLng(
                              m.location.latitude,
                              m.location.longitude,
                            ),
                            width: 44,
                            height: 44,
                            child: Tooltip(
                              message: m.location.displayName,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border: Border.all(
                                    color: radarColor(m.status),
                                    width: 4,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  m.isLeader ? Icons.flag : Icons.person,
                                  color: AppTheme.forest,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const OsmAttribution(),
                  ],
                ),
              ),
              SizedBox(
                height: 112,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  children: [
                    for (final m in members) _MemberCard(member: m, now: now),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.now});

  final RadarMember member;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = member.location;
    final where = switch (member.status) {
      RadarStatus.stale => 'Last seen ${_ago(l.updatedAt)}',
      _ when member.isLeader => 'Leader',
      _ when member.metersAway == null => 'With the group',
      _ => '${member.metersAway!.round()} m away',
    };
    final ping = member.pingAt(now);

    return SoftCard(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      radius: 22,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: radarColor(member.status), width: 3),
            ),
            child: AppAvatar(initial: l.displayName, size: 34),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  where,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkMuted,
                  ),
                ),
                if (ping != null)
                  Text(
                    '“$ping”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.amberText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }
}
