# Tabi: feature and code analysis

Snapshot of the working tree on `main` (commit `417ade2`, clean), 2026-11-17.
Written for engineers who work on or inherit this codebase.

**How to read this document.** Each statement carries a confidence level:
- **Verified** means checked directly in source (file paths given).
- **Reported** means found by a read-through of that area and spot-checked, but not every line re-verified.
- **Per docs** means taken from `ACHIEVEMENT_RULES.md`, `TASKS.md` or `README.md` and not confirmed in code.

Coverage is uneven. Foundation, planner/AI, discovery/map, backend, Cloud Function and Firestore rules are covered in depth. Live tracking, social, memories (Flutter side), profile and achievements are covered at a lower depth. See [Coverage and what is still open](#coverage-and-what-is-still-open).

**Status labels:** Implemented, Partial, Stubbed/mocked (hard-coded sample data), Behind a flag, Dead code.

## Contents
1. [What the app is](#what-the-app-is)
2. [Feature status at a glance](#feature-status-at-a-glance)
3. [Architecture](#architecture)
4. [Features](#features)
5. [Backend and cloud](#backend-and-cloud)
6. [XP rules and anti-cheat](#xp-rules-and-anti-cheat)
7. [Tests and CI](#tests-and-ci)
8. [Documentation that no longer matches the code](#documentation-that-no-longer-matches-the-code)
9. [Gaps and risks](#gaps-and-risks)
10. [What still needs to improve](#what-still-needs-to-improve)
11. [Coverage and what is still open](#coverage-and-what-is-still-open)

---

## What the app is

Tabi (Dart package `real_world_exploration`, v1.0.0+1) is a gamified exploration and travel app for India, built with Flutter. Users discover places, track real trips by GPS, earn XP for being physically at a place, plan multi-day trips with AI, keep a journal of photos and voice notes, and connect with friends and groups.

It is **local-first**. Trips, XP, places, memories and saved itineraries live in SQLite and SharedPreferences on the device. Firebase (Auth, Firestore, Storage, Cloud Functions) adds the social layer, and a separate Node and MongoDB server hosts shared photos and videos. If Firebase fails to start, the app still runs without it (`lib/main.dart:14-26`).

**Size:** 172 Dart files and 41,012 lines in `lib/`. `test/` has 41 files, 6,860 lines and 342 test cases. The JS code (backend, Cloud Functions, rules tests) is about 2,250 lines.

| Folder | Files | Lines |
|---|---|---|
| `lib/core` | 16 | 2,750 |
| `lib/features/planner` | 18 | 6,767 |
| `lib/features/tracking` | 19 | 6,750 |
| `lib/features/social` | 27 | 6,160 |
| `lib/features/memories` | 12 | 2,948 |
| `lib/features/locations` | 10 | 2,684 |
| `lib/features/explore` | 10 | 2,568 |
| `lib/features/profile` | 10 | 1,762 |
| `lib/features/ecosystem` | 12 | 1,635 |
| `lib/features/journal` | 4 | 1,481 |
| `lib/features/map` | 4 | 1,363 |
| `lib/features/home` | 3 | 1,221 |
| Other (auth, challenges, preferences, onboarding, ai, wishlist, weather, notifications) | 27 | 2,923 |

---

## Feature status at a glance

| Feature | Status | Where |
|---|---|---|
| Onboarding (3 static pages, asks location permission) | Implemented | `/onboarding` · `lib/features/onboarding/` |
| Email and password sign-in, sign-up, reset, delete account | Implemented (email only) | `/login` · `lib/features/auth/` |
| Home (nearby cities, around you, quick actions, AI card, trip card) | Implemented | `/explore` · `lib/features/home/` |
| City catalog, search, city detail | Implemented | `/city/:cityId` · `lib/features/explore/` |
| Places (OSM and Wikipedia fetch, place sheet, photos) | Implemented | `lib/features/locations/` |
| Map with fog of war | Implemented | `/map` · `lib/features/map/` |
| Weather warnings | Partial (warnings only) | `lib/features/weather/` |
| Wishlist | Partial (one entry point) | `/wishlist` · `lib/features/wishlist/` |
| Live trip tracking, journey and trek split, navigation | Implemented | `/tracking` · `lib/features/tracking/` |
| Server-verified XP | Behind a flag (`serverVerifiedXp`, false) | `functions/`, `firestore.rules` |
| AI trip planner (Gemini, with rules-based fallback) | Implemented | `/trip-planner` · `lib/features/planner/` |
| Saved trips, cloud backup, trip sharing | Implemented, rules deployment unconfirmed | `/my-trips` |
| Memories (photo, video, voice) and proof-photo camera | Implemented | `/memories` · `lib/features/memories/` |
| Shared and community memories | Implemented, needs `MEMORIES_API_URL` | `/community-memories`, `backend/` |
| Journal and calendar | Implemented | `/journal`, `/calendar` · `lib/features/journal/` |
| XP, ranks, achievements, daily challenges, streaks | Implemented | `/passport`, `/achievements` |
| Preferences and battery saver | Implemented | `/preferences` |
| Reminder toggles | Stubbed (settings stored, nothing reads them) | `lib/features/notifications/` |
| Social: friends, groups, chat, group adventures, live location, leaderboard, friend challenges, footprint, activity feed | Implemented, needs sign-in and Firebase | `/social` and sub-routes |
| Ecosystem hub (guides, gear, events, stays, transport, rewards, creator mode) | Behind a flag (`ecosystem`, false), on sample data | `/ecosystem/*` |
| Push or local notifications | Missing | none |
| SOS emergency-contact SMS (claimed in README) | Not found in code (see gaps) | none |

---

## Architecture

### Stack
Flutter and Dart (SDK `^3.13.4`) · Riverpod 3 for state · GoRouter 18 for routing · `flutter_map` with OpenStreetMap tiles · `geolocator`, `permission_handler`, `pedometer` for sensors · `sqflite` and `shared_preferences` for local data · Firebase Auth, Firestore, Storage and Cloud Functions · Dio for HTTP · `camera`, `image_picker`, `record`, `audioplayers`, `video_player` for media · `flutter_tts` for spoken navigation · `share_plus`, `url_launcher`. The AI provider is Google Gemini only (see the planner section). Light theme only, English only.

### Layout
`lib/core/` holds config, database, router, services, theme and utils. `lib/features/<name>/` holds `application`, `data`, `domain` and `presentation` layers. Outside `lib/` are `functions/` (Cloud Functions), `backend/` (memories API), `firebase_tests/` (rules tests), `firestore.rules`, `storage.rules` and `render.yaml`.

### Startup and resilience (Verified)
`main()` initialises Firebase inside a silent try/catch and records `firebaseReady` in a provider. Firebase options exist only for **web and Android**. The Android options reuse the web app's identifiers, because no Android app is registered (`lib/firebase_options.dart`). iOS, macOS, Windows and Linux throw, are caught, and run local-only. Everything that needs the cloud (login, social, community memories, sharing, trip backup, tips, live location, XP sync) is unavailable in that mode.

### Feature flags (Verified, `lib/core/config/feature_flags.dart`)
Both are compile-time constants, both `false`.

| Flag | Gates |
|---|---|
| `ecosystem` | The `/ecosystem/*` routes and the Home "Ecosystem" tile. With the flag off the routes do not exist. |
| `serverVerifiedXp` | The call to the `verifyTrip` Cloud Function at trip end. Even when on, the client discards the server's answer. |

### Build-time settings (`--dart-define`)

| Name | Default | Effect when missing |
|---|---|---|
| `MEMORIES_API_URL` | empty | Sharing and the community feed report "not set up". Local memories are unaffected. |
| `GEMINI_API_KEY` | empty | The Home AI card is hidden. Map "generate places" shows a snackbar. The planner uses its rules-based fallback. |
| `GEMINI_MODEL` | `gemini-flash-latest` | Uses the default alias. |

`dart_defines.local.json` is git-ignored and is used by all three VS Code launch configurations. No example file exists in the repo. `ANTHROPIC_API_KEY` appears only in the README, and no code reads it.

### Navigation (Verified, `lib/core/router/app_router.dart`)
Onboarding gates everything. Until it completes, every route redirects to `/onboarding`. After that the app starts at `/explore`. A floating bottom bar has four tabs: **Explore** (`/explore`, Home), **Map** (`/map`), **Social** (`/social`) and **Passport** (`/passport`, profile). All other routes sit outside the tab shell, so the bar is hidden on them. There is no auth guard, no error page, and no deep-link support. Many sub-screens use plain `Navigator.push`, so they have no URL.

| Route | Screen | Notes |
|---|---|---|
| `/city/:cityId` | City detail | |
| `/trip-planner` | Planner form | Query `destination`, `cityId` |
| `/my-trips` | Saved trips | |
| `/tracking` | Live trip | Query `title`, `destLat`, `destLng`, `destId`, `destName`, `destXp` (default 50), `autostart=1` |
| `/memories`, `/community-memories` | Gallery, shared feed | |
| `/preferences`, `/wishlist`, `/calendar`, `/journal`, `/journal/:adventureId` | | |
| `/achievements`, `/leaderboard`, `/footprint/:uid`, `/activity-feed` | | |
| `/groups`, `/groups/:groupId`, `/groups/:groupId/chat` | | |
| `/group-adventures`, `.../:id/chat`, `.../:id/live-map` | | |
| `/login`, `/onboarding` | | |
| `/ecosystem/*` (guides, gear, events, accommodation, transport, creator-mode, rewards) | | Only when `ecosystem` is true |

### Local data (Reported; schema read in full)
SQLite file `real_world_exploration.db`, **version 9**, dates stored as ISO-8601 text.

| Table | Holds |
|---|---|
| `adventures` | Trips: title, start and end, status (active, paused, completed, discarded, unverified), distance, duration, XP earned, trek and journey meters and seconds, steps, group adventure id |
| `route_points` | GPS points per trip (cascade delete) |
| `checkpoints` | Targets per trip: radius (default 30 m), XP reward (default 50), reached time |
| `xp_transactions` | The XP ledger. Total XP is `SUM(amount)`. |
| `locations` | Places: seed, fetched from OSM or Wikipedia, and AI-generated. Category, coordinates, XP reward, discovered time, mystery hint, image. |
| `memories` | Photos, videos, voice notes with file path, location, caption, `shared_id`, `visibility` |
| `wishlist` | Saved places |
| `trip_plans` | Saved itineraries (the full plan is stored as JSON) |
| `user_profile` | Dead: never read or written |

Known schema issues: foreign keys are never enabled with `PRAGMA`. Migrations exist only for steps 2 to 9 of specific columns and the `trip_plans` table. Nothing migrates the other tables, so a very old database could be missing them (unverified whether such builds shipped). No table is scoped to a user, so signing in as another account keeps the same local trips and XP, and the XP total is then synced to the new account.

SharedPreferences keys include `onboarding_completed_v1`, `battery_saving_mode`, `pref_*`, `reminder_*`, `gemini_call_log_v1`, `trip_plan_cache_v1`, `opening_hours_cache_v1`, `recent_searches_v1`, `equipped_rank_style`, and streak keys. Map tiles are cached as files under `map_tiles_cache`.

### Sensors and services (Reported)
- **Location:** foreground "while in use" permission only. Mock locations are rejected in release builds and allowed in debug. Trip tracking uses accuracy high, 10 m distance filter and a 5 s Android interval. **Battery saver** switches to medium accuracy, 30 m and 20 s. Android shows a foreground-service notification; iOS requests background updates. `location_service.dart` uses `dart:io Platform` without a web guard.
- **Steps:** Android and iOS pedometer, with activity-recognition permission on Android. No sensor or denied permission just means no steps.

### Design system (Reported)
Material 3, light only. Brand colours: deep green `#14532D`, primary green `#237A4B`, emerald `#1FA36B`, forest `#0F3D2B`, sage `#C4E4CF`, cream `#F7FBF5`, amber `#F5A623`, ink `#0F2A1E`. No custom fonts. Reusable components include `HeroCard`, `SoftCard`, `GlassCard`, `PlaceCard`, `StatTile`, `EmptyStateCard`, `Shimmer` skeletons, `FloatingNavBar`, `PressableScale` and `FadeSlideIn`. `GlowButton` is unused.

### Platform status
Android and web are the configured targets. The iOS plist, macOS entitlements, Windows and Linux folders exist, but Firebase is not set up there. Debug builds allow cleartext HTTP so a phone can reach a laptop memories server. Release builds need https.

---

## Features

### Onboarding, accounts and preferences
- **Onboarding** is three static pages. It stores one boolean and triggers the location prompt on the last step or on Skip. Its copy still says "across Chandigarh".
- **Auth** supports email and password only. There is no Google, Apple, phone, anonymous or email-verification flow. After sign-up the app writes the public profile `explorers/{uid}` with a display name taken from the email prefix. The login screen does not navigate after success (the user presses back). The "Sign-in unavailable" screen tells users to see `PENDING_TASKS.md`, which does not exist.
- **Delete account** re-authenticates, deletes the user's shared memories on the server, deletes friendships, feed posts, blocks, mutes, live location, footprint and profile in Firestore, then deletes the auth user. Group chat messages and local data stay.
- **Preferences:** interests, duration, difficulty and social preference, all stored locally. Only `interests` is consumed (the Home AI prompt). **Battery saver** is applied at the next trip start. Three **reminder toggles** (streak, challenge, social) are saved but nothing reads them. There is no notification package, so no reminders ever fire.

### Home, explore and places (Reported, key claims re-checked)
- **City catalog:** `assets/data/india_cities.json` has 165 entries covering 35 of 36 states and union territories (Chhattisgarh is missing) across 9 categories. Only 48 distinct Unsplash image URLs are used, one of them 26 times.
- **Search:** as-you-type results come from the local catalog plus **Photon**. Nominatim runs only when the user presses search or "Search everywhere". Recent searches are stored locally.
- **Places:** `NearbyPlacesService` fetches from Wikipedia, Overpass (OSM) and Wikimedia Commons within about 30 km and stores them in `locations`. XP is **60, 70, 80, 100 or 110** for live-fetched places depending on kind. Search results, planner stops and deep links pay 50 by default. The one built-in "mystery place" pays 150.
- **Place sheet:** details, photos, opening hours, "start trip", directions. Starting a trip needs only a location fix. The old Chandigarh-only block is gone.
- **Home screen:** header actions, nearby cities, around-you cards, quick actions (Trip Planner, Memories, Journal, Calendar), the trip card and the AI recommendation card.
- **Service area:** `ServiceArea` is now an **all-India bounding box** (lat 6 to 38, lng 68 to 98, default centre New Delhi). It is still enforced as a filter in seven places, including the place repository, the nearby-places save, Map AI places and planner stop validation. It also admits parts of neighbouring countries. Seed data is Chandigarh-only and is used only when the `locations` table is empty.
- **Weather:** Open-Meteo. The severe flag (`weatherCode >= 71`) only shows warning banners on the trip start, tracking and navigation screens. It does **not** hide places or quests, contrary to the README. Wind speed is parsed but unused.
- **Wishlist:** works, but items can only be added from the Map marker sheet.
- **Community tips** on places: shown only for discovered places, with no moderation, report option or length limit. There is no UI to delete a tip.
- **"Explore on Map"** on city detail sets `selectedCityProvider`, but the Map screen never reads it, so the button does not move the map.

### Map and fog of war (Reported)
OpenStreetMap tiles with an on-disk cache that has **no size limit or eviction**. The fog service reveals places within **250 m** of the user's position and ignores mock locations. With no GPS the avatar is placed at New Delhi. The map takes a one-time snapshot of places, so places fetched later do not appear until it is rebuilt. Map markers open the place sheet. The Map can also ask Gemini to generate nearby places, which are written to the same `locations` table without a provenance column and with unclamped XP. No OSM attribution widget exists anywhere in `lib/`.

### Live trip tracking and navigation (Reported and per docs)
Trips start from a place sheet, a planner stop, a group adventure or the Home screen. The tracking screen records GPS, supports pause and resume, counts steps, warns about severe weather and shows turn-by-turn navigation using the free FOSSGIS/OSM router with spoken guidance (`flutter_tts`). Each trip is split into **journey** (getting there, any transport) and **trek** (on foot within 200 m of the start); only trek counts for XP, distance achievements and difficulty. A failed trip is saved as "Trip not counted" with the reasons listed in plain words. Finished trips can be shared as text or an image, but the share sheet hard-codes `#Chandigarh` and "Adventure Completed · Chandigarh" for every trip. Rules and numbers are in [XP rules and anti-cheat](#xp-rules-and-anti-cheat).

### AI trip planner (Reported)
- **Provider:** only Google Gemini, via the REST API with the key in the URL query. The key is compiled into the app. The README's "Anthropic Claude quest generator" is stale: no code calls Anthropic.
- **Cost guard:** a client-side limiter of 3 s between calls, 20 per hour and 60 per day, kept in SharedPreferences and shared by every AI feature. It is bypassable by a modified client.
- **Flow:** the form takes destination, days, who is going, trip type, budget, interests, pace and start date. It grounds the prompt on places fetched for the city, asks Gemini for strict JSON, then validates and repairs the result (`itinerary_repair.dart`). Stops are geocoded, shown per day on a route map and checked against opening hours. The user can reorder or delete stops, regenerate a day and mark stops done. Each day gets morning, afternoon and evening blocks. Plans are cached for 30 days by destination.
- **Fallback:** a rules-based planner builds a simple plan when AI is unavailable. It ignores interests and language, and the screen never says which path produced the plan.
- **Extras:** safety tips, packing list, budget estimate, weather for dates within 16 days, hotel and transport links (external links, because the ecosystem flag is off), text and image share. Hindi is supported for AI output only.
- **Saving and sharing:** plans are saved to SQLite and backed up to the Firestore `trip_plans` collection. The owner can share a plan with up to 20 members, who can edit it. Concurrent edits are last-write-wins on the whole plan.

### Memories, journal and calendar (Reported, backend verified)
- **Capture:** live camera with a rule-of-thirds overlay, video, voice notes with preview, and gallery import. A separate **proof-photo mode** has no gallery and requires a fresh photo taken at the place (see XP rules). Memory media is stored under the app documents folder, with metadata in the `memories` table.
- **Gallery and viewer:** browse, play, caption and delete. Sharing a memory uploads it to the memories server with visibility **friends** or **public**.
- **Community feed:** public or friends' memories, 80 per request. Needs sign-in and `MEMORIES_API_URL`.
- **Journal and calendar:** past trips grouped by day, month calendar, and trip detail with route playback, stats and the memories captured.

### Profile, ranks, achievements and challenges (Reported and per docs)
- **Ranks** unlock cosmetic profile frames and trail colours: Beginner 0 XP, Explorer 1,000, Adventurer 2,500, Pathfinder 6,000, Trailblazer 12,000, Expedition Leader 25,000, Legendary Explorer 50,000 (per `ACHIEVEMENT_RULES.md`).
- **Achievements:** six 3-star achievements (Trail Walker, Long Walker, Destination Hunter, City Explorer, Memory Maker, Storyteller) plus Step Master. Stars pay 50, 150 and 400 XP when the user claims them.
- **Daily challenge** and **streak** with a flame badge and streak freezes.

### Social (Reported, rules read in full)
Needs Firebase and sign-in. Friends (request, accept, remove, block, mute), explorer profiles with XP, groups with real-time chat, group adventures (public or private, with chat and a live map), opt-in live location sharing, a leaderboard ranked by the profile's `totalXp`, friend challenges, a shareable footprint of routes and visited places, an activity feed, and reports. Without Firebase or sign-in the Social tab shows a sign-in prompt. See the rules table below for who can read what.

### Ecosystem hub (Verified: behind a flag)
Guides, gear rental, events, accommodation, transport, rewards and creator mode run on hard-coded sample data. They are hidden in v1 because users might mistake sample listings and prices for real ones.

---

## Backend and cloud

### Memories API (`backend/`, Verified)
Express app with MongoDB for records and GridFS for files. Deployed on Render (`render.yaml`: free web service `rwe-memories`, health check `/healthz`). Login stays with Firebase: the server only verifies the Firebase ID token.

| Method and path | Auth | Behaviour |
|---|---|---|
| `GET /healthz` | none | `{ok:true}` |
| `GET /media/:fileId` | signed link | Verifies an HMAC link (expires 6 h per README). Supports byte ranges (206, 416). `Cache-Control: private, max-age=3600`. |
| `GET /memories/feed?scope=public or friends` | Bearer token | Up to 80 items. For friends scope the server reads accepted friendships from Firestore (`server.js` passes `getFriends`), so the app's list only narrows the result. |
| `PUT /memories/:id` | Bearer token | Upload the file as the body. Checks type (415), size over 50 MB (413), ownership (403), more than 300 memories per user (429). |
| `PATCH /memories/:id` | Bearer token, owner | Change visibility or caption (trimmed to 300 characters). |
| `DELETE /memories/:id` | Bearer token, owner | Delete one. |
| `DELETE /memories` | Bearer token | Delete all of the caller's memories (used at account deletion). |

Environment: `MONGODB_URI`, `MEDIA_SECRET`, `FIREBASE_PROJECT_ID`, `MONGODB_DB` (default `rwe`), `PORT`. Free-tier limits: 512 MB MongoDB, and the server sleeps when idle.

### Cloud Function `verifyTrip` (Verified, not deployed)
`functions/index.js` exports one callable, `verifyTrip`, in region `asia-south1`, max 10 instances. It requires sign-in. **App Check enforcement is off** (`enforceAppCheck: false`). It evaluates a finished trip (see rules below) and writes XP to `verified_xp/{uid}`, paying each trip id once. The app does not call it unless `serverVerifiedXp` is on, and nothing reads `verified_xp` yet.

### Firestore rules (Verified, `firestore.rules`)

| Collection | Read | Write |
|---|---|---|
| `explorers/{uid}` | any signed-in user | Owner only. New profile must start at 0 XP. XP change needs the server clock and is capped: 20,000 on first sync, then 1,000 plus 3,000 per day. |
| `friendships/{a_b}` | the two users | Either user creates a pending request (ids sorted). Only the non-requester can accept. Either can delete. |
| `activity` | author or accepted friend | Author creates or deletes. |
| `live_locations/{uid}` | self, accepted friend with sharing on, or member of the group adventure | Owner |
| `groups`, `group_adventures` | public, creator or member | Creator manages. Others can only join a public one or remove themselves. Messages are creator and member only and cannot be edited or deleted. |
| `groups/.../safety_statuses/{uid}` | creator and members | Self |
| `location_communities/{id}` and `visitors`, `tips` | any signed-in user | Counter may only go up by 1. Tips are author-created and author-deleted. |
| `explorers/{uid}/blocked`, `muted` | owner (and the blocked user can read a block) | Owner |
| `footprints/{uid}` | self, public, or friends per its own `visibility` field | Owner |
| `shared_memories` | owner, public, or accepted friend | Owner |
| `reports` | nobody | Any signed-in user creates; reviewed in the console |
| `verified_xp/{uid}` | any signed-in user (subcollections: owner) | Nobody (server only) |
| `trip_plans/{id}` | members | Create with owner as member (max 20 members). Members edit. Owner changes membership and deletes. A member can remove only themselves. |
| `friend_challenges` | the two users | Either participant can update or delete |

Emulator tests (`firebase_tests/`) cover only the `explorers` XP rules and `verified_xp`. Nothing tests `trip_plans`. The rules file is read-only here, so whether it is published is unknown. `TASKS.md` says it was not.

`storage.rules` is 25 lines (not analysed in depth). `firebase.json` configures only Firestore and Storage rules. It has no `functions` block.

---

## XP rules and anti-cheat

The principle (per `ACHIEVEMENT_RULES.md`): XP is paid for being at a real place. The numbers below are from that file. The server-side column is verified against `functions/lib/evaluate_trip.js`. The app-side values were not re-verified line by line.

| Rule | Value |
|---|---|
| Reach a place | Start at least 100 m away, walk at least 60% of the straight-line distance, at least 60 s in, no fake GPS, arrive within 40 m, take a live camera photo at the place (GPS fix under 90 s old and within 100 m, photo under 2 minutes old) |
| Place payout | Once per place per **7 days** |
| Complete a trip | +100 XP for at least 200 m and 2 minutes of trek with clean GPS |
| Daily cap on trip XP | **1,500** |
| Achievement stars | 50, 150, 400 XP, claimed manually |
| Teleport flag | Over 45 m/s between readings (jump of at least 60 m) |
| Vehicle vs foot | Faster than 4 m/s over the last 30 s is a vehicle. A 300 m vehicle leg means heading back. |
| Ignored readings | Accuracy worse than 50 m, steps under 3 m |
| Trek difficulty | Under 3 km Easy, under 8 Moderate, under 15 Challenging, else Hard |

**Server verification (Verified).** The function checks the trip id, times (under 24 hours long, not more than 5 minutes in the future, not older than 48 hours), at most 6,000 fixes, re-runs the guard over the whole path, and sets XP from its own table, ignoring the app's number. Server place XP: heritage 80, nature 70, lake 60, photography 60, viewpoint 70, hiddenGem 110, everything else 50.

**Mismatch to know about:** the app pays 60 to 110 by place kind, 150 for the mystery place, and AI-generated places carry unclamped XP. The server table has no entry for trek, mountain, waterfall, food, camping or mystery places, so they get 50. Turning the flag on would make server and app totals disagree.

**Honest limits (from the docs, consistent with the code).** XP is stored on the phone. A rooted phone can edit it, and a good GPS spoofer that hides the mock flag still passes. The leaderboard ranks the profile's self-reported `totalXp`, not `verified_xp`, so treat it as for fun. Planned hardening (App Check, photo verification, QR or NFC at partner places, reports) is not built.

---

## Tests and CI

- **Flutter:** 342 test cases in 41 files. The largest are `trip_guard_test.dart` (26), `opening_hours_test.dart` (24), `search_test.dart` (20), `achievements_test.dart` (17), `trip_split_test.dart` (16), `directions_test.dart` (16), `place_photos_test.dart` (15), `camera_screen_test.dart` (14), `home_sections_test.dart` (13) and `itinerary_repair_test.dart` (13). Areas covered include trip guard and split, steps, achievements, calendar, camera and media review, search and ranking, opening hours, planner repair and extras, leaderboard, rank styles and streaks.
- **Not covered:** the router and onboarding redirect (one onboarding test only), auth and login, theme and components, Social screens, the Firestore `trip_plans` rules, and real GPS or camera hardware.
- **JS:** Cloud Function tests (`functions/test/`: evaluate trip, ledger, guard, split), backend tests (`backend/test/`) and rules tests (`firebase_tests/`). Counts were not re-verified. `ACHIEVEMENT_RULES.md` claims 62, 32 and 83.
- **CI:** one GitHub Actions workflow on push and PR to `main`: Java 17, Flutter stable, `pub get`, format check, `flutter analyze`, `flutter test`, release APK build, upload APK. **It does not run the backend, Cloud Function or rules tests.** The CI APK is built with no dart-defines, so AI is off and sharing is "not set up".

---

## Documentation that no longer matches the code

| Documentation says | Code does |
|---|---|
| README: AI Adventure Generator uses Anthropic Claude; run with `ANTHROPIC_API_KEY` | Only Gemini is called (`GEMINI_API_KEY`). No code reads the Anthropic key. |
| README: weather "hides dangerous outdoor quests" | Severe weather only shows warning banners on the trip screens. |
| README: SOS system SMS to emergency contacts | No SOS or emergency-contact code found (see gaps) |
| README: apply security rules from `PENDING_TASKS.md` | That file does not exist. |
| README: run `flutterfire configure` | `firebase_options.dart` is hand-written and covers web and Android only. |
| README and `TASKS.md`: Chandigarh-only lock | Replaced by an all-India box, which still filters places in seven spots. |
| `TASKS.md`: all 21 tasks built | Not fully: no "Start today's plan" button (per-stop "Go" only), no PDF share, no group integration, no trip-type field saved, Hindi covers AI output only. |
| `TASKS.md`: `place_sheet.dart` blocks trips outside the area | Block removed. The doc comment there is stale. |
| `ACHIEVEMENT_RULES.md`: place pays 60 to 110 by kind | True only for live-fetched places. Seed mystery pays 150, other sources 50, AI places unclamped. |
| README ends mid-file | Last lines are UTF-16 garbage (`# tapi`), and the file contains NUL bytes. |

---

## Gaps and risks

### High
- **Leaderboard can be inflated.** It ranks the self-written `totalXp`, capped only by the rules' growth limits. Server-verified XP is built but off and unread.
- **Gemini key shipped in the app.** It is compiled in and sent in the URL, and the only rate guard is on the device.
- **Android Firebase app is the web app.** There is no `google-services.json`, and iOS, macOS and desktop have no Firebase at all.
- **`explorers` profiles (including an email-prefix display name) are readable by every signed-in user.**
- **Local data is not scoped per account**, so a second user on the same device inherits the first user's trips and XP.

### Medium
- Stale `cityId` in the planner: editing the destination text after picking a city keeps the old city's grounding, but caches the result under the new name for 30 days.
- AI failures are swallowed with no indicator, and the screen always says "AI Trip Planner". An unresolvable destination silently becomes New Delhi.
- Server and app XP tables differ (see XP rules).
- `serverVerifiedXp` off means `verifyTrip` is never called. When on, the client throws the answer away. App Check is off.
- Last-write-wins sync on whole trip plans, and an owner's next save can re-add a member who left.
- "Explore on Map" does nothing to the map. Wishlist and community tips each have a single entry point. Tips have no moderation.
- Reminder toggles and three of the four preferences are stored but consumed by nothing.
- The mystery place leaks its real name in several places (planner card, search, wishlist, AI prompts).
- Third-party calls send the placeholder User-Agent `com.example.real_world_exploration`, with no retry, backoff or 429 handling. Exact GPS coordinates go to third-party hosts including an Overpass mirror.
- Share sheet hard-codes "Chandigarh" for every trip. Onboarding copy says "across Chandigarh".
- `firebase.json` has no `functions` block, so deploying the function needs it added (not verified by running a deploy).

### Low
- Dead code: `user_profile` table, `GlowButton`, the `NavigationBar` theme, `ServiceArea.isNear`, `kmFromCenter`, `defaultRadiusKm`, wishlist "quest" type.
- Map tile cache has no size limit and the app shows no OSM attribution.
- `PolylineCodec.decode` can throw on truncated input and is used on Firestore data without a try/catch.
- Android auto-backup is not restricted (GPS history can be backed up).
- A stray `y.txt` (20 lines of `y`) is in the repo root.
- Catalog uses 48 distinct images, and shows the raw `HILL_STATION` label.

---

## What still needs to improve

A prioritised list of improvements, drawn from the gaps above. Each item names the files involved.

### Priority 1: security and trust
1. **Move the Gemini key off the device.** Call Gemini through a Cloud Function or the memories backend, keep the key on the server, and rate-limit per user there. Today the key is compiled into the app (`lib/core/services/ai_status.dart`, `lib/features/ai/data/gemini_client.dart`).
2. **Finish server-verified XP.**
   - Deploy `verifyTrip` (add a `functions` block to `firebase.json`).
   - Turn on `FeatureFlags.serverVerifiedXp`.
   - Use the server's answer instead of discarding it (`tracking_service.dart` around line 674).
   - Switch the leaderboard and achievements to read `verified_xp`.
3. **Turn on App Check** (`enforceAppCheck: true` in `functions/index.js`) with Play Integrity, so only the real app can call the function.
4. **Align the XP tables.** Give the server `PLACE_XP` (`functions/lib/evaluate_trip.js`) the same categories as the app, including trek, mountain, waterfall, food, camping and mystery. Clamp the XP of AI-generated places.
5. **(Already done.)** `backend/server.js` verifies friendships from Firestore for friends-only memories; an earlier draft of this list said otherwise.
6. **Limit profile exposure.** Stop using the email prefix as the default public name, or make `explorers/{uid}` readable only by friends, leaving a minimal leaderboard projection.
7. **Scope local data to the signed-in user.** Add a user id to the SQLite tables, or clear or separate data on account switch, so XP is not synced into the wrong account.

### Priority 2: platform and release readiness
8. **Register real Firebase apps.** Run `flutterfire configure` for Android (`google-services.json`) and iOS, instead of reusing the web app id.
9. **Publish and test the Firestore rules.** Deploy them, then add emulator tests for `trip_plans`, social collections and `friend_challenges` (`firebase_tests/` covers only XP today).
10. **Extend CI.** Run `backend` and `functions` tests and the rules emulator tests. Build with a test dart-define file so AI and sharing paths are exercised.
11. **Make the setup reproducible.** Add `dart_defines.example.json`, fix the README (Gemini not Claude, remove `PENDING_TASKS.md`, fix the UTF-16 tail), and delete `y.txt`.
12. **Make the database migrations complete.** Add `CREATE TABLE IF NOT EXISTS` for every table on upgrade, enable `PRAGMA foreign_keys`, drop the dead `user_profile` table, and add indexes on `adventures.started_at`, `xp_transactions.created_at` and `memories.timestamp`.
13. **Guard web builds.** `location_service.dart` and `step_service.dart` use `dart:io Platform` without `kIsWeb` checks.

### Priority 3: features that are promised but missing
14. **Notifications.** Add `flutter_local_notifications` (and optionally FCM) and wire the three reminder toggles: streak, challenge and social.
15. **SOS and emergency contacts.** The README promises this, but it is not in the code. Either build it (contacts in preferences, plus an SMS or share-location action on the trip screen) or remove the claim.
16. **Weather safety.** Actually hide or flag outdoor places on severe-weather days, as documented, and use wind speed.
17. **Planner.**
    - Add a "Start today's plan" button that starts a trip with every stop of the day.
    - Save a trip type.
    - Add group integration.
    - Fix the stale `cityId` when the destination text changes (`trip_planner_screen.dart:257-279`).
    - Show whether a plan came from AI or from the rules fallback.
    - Pass the start date and weekday to the AI, so it avoids closed days.
    - Check opening hours over the whole visit, not just one instant per slot.
18. **Map.**
    - Make "Explore on Map" move the map (read `selectedCityProvider` in `map_screen.dart`).
    - Refresh markers when new places are fetched.
    - Add an OSM attribution widget.
    - Cap and evict the tile cache.
19. **Wishlist and tips.**
    - Add "save to wishlist" on the place sheet and city screens, not only on map markers.
    - Add a delete UI, a length limit and a report option for community tips.
20. **Use the stored preferences.** Duration, difficulty and social preference are saved but unused. Feed them into recommendations and the planner, or remove them.
21. **Login screen.** Navigate back after a successful sign-in, and add a back button. Optionally add Google sign-in and email verification.
22. **Remove the Chandigarh leftovers.** These are the share-sheet hashtag and caption (`trip_share_sheet.dart:40,217`), the onboarding copy, the `Location` constructor defaults and stale comments.
23. **Fix the mystery place.** Hide its real name in the planner card, search, wishlist and AI prompts, or remove the feature until it is complete.
24. **Ecosystem hub.** Either connect real data sources or delete the sample-data screens. They are dead weight while the flag is off.

### Priority 4: quality and polish
25. **Network hygiene.** Set a real User-Agent with contact details for Nominatim, Overpass and Wikimedia, as their policies require. Add retry with backoff and 429 handling. Avoid sending exact coordinates where rounded ones work.
26. **Sync conflicts.** Merge trip-plan edits per stop or day, instead of last-write-wins on the whole plan, and use server timestamps.
27. **Robustness.** Wrap `PolylineCodec.decode` on Firestore data in a try/catch. Show errors instead of silently swallowing AI failures. Handle permanently denied location permission with an "open settings" action.
28. **Accessibility.** Add `Semantics` labels beyond chips and nav buttons. Respect reduced motion in `Shimmer` and other animations.
29. **Dark theme and localisation.** The UI is light-only and English-only, while Hindi is supported only in AI output.
30. **Test gaps.** Add tests for routing and the onboarding redirect, auth, the social repository and screens, and theme widgets.
31. **Android backup.** Set `allowBackup` or data-extraction rules so GPS history is not backed up by default.
32. **Dead code cleanup.** Remove `GlowButton`, the unused `NavigationBar` theme, the unused `ServiceArea` members and the wishlist "quest" type.

---

## Coverage and what is still open

I started a deep multi-area analysis and the results for tracking and XP, social, profile and achievements, and the memories Flutter UI were lost before they could be merged (the working folder was cleared and the analysts hit an API rate limit that resets at 10:20 am EST). So:

- **Deep and verified:** foundation (config, database, routing, services, theme, auth, onboarding, preferences), planner and AI, discovery and map (key claims re-checked), the memories backend, `verifyTrip`, and the Firestore rules.
- **Shallower:** live tracking internals (state machine, navigation details), social screens and repository, achievements and rank code, and memories UI. These rely on the docs, routes and the lower-depth reads above. The XP numbers in the app-side column of the XP table are **per docs** and not re-verified against `trip_guard.dart` or `tracking_service.dart`.
- **Not checked:** `storage.rules` contents, the exact JS test counts, whether the Firestore rules or the function are deployed, and any behaviour that needs a device.

A second pass on tracking and XP, social, and profile and achievements would close these.
