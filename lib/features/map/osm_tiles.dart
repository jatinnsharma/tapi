import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import '../offline/data/offline_pack_store.dart';
import 'cached_tile_provider.dart';

/// OpenStreetMap's tile server. Every map in the app uses it, through
/// [osmTileLayer], and must show [OsmAttribution] (OSM's licence requires
/// the credit to be visible on the map).
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Identifies the app to the tile server, as its usage policy asks.
const osmUserAgentPackageName = 'com.example.real_world_exploration';

/// The base map layer, with tiles cached on disk (see [CachedTileProvider]).
/// [tileBuilder] restyles tiles, e.g. flutter_map's `darkModeTileBuilder`.
TileLayer osmTileLayer({TileBuilder? tileBuilder}) => TileLayer(
  urlTemplate: osmTileUrl,
  userAgentPackageName: osmUserAgentPackageName,
  tileProvider: CachedTileProvider(),
  tileBuilder: tileBuilder,
);

/// "© OpenStreetMap contributors", bottom right; tapping it opens the
/// copyright page. Put it last in a map's children so it draws on top.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  static final _copyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    // Offline city packs are MapTiler tiles, which need their credit too.
    final credit = mapTilerKey.isEmpty
        ? '© OpenStreetMap contributors'
        : '© OpenStreetMap contributors · MapTiler';
    final scheme = Theme.of(context).colorScheme;
    // Our own small credit (not flutter_map's): it shrinks with the map
    // instead of overflowing on narrow ones.
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Semantics(
          link: true,
          label: '$credit. Opens the copyright page',
          excludeSemantics: true,
          child: Material(
            color: scheme.surface.withValues(alpha: 0.75),
            child: InkWell(
              onTap: () =>
                  launchUrl(_copyright, mode: LaunchMode.externalApplication),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  credit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
