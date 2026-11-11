# How to earn XP and achievements (and how we check)

The rule behind all of it: **XP is paid for being at a real place, not for
pressing buttons.** Every reward needs *proof of presence*, and each proof is
checked by code in the app. This file lists every way to earn, what proves it,
and what stops cheating. It is written to match the code; if you change a
number in the code, change it here.

Status: **Built** = in the app and covered by tests. **Planned** = designed,
not built yet.

---

## 1. Earning XP

### Journey and trek

Every trip is split in two (`trip_split.dart`, server copy `functions/lib/trip_split.js`):

| | What it is | Counts for |
|---|---|---|
| **Journey** | Getting to the trek's start and back, by **any transport** (walk, car, bus, train) | Shown for planning (place sheet: distance and time by car and on foot) and in the trip summary. **Never** counts for XP bonuses, achievements, stats or difficulty |
| **Trek** | Time and distance **on foot** once you are **within 200 m of the trek's start** (the place the trip goes to; for a trip with no place, where the trip begins), **return hike included** | The completion bonus, the Trek km achievement, profile and journal distance, trek difficulty |

- On foot vs vehicle is judged on the last 30 s of movement: faster than **4 m/s (14.4 km/h)** on average is a vehicle. A step at walking speed always counts as on foot, so getting out of a car counts straight away.
- A vehicle leg of **300 m or more** after the trek starts means you are heading back: from then on it is journey, unless you come back to the trek's start on foot.
- Standing still counts on the side you were on: resting on the trek is trek time, waiting in traffic is journey time. Paused time counts as neither.
- The **total trip time** (everything, excluding pauses) is shown separately from the trek time.
- Trek difficulty comes from trek distance only: under 3 km Easy, under 8 km Moderate, under 15 km Challenging, otherwise Hard.
- Trips recorded before this split were all on foot, so the upgrade counts all of their distance and time as trek.

### What you earn

