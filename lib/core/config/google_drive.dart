/// Google Drive for trip albums. Both are passed at build time:
///   --dart-define=DRIVE_API_KEY=...            (an API key restricted to the
///                                               Google Drive API and this app)
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=...  (the *web* OAuth client ID of
///                                               the Firebase project)
/// The key only lets the app read files that are already link-shared, which
/// is how trip members see each other's album photos. When either is empty,
/// albums still work on the phone but nothing is uploaded.
const String driveApiKey = String.fromEnvironment('DRIVE_API_KEY');
const String googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
);

bool get driveAlbumConfigured =>
    driveApiKey.isNotEmpty && googleServerClientId.isNotEmpty;

/// Where a link-shared Drive file can be downloaded (photo or thumbnail).
Uri driveFileUrl(String fileId) => Uri.https(
  'www.googleapis.com',
  '/drive/v3/files/$fileId',
  {'alt': 'media', 'key': driveApiKey},
);
