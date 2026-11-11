/// Address of the memories server (see backend/README.md), e.g.
/// https://rwe-memories.onrender.com. Passed at build time:
///   --dart-define=MEMORIES_API_URL=https://...
/// When empty, sharing and the community feed say they are not set up.
const String memoriesApiUrl = String.fromEnvironment('MEMORIES_API_URL');