| # | How you earn | XP | Proof the app requires | Limits |
|---|---|---|---|---|
| 1 | **Reach a place** on a trip (Start from a place's sheet) | 60–110 by kind of place (shown on the place as "+N XP") | All of: (a) you started the trip **100 m or more** from it; (b) your recorded walk covers **at least 60%** of the straight-line distance; (c) **at least 60 s** into the trip; (d) your GPS shows **no fake or teleporting readings**; (e) you reach **within 40 m** of it; (f) you take a **photo with the live camera while you are there** (the gallery is not offered). The photo counts only if the last good GPS reading is **under 90 s old** and **within 100 m** of the place, and the photo itself is **under 2 minutes old** | A place pays XP **once every 7 days**. Revisits still count as visits, with 0 XP. Counts toward the **1,500 XP/day** trip cap |
| 2 | **Complete a trip** (press Finish) | +100 | Your **trek** (on foot, from within 200 m of the trek's start) was **at least 200 m** over **at least 2 minutes**, and the GPS was clean for the whole trip. The journey there doesn't count, however long | Counts toward the 1,500 XP/day cap. A trip that fails is saved as **"Trip not counted"**, earns nothing, and counts toward no achievement |
| 3 | **Claim an achievement star** | 50 / 150 / 400 | The star's target is reached (section 2). You press **Claim** yourself | Each star pays once. Not part of the daily cap (it is limited by the targets) |

Everything in the table is **Built**.

Example: *"take a photo there and upload there, then it's achieved."* In the
app, that is row 1. The photo is the proof; it is saved to your memories at
once, and you can share it later (it is not uploaded automatically).

### What you see when something doesn't count
The trip screen shows the reason in plain words, for example "Your location
jumped further than anyone can travel, so this trip can't earn XP", "You
started less than 100 m from this place", or "Take the photo while you are at
Sukhna Lake". Nothing is silently dropped.

---

## 2. Achievements (3 stars each, claim bonus XP)

Full set per achievement: **600 XP** (50 + 150 + 400). All six: **3,600 XP**.

| Achievement | Counts | Stars at | Exactly what counts | Proof / limit |
|---|---|---|---|---|
| **Trail Walker** | Adventures | 1 / 5 / 20 | Trips that passed the completion check (row 2 above) | A trip must be real: 200 m and 2 min of trek, clean GPS |
| **Long Walker** | Kilometres | 5 / 25 / 100 | **Trek** distance of counted trips ("Trek N km in total"). Journey distance never counts. Distance is only added from **verified** readings: no fake or imprecise ones, no teleports, no sub-3 m wobble | Driving, standing still, or GPS jumping adds nothing |
| **Destination Hunter** | Places reached | 3 / 10 / 30 | **Different** places reached on counted trips with the proof photo (row 1) | A place visited five times counts once |
| **City Explorer** | Places discovered | 5 / 15 / 30 | Places revealed on the map by walking within 250 m | Location from a mock-location app is ignored |
| **Memory Maker** | Photos and videos | 3 / 15 / 50 | Photos and videos made **on counted trips** | **At most 5 per trip**, so adding one gallery photo again and again can't farm it; more memories need more real trips |
| **Storyteller** | Voice notes | 1 / 5 / 15 | Voice notes made on counted trips | **At most 3 per trip** |
| **Step Master** | Trek steps | 10,000 / 50,000 / 250,000 | Steps counted by the phone's **step sensor** while **trekking** on counted trips. Journey steps don't count | Needs the Physical activity permission and a phone with a step sensor. Steps while paused, phone restarts and impossible jumps (over 6 steps a second) are ignored |

Everything in the table is **Built**.

---

## 3. Cheats, and what stops each one

| Cheat | What stops it | Where |
|---|---|---|
| **Fake-GPS app** (Android mock location) | Android marks the readings as mock; the trip is flagged and earns nothing. The map ignores them too, so places aren't discovered. *(Debug builds allow mocks so the app can be tested on an emulator.)* | `trip_guard.dart`, `location_service.dart` |
| **Teleporting** (jump to the place) | Moving faster than 45 m/s (162 km/h, above any car, bus or train here) between two readings flags the trip. The limit allows vehicles on the journey but is kept as low as honest travel allows: a spoofer who jumps and stays keeps failing until the jump looks like a drive | `trip_guard.dart` |
| **Hiding the mock flag** (rooted phone, hardened spoofer) | Not detectable on the phone alone. It still has to *walk* plausibly (speed, distance share, time), take a **live camera photo**, and stay under the **daily cap** and **weekly place limit**, so the gain is small. Real protection needs a server (section 4) | |
| **Start then Finish repeatedly** for +100 | The bonus needs 200 m and 2 minutes of verified trek | `trip_guard.dart` |
| **Starting next to a place** and "arriving" | Start must be 100 m or more away, and you must have walked 60% of the distance | `trip_guard.dart` |
| **Same place again and again** | One XP payout per place per 7 days | `tracking_service.dart` |
| **Unlimited trips in a day** | 1,500 XP/day cap on trip XP | `tracking_service.dart` |
| **Gallery photo as proof** | The proof camera has no gallery, and the photo must be under 2 minutes old with a fresh GPS reading at the place | `camera_screen.dart` |
| **Taking the photo elsewhere, submitting later** | Proof needs a GPS reading under 90 s old within 100 m of the place when the photo is submitted | `trip_guard.dart` |
| **Standing still / GPS drift counted as walking** | Steps under 3 m and readings worse than 50 m accuracy are ignored | `trip_guard.dart` |
| **Farming memory achievements** | Per-trip caps (above) | `achievement.dart` |
| **Claiming an achievement twice** | The claim is saved before the XP is paid | `achievement_service.dart` |
| **Writing a huge XP number to the leaderboard** | Database rules: a new profile starts at 0; XP can rise by at most 20,000 on the first sync, then 1,000 + 3,000 per day, only with the server's clock; it can't be rewound or wiped. Tested against the Firestore emulator (23 tests) | `firestore.rules`, `firebase_tests/` |

---

## 4. What is NOT stopped yet (honest limits)

A phone is a computer the player controls. The score is kept on the phone, and
the app can only check it from the inside, so these remain possible:

1. **Editing the saved XP on a rooted phone.** The local database and the
   saved claims can be changed. This inflates the player's own screen, and,
   within the rate limits above, their leaderboard entry.
2. **A good GPS spoofer** that hides the mock flag and moves at walking
   speed. It still needs the camera photo and is held to the daily cap, but
   nothing on the phone can *prove* the person was there.
3. **A photo of a photo**, or an old photo of the place shown to the camera.

**The real fix: a server that decides XP.** Planned, in this order:

| Step | What | Needs |
|---|---|---|
| 1. **Server-verified trips** — *built and tested, not deployed* | When a trip finishes, the app uploads the trip's proof (the path with times and accuracy, and the proof photo). A Firebase **Cloud Function** re-runs the same checks as `TripGuard` and writes the XP to a field the player **cannot write** (rules deny client writes). The leaderboard ranks that field only | Firebase Blaze plan (already needed for Storage), `firebase login` to deploy |
| 2. **Device integrity** | **Firebase App Check with Play Integrity**: the server only accepts requests from the genuine app on an unmodified, certified phone | Console setup; Play Console link |
| 3. **Photo check** | The server asks an AI model whether the photo shows the place (compared with its Wikipedia photos), and rejects screenshots and photos of screens | Gemini key kept **on the server** |
| 4. **Cross-checks** | Phone step counter vs distance walked (free, hard to fake together with GPS) and the phone's own clock vs the server's. *Steps are now counted and stored per trip, but not yet used to judge XP: a phone in a bag or a missing sensor must not cost honest players* | Activity-recognition permission (asked at trip start) |
| 5. **Strongest proofs at special places** | A **QR code** or **NFC tag** placed at partner locations; scanning it is proof you were physically there | Partners, printing |
| 6. **Community** | A "Report" button on shared photos and suspicious scores; manual review | Moderation process |

**Step 1, where it stands.** Code is in `functions/` (`verifyTrip`):

- It re-runs the same checks as `TripGuard` (`lib/trip_guard.js`, tested to match
  the app's rules), sets the XP itself from its own table (an app can't ask for
  more), enforces the 7-day place cooldown and 1,500 XP/day, rejects old,
  future, oversized or malformed trips, and pays each trip id **once**
  (replays and edited resubmissions return the first answer).
- XP goes to `verified_xp/{uid}`, which `firestore.rules` lets nobody write
  from the app (emulator-tested).
- The app records fixes and sends them when a trip ends, behind
  `FeatureFlags.serverVerifiedXp` (**off**).
- Tests: 62 for the function, 32 for the rules, 83 for the app.

Still to do before it protects anything: deploy the function (Blaze plan,
`firebase login`), publish the rules, turn the flag on, **then switch the
leaderboard and achievements to read `verified_xp`** (they still use the
profile's `totalXp`, which a modified app can inflate within the rate limit).
Be clear on what the server can and can't do: it can reject impossible paths
and stop repeats, but it **cannot prove the GPS readings were true**. A faked
path that looks like a plausible walk, with a live photo, still passes. That
is what steps 2 to 5 narrow.

Until the leaderboard reads server XP, treat it as **for fun**, not for real
prizes.

---

## 5. The numbers (all in one place)

| Value | Setting | Where |
|---|---|---|
| Ignore GPS readings less accurate than | 50 m | `TripGuard.maxAccuracyMeters` |
| Fastest believable movement | 45 m/s (162 km/h) | `TripGuard.maxSpeedMetersPerSecond` |
| Smallest jump counted as a teleport | 60 m | `TripGuard.minJumpMeters` |
| Movement counted as walking | 3 m or more | `TripGuard.minStepMeters` |
| Start at least this far from a place | 100 m | `TripGuard.minStartDistanceMeters` |
| Share of the distance that must be walked | 60% | `TripGuard.minTravelShare` |
| Minimum time before arrival counts | 60 s | `TripGuard.minArrivalSeconds` |
| Trip counts as completed after | 200 m and 2 min **of trek** | `TripGuard.minCompletionMeters/Seconds` |
| Trek starts within | 200 m of its start | `TripSplit.trekStartRadiusMeters` |
| Faster than this on average is a vehicle | 4 m/s (14.4 km/h) over 30 s | `TripSplit.maxTrekSpeedMetersPerSecond` |
| Vehicle leg that means heading back | 300 m | `TripSplit.vehicleLegMeters` |
| Proof photo: GPS reading no older than | 90 s | `TripGuard.proofFreshnessSeconds` |
| Proof photo: within place radius plus | 60 m (radius is 40 m) | `TripGuard.proofSlackMeters` |
| Proof photo: itself no older than | 120 s | `confirmArrivalWithPhoto` |
| Daily cap on trip XP | 1,500 | `TrackingService.dailyTripXpCap` |
| A place pays XP once every | 7 days | `TrackingService.placeCooldown` |
| Memories counted per trip | 5 photos/videos, 3 voice notes | `achievement.dart` |
| Leaderboard XP rise allowed | 20,000 once, then 1,000 + 3,000/day | `firestore.rules` |

---

## 6. Testing

- **App logic:** `flutter test` — `trip_guard_test.dart` (25 tests: fake GPS,
  teleports, walking, arrival, photo proof, completion), `achievements_test.dart`
  (star, claim and per-trip-cap rules), and the others.
- **Database rules:** `cd firebase_tests && npm install && npm test`
  (needs Java 21+). Tries honest and dishonest XP writes, 23 checks.
- **Not tested automatically:** the camera and the real GPS hardware. Walk a
  real trip on a phone to check them.

## Rank rewards (what your total XP unlocks)

Each rank unlocks a **profile frame** (the ring around your avatar) and a **trail colour** (the path you walk on the trip map). Tap an unlocked style on the Achievements screen to wear it. If XP is ever lower than a style needs (reinstall, reset), the best unlocked style is used instead. These are cosmetic by design: nothing here gives XP, so there is nothing to farm.

| Rank | XP | Frame | Trail |
|---|---|---|---|
| Beginner | 0 | Mint | Amber |
| Explorer | 1,000 | Bronze | Blue |
| Adventurer | 2,500 | Silver | Coral |
| Pathfinder | 6,000 | Gold | Purple |
| Trailblazer | 12,000 | Aurora | Pink |
| Expedition Leader | 25,000 | Flame | Orange |
| Legendary Explorer | 50,000 | Legend gold | Gold |
