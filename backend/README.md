# Memories API

Shared trip memories for the app. **MongoDB** keeps the records and the photos
and videos (in GridFS). Login stays with Firebase: the server only checks the
user's Firebase login token, so it needs no Firebase credentials.

What it does: share a photo or video (friends or public), change who can see
it, delete it, list what friends or everyone shared, and serve the files with
seeking for video. Files are served through links that are signed and expire
after 6 hours; the feed hands out fresh ones.

**Audio capsules** are voice notes left at a spot (`type=voice`, up to 5 MB,
`audio/mp4`, `aac` or `mpeg`, location required, at most 2 per person within
50 m). `GET /memories/nearby?lat=&lng=&radius=` lists the ones near a point
(public, plus friends' ones), nearest first, radius up to 2 km (default
500 m). `POST /memories/:id/report` reports someone else's memory or capsule;
after 3 different people report it, it is hidden from every list (the record
stays for review). Capsules are found with a `2dsphere` index on `geo`,
created at start-up.

**Sightseer Lens**: `POST /lens?lat=&lng=&near=` with a JPEG, PNG or WebP
photo (up to 4 MB) as the body asks Gemini what it shows and returns
`{ name, style, era, summary, details[3], confidence }`. The Gemini key stays on
this server. 30 uses per person per day (counted in memory, so a restart
resets it).

## Run it on your laptop (to test with a phone)

Needs Node 20+ and a MongoDB (the local one works).

```
cd backend
npm install
MONGODB_URI=mongodb://127.0.0.1:27017 MEDIA_SECRET=anything-long FIREBASE_PROJECT_ID=clone-2353a node server.js
```

On Windows PowerShell:

```
$env:MONGODB_URI="mongodb://127.0.0.1:27017"; $env:MEDIA_SECRET="anything-long"; $env:FIREBASE_PROJECT_ID="clone-2353a"; node server.js
```

Find your laptop's Wi-Fi address (`ipconfig`, e.g. 192.168.1.20), allow port
8080 through the Windows firewall, and run the app (debug build) with
`"MEMORIES_API_URL": "http://192.168.1.20:8080"` in `dart_defines.local.json`.
Phone and laptop must be on the same Wi-Fi. Release builds only allow https.

## Put it online (free)

1. **MongoDB Atlas** (cloud.mongodb.com): create a free M0 cluster, add a
   database user, and under *Network Access* allow `0.0.0.0/0` (Render's
   addresses change). Copy the connection string (`mongodb+srv://...`).
   The free tier holds 512 MB, roughly a few hundred photos or a handful of
   videos in total.
2. **Render** (render.yaml is at the project root): push the project to
   GitHub, choose *New > Blueprint*, pick the repo, and paste the Atlas
   string as `MONGODB_URI` when asked. `MEDIA_SECRET` is generated for you.
3. When it is live, copy its address (https://rwe-memories.onrender.com or
   similar) into `dart_defines.local.json` as `MEMORIES_API_URL`, and use the
   same value in release builds: `--dart-define=MEMORIES_API_URL=https://...`.

The free Render server sleeps when idle, so the first request after a quiet
spell can take up to a minute. The app waits for it.

## Environment variables

| Name | What |
|---|---|
| `MONGODB_URI` | MongoDB connection string (required) |
| `MEDIA_SECRET` | Long random text that signs media links (required) |
| `FIREBASE_PROJECT_ID` | `clone-2353a` (required) |
| `MONGODB_DB` | Database name, default `rwe` |
| `PORT` | Set by Render; default 8080 |
| `GEMINI_API_KEY` | Optional. Turns on the Sightseer Lens (`POST /lens`); without it the lens answers 503 |
| `GEMINI_MODEL` | Optional, default `gemini-flash-latest` |

## Tests

```
npm test                                   # in-memory store
MONGODB_TEST_URI=mongodb://127.0.0.1:27017 npm test   # also against real MongoDB
```

The second form creates and drops its own database (`rwe_test_...`).

## Known limits

- **Friends-only is checked by the server.** `server.js` reads accepted
  friendships from Firestore (Firebase Admin) for every friends-only request,
  so the friend list the app sends is only used to narrow the result.
- Reports hide a memory after 3 different reporters; reviewing them is
  manual (MongoDB). Delete requests from the owner and account deletion work.
- Uploads are capped at 50 MB per file and 300 shared memories per person.
