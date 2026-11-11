/// Switches for features that exist in the code but aren't part of the
/// current release. Flip a flag to bring the feature back: its routes and
/// entry points check these.
class FeatureFlags {
  FeatureFlags._();

  /// Guides, gear, events, stays, transport, rewards and creator mode. Off for
  /// version 1: these screens still run on sample data, which users would
  /// mistake for real listings, prices and points.
  static const bool ecosystem = false;

  /// Sends each finished trip to the `verifyTrip` Cloud Function so XP is
  /// judged on the server too. Turn on only after the function is deployed
  /// (see ACHIEVEMENT_RULES.md), otherwise every trip logs a failed call.
  static const bool serverVerifiedXp = false;
}
