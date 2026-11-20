# Tabi: manual test cases

Step-by-step test cases for every feature, for testing on real phones. Automated tests already cover the logic (`flutter test`); these cases check what a person sees and does.

**How to use this file**
- Each case has an **ID**, any **setup** needed, numbered **steps**, and the **expected** result. Mark it Pass, Fail or Blocked, and note the phone, the Android or iOS version and the build.
- **Blocked today:** the live-trip screen for trips *to a place* (`navigation_view.dart` is empty and must be restored). Those cases are marked ⛔.
- "Signed in" means signed in with an account. "Friend" means a second account on a second phone that has accepted a friend request.

## Contents

0. [Before you start](#0-before-you-start)
1. [Install, first launch and onboarding](#1-install-first-launch-and-onboarding)
2. [Accounts](#2-accounts)
3. [Tabs and navigation](#3-tabs-and-navigation)
4. [Explore (Home)](#4-explore-home)
5. [City page](#5-city-page)
6. [Place sheet](#6-place-sheet)
7. [Tips on places](#7-tips-on-places)
8. [Wishlist](#8-wishlist)
9. [Map](#9-map)
10. [Places to eat](#10-places-to-eat)
11. [Voice notes on the map](#11-voice-notes-on-the-map)
12. [Live trip](#12-live-trip)
13. [XP rules and trips that don't count](#13-xp-rules-and-trips-that-dont-count)
14. [Trip planner](#14-trip-planner)
15. [Itinerary](#15-itinerary)
16. [Adjust my day](#16-adjust-my-day)
17. [Trip essentials](#17-trip-essentials)
18. [My Trips](#18-my-trips)
19. [Shared trips between phones](#19-shared-trips-between-phones)
20. [Sharing a trip and publishing a tour](#20-sharing-a-trip-and-publishing-a-tour)
21. [Community tours](#21-community-tours)
22. [Trip album](#22-trip-album)
23. [Share trip photos](#23-share-trip-photos)
24. [Camera](#24-camera)
25. [Review screen](#25-review-screen)
26. [Memories](#26-memories)
27. [Journal, calendar and trip details](#27-journal-calendar-and-trip-details)
28. [You tab](#28-you-tab)
29. [Achievements](#29-achievements)
30. [Passport stamps](#30-passport-stamps)
31. [Exploration map and poster](#31-exploration-map-and-poster)
32. [Streak and daily challenge](#32-streak-and-daily-challenge)
33. [Friends](#33-friends)
34. [Groups and meetups](#34-groups-and-meetups)
35. [Leaderboard, feed and footprints](#35-leaderboard-feed-and-footprints)
36. [Friend challenges](#36-friend-challenges)
37. [Safety and SOS](#37-safety-and-sos)
38. [Weather advice](#38-weather-advice)
39. [Preferences and reminders](#39-preferences-and-reminders)
40. [Settings and privacy](#40-settings-and-privacy)
41. [Offline maps](#41-offline-maps)
42. [AR guide and Identify (Lens)](#42-ar-guide-and-identify-lens)
43. [Ecosystem (hidden)](#43-ecosystem-hidden)
44. [Accessibility](#44-accessibility)
45. [Tablets and landscape](#45-tablets-and-landscape)
46. [No signal and bad connections](#46-no-signal-and-bad-connections)
47. [Updating from an older version](#47-updating-from-an-older-version)

---

## 0. Before you start

**Builds to test**

| Build | Settings (`--dart-define`) | Use for |
|---|---|---|
| **A: basic** | none | Everything that must work with no accounts or servers |
| **B: full** | Firebase, `MEMORIES_API_URL`, `GEMINI_API_KEY`, `MAPTILER_KEY`, `DRIVE_API_KEY`, `GOOGLE_SERVER_CLIENT_ID` | Accounts, friends, sharing, AI, offline maps, album |

**Devices:** at least one Android phone with GPS and a SIM (for SOS texts), a second phone for the friend cases, and a tablet or a phone in landscape for section 45. Test once on a small phone (360 dp wide or less).

**Accounts:** account **A** (email and password), account **B** (Google), and a Google account with Drive for the album.

**Fresh start:** uninstall the app, or clear its data, before sections 1, 2 and 47.

---

## 1. Install, first launch and onboarding

**TC-ONB-01 · First launch shows onboarding straight away**
1. Install and open the app.
- Expected: the "Welcome to Tabi" page is the first thing you see. Explore never flashes first, and no location prompt appears yet.

**TC-ONB-02 · Pages**
1. Swipe through, or tap Continue.
- Expected: three pages: Welcome to Tabi, How XP Works, Why Location Matters. The dots show the page, and a screen reader says "Page 2 of 3".

**TC-ONB-03 · Finishing asks for location once**
1. On the last page, tap **Enable Location & Start Exploring**.
- Expected: Android/iOS asks for location permission (once, even if you tap twice), then Explore opens.

**TC-ONB-04 · Skip doesn't ask for location**
1. Fresh install, then tap Skip on page 1.
- Expected: Explore opens with **no** permission prompt. The app asks later, when a feature needs location (for example Around you's **Turn on location**).

**TC-ONB-05 · Onboarding only once**
1. Close the app completely and open it again.
- Expected: it opens straight on Explore.

**TC-ONB-06 · Location refused**
1. Fresh install, finish onboarding, and deny location.
- Expected: Explore still opens. Around you offers **Turn on location**, and the Map shows "Location is off" (TC-MAP-08).

**TC-ONB-07 · Small phone, large text**
1. Set the largest font size on a small phone, then fresh install.
- Expected: each page's text can be read in full (it scrolls if needed). Nothing is cut off, and the buttons stay visible.

---

## 2. Accounts

*Build B.*

**TC-ACC-01 · Sign up asks for a name**
1. Friends → Sign in → "Don't have an account? Create one".
- Expected: a "Your name" field ("What friends and other explorers see") appears above Email and Password. Submitting empty fields shows "Enter your name", "Enter a valid email" and "At least 6 characters", and nothing is sent.

**TC-ACC-02 · Sign up**
1. Enter a name, a new email and a password (6+ characters) → Create account.
- Expected: you're signed in and returned to where you came from. Your name (not your email) is what Friends and the leaderboard show, and Settings shows your email under ACCOUNT.

**TC-ACC-03 · Email already used**
1. Sign up again with the same email.
- Expected: "An account with this email already exists. Sign in instead."

**TC-ACC-04 · Wrong password**
1. Sign in with the right email and a wrong password.
- Expected: "Wrong email or password." You stay on the screen; no technical code is shown.

**TC-ACC-05 · Reset password**
1. Forgot password? → enter your email → Send link.
- Expected: "If there's an account for that email, a reset link is on its way…". The message is the same whether or not the email has an account. A real reset email arrives for a real account.

**TC-ACC-06 · Sign in with Google**
1. Continue with Google → pick an account.
- Expected: signed in. A first Google sign-in creates your profile with your Google name. Closing the Google window shows no error.

**TC-ACC-07 · No connection**
1. Airplane mode → Sign in.
- Expected: "No connection. Check your internet and retry." (or "Something went wrong. Check your connection…"). The button stops spinning.

**TC-ACC-08 · Sign out asks first**
1. Settings → Sign out.
- Expected: a confirmation. Confirming signs you out; trips and memories stay on the phone.

**TC-ACC-09 · Delete account dialog**
1. Settings → Delete account.
- Expected: lists what is permanently deleted (profile and photo; friends, posts, map and live location; trips saved to your account; your album photos and their Google Drive copies; shared memories, tips, tours, challenges; groups and meetups you created; your sign-in) and what stays (group chat messages, the server's record of verified XP, everything on the phone). The delete button stays greyed until the password is typed.

**TC-ACC-10 · Delete account, wrong password**
1. Enter a wrong password → Delete my account.
- Expected: "That password is incorrect." and nothing is deleted.

**TC-ACC-11 · Delete account**
1. Create a test account with a trip you own, a trip shared with you, a tip, a published tour, a group you created and an album photo. Delete it with the right password.
- Expected: "Your account has been deleted." In the Firebase console: your `explorers`, `trip_plans` (owned), album `photos`, `curated_tours`, tips, groups and avatar are gone; you are removed from trips and groups owned by others. The email can't sign in again.

**TC-ACC-12 · Delete interrupted**
1. Turn off the network mid-delete.
- Expected: "Couldn't finish deleting…". The account still exists and can sign in. Deleting again finishes the job.

**TC-ACC-13 · Delete a Google account**
1. Signed in with Google only: Delete account.
- Expected: no password box; Google asks you to confirm, then it deletes as above.

**TC-ACC-14 · Build A has no accounts**
1. In build A, open Settings and the Friends tab.
- Expected: "Sign-in unavailable… Everything else works without one." No developer text.

**TC-ACC-15 · Small phone, large text**
1. Largest font on a small phone: open sign-in and sign-up.
- Expected: nothing cut off; the form scrolls.

---

## 3. Tabs and navigation

**TC-NAV-01 · Five tabs**
1. Look at the bottom bar.
- Expected: Explore, Map, Trips, Friends, You, each with an icon and label. The selected tab is filled.

**TC-NAV-02 · Tabs keep their place**
1. Scroll down on Explore, then switch to Map and back.
- Expected: Explore is still scrolled where you left it.

**TC-NAV-03 · Tapping the current tab again**
1. Open a city from Explore, then tap Explore in the bar.
- Expected: it goes back to Explore's first screen.

**TC-NAV-04 · Back button inside a tab**
1. Open a city, then a place sheet, then Settings, pressing the phone's Back each time.
- Expected: each press goes back one step.

**TC-NAV-05 · Back from another tab (Android)**
1. Open the Trips tab and press Back.
- Expected: it goes to **Explore** (not out of the app). Pressing Back again on Explore leaves the app.

**TC-NAV-06 · Friends badge**
1. Have another account send you a friend request.
- Expected: after you open the app (or pull to refresh on Friends), the Friends tab shows a badge with the number of requests waiting. Accepting or declining them clears it. Only requests waiting for *you* count, not ones you sent or accepted friends.

**TC-NAV-07 · Active trip bar**
1. Start a free trip (TC-TRIP-01), then switch tabs.
- Expected: above the tab bar, on every tab: "On a trip · mm:ss · X km" with **Open** and **SOS**. Open returns to the trip. When paused: "Paused" and **Resume**.

**TC-NAV-08 · No trip, no bar**
1. Finish or discard the trip.
- Expected: the bar disappears.

**TC-NAV-09 · Screen reader**
1. With TalkBack/VoiceOver on, swipe across the bar.
- Expected: each tab is read once ("Explore, selected, button"), and Friends reads "Friends, 2 new" when there is a badge.

**TC-NAV-10 · Old links**
1. Open the link `/my-trips`.
- Expected: the Trips tab opens.

---

## 4. Explore (Home)

**TC-HOME-01 · Header**
1. Open Explore.
- Expected: a greeting with your name, and your location line (city or "Locating…") with a ⌄. Weather appears once.

**TC-HOME-02 · Change city from the header**
1. Tap the location line.
- Expected: the city picker opens. Picking a city changes Around you to that city.

**TC-HOME-03 · Search**
1. Type "Jaipur" in the search bar.
- Expected: matching cities and places appear as you type. Tapping a city opens its page, and tapping a place opens the place sheet.

**TC-HOME-04 · Search everywhere and recent searches**
1. Search for something not in the list, then tap search or "Search everywhere".
2. Clear the field.
- Expected: wider results appear. Your recent searches are listed when the field is empty.

**TC-HOME-05 · "Now" card with no trip**
1. With no trips saved, look under the search bar.
- Expected: "Explore around you" with **Start exploring** and **Plan a trip**, and today's weather in the text.

**TC-HOME-06 · "Now" card with a trip today**
1. Plan a trip that starts today (TC-PLAN-04), then go back to Explore.
- Expected: the card shows today's trip and its next stop, instead of "Explore around you". Tapping it opens the trip at today's day.

**TC-HOME-07 · Upcoming trip**
1. Have a trip starting in a few days.
- Expected: the card shows the upcoming trip with its date.

**TC-HOME-08 · Daily challenge**
1. Look below the Now card.
- Expected: the daily challenge card (see section 32).

**TC-HOME-09 · Around you appears fast**
1. Open the app after you've used it before, with data on.
- Expected: places already saved on the phone appear within a second or two, without waiting for the internet. New places join the list a few seconds later. (A brand-new install shows a loading row until the first lookup ends, never a false "Nothing here yet".)

**TC-HOME-10 · Around you cards**
1. With location on, scroll to Around you.
- Expected: nearby places, nearest first, with photo, "Open now / Closed now" when known, kind, +XP and distance. Tapping one opens the place sheet. Chips (All, Temples & heritage, Nature, Food, Photo spots, Hidden gems) only appear for kinds that exist nearby.

**TC-HOME-11 · Distance**
1. Tap "Within N km" and pick another distance.
- Expected: the list changes. With nothing in range, "Look within 50 km" widens it and the distance **stays** there (it does not snap back to your preference).

**TC-HOME-12 · Pull to refresh**
1. Pull the screen down.
- Expected: the spinner stays until the new places have loaded.

**TC-HOME-13 · Around you with location off**
1. Turn location off for the app, then reopen Explore.
- Expected: a "Location is off" banner with **Turn on**, and "Pick a city instead". No endless loading.

**TC-HOME-14 · Around you offline**
1. Airplane mode, then pull to refresh.
- Expected: places already saved still show. With nothing saved: "Couldn't look up places near you. Check your internet connection…" and **Find places nearby**. No technical text.

**TC-HOME-15 · Mystery card**
1. Find the mystery place in Around you.
- Expected: shown as "Mystery Place" with "Mystery · +N XP"; no "???" label.

**TC-HOME-16 · Destinations and AI pick**
1. Scroll down.
- Expected: Destinations shows city cards. In build B with AI, an AI recommendation card appears; in build A it's hidden, with no error.

**TC-HOME-17 · The old blocks are gone**
- Expected: no giant "Where to next?" headline and no quick-actions row. Journal, Memories and Calendar are on the You tab instead.

---

## 5. City page

**TC-CITY-01 · Opens at once**
1. Open Jaipur from Destinations or search.
- Expected: the photo header, the state and kind tags, the description and the **Plan a trip to Jaipur** button appear straight away. Places already saved appear under "Places to explore (N)" without waiting for the internet; new ones join a few seconds later. With nothing saved yet, a spinner shows (never a false "No places found").

**TC-CITY-02 · Sections**
- Expected, in order: signature dishes, community tours (when signed in), the offline map card, then Places to explore with category chips (All places, Heritage, Nature, Viewpoint, Lake, Hidden gem, Photography).

**TC-CITY-03 · Categories**
1. Tap a chip, for example Lake.
- Expected: only that kind. With none: "No lake places here yet. Try another kind." with **Show all places**.

**TC-CITY-04 · Weather**
1. When the city has bad weather: a banner and some places hidden.
- Expected: "Show all" reveals them. If the weather hides everything: "The weather hides these places. Show all to see them."

**TC-CITY-05 · Pull to refresh**
1. Pull the page down.
- Expected: it looks for places again.

**TC-CITY-06 · Offline**
1. Airplane mode, then open a city never opened before.
- Expected: the city shows. With no places saved: "Couldn't look up places here. Check your connection and try again." with **Try again**. With places saved, they simply show, with no error.

**TC-CITY-07 · Explore on Map**
1. Tap the map icon in the photo header.
- Expected: the Map tab opens centred on the city. Going back to Explore, the header still shows your own location (it does **not** change to this city).

**TC-CITY-08 · Plan a trip**
1. Tap Plan a trip to Jaipur.
- Expected: the planner opens with Jaipur filled in. Explore's location is unchanged afterwards.

**TC-CITY-09 · Safety tips**
1. Tap the shield.
- Expected: a sheet with safety advice and helplines.

**TC-CITY-10 · Back and unknown cities**
1. Use Back (header) from a city opened from search.
- Expected: it returns to where you were. Opening a city link that doesn't exist shows "City not found" with **Back to Explore**.

**TC-CITY-11 · Small phone, large text**
1. Largest font on a small phone.
- Expected: the tags wrap, nothing is cut off, and the buttons stay tappable.

---

## 6. Place sheet

**TC-PLACE-01 · Layout**
1. Open any normal place.
- Expected, from the top:
  - photos
  - the name
  - up to 2 tags
  - distance and walk time
  - the description, 3 lines with **More**
  - Getting there
  - tips
- A bar stays at the bottom with "+N XP when you get there", **Start trip**, a bookmark, and ⋮.

**TC-PLACE-02 · Start trip is always in reach**
1. On a small phone, open a place without scrolling.
- Expected: Start trip is visible. Drag the sheet to full height and scroll: the bar stays at the bottom.

**TC-PLACE-03 · More / Less**
1. Tap More under a long description.
- Expected: the full text, with **Less** to collapse it.

**TC-PLACE-04 · Getting there**
1. Wait for the times to load.
- Expected: By car and On foot tiles with distance and time. Offline: "About X km away in a straight line".

**TC-PLACE-05 · How trips are counted**
1. Tap ⓘ next to Getting there.
- Expected: a sheet explaining that your trek starts within 200 m of the place, and only time on foot counts.

**TC-PLACE-06 · Save to wishlist**
1. Tap the bookmark, then tap it again.
- Expected: it fills in (Saved) and then empties. The place appears in, then leaves, the Wishlist.

**TC-PLACE-07 · More menu**
1. Phone within 2 km of the place: tap ⋮.
- Expected: "Point me there (AR)" and "Identify what's here".
2. Repeat for a place more than 2 km away.
- Expected: only "Identify what's here".

**TC-PLACE-08 · Start trip**
1. Tap Start trip.
- Expected: the sheet closes and a trip to the place starts. ⛔ The guidance screen for trips to a place is blocked.

**TC-PLACE-09 · Start with location off**
1. Turn location off, then tap Start trip.
- Expected: "Turn on location to start a trip."

**TC-PLACE-10 · A trip already running**
1. Start a free trip, then open a place and tap Start trip.
- Expected: "You already have an adventure in progress…", and you are taken to the running trip.

**TC-PLACE-11 · Mystery place**
1. Open the mystery place before visiting it.
- Expected:
  - the photo is blurred, with "Photo hidden until you get there"
  - the name shows as "Mystery Place", and a hint replaces the description
  - **Start the hunt**
  - no tips

**TC-PLACE-12 · Mystery solved**
1. Visit the mystery place (a counted trip), then open it again.
- Expected: the real name, photos and a "Mystery solved" tag.

**TC-PLACE-13 · Unknown place (from the Map)**
1. On the Map in Nearby view, tap a "?" pin.
- Expected: "Unknown place", the distance, "Get closer to find out what this place is." and **Head that way**. No name, photos, XP or bookmark.

---

## 7. Tips on places

*Build B, signed in.*

**TC-TIP-01 · Add a tip**
1. In a place sheet, under tips, add "Go at sunrise" and save.
- Expected: it appears with your name. The explorer count updates.

**TC-TIP-02 · 280-character limit**
1. Try to type more than 280 characters.
- Expected: you can't go past 280.

**TC-TIP-03 · Delete your tip**
1. Delete your own tip.
- Expected: it's removed.

**TC-TIP-04 · Report someone's tip**
1. On another person's tip, open ⋮ → Report tip → pick a reason.
- Expected: the tip disappears for you, and the report is sent.

**TC-TIP-05 · Block the author**
1. On another person's tip, open ⋮ → Block, and confirm.
- Expected: their tips disappear everywhere. They appear under Settings → Privacy → Blocked.

**TC-TIP-06 · Signed out**
1. Sign out, then open a place.
- Expected: "Sign in to see and share tips about this place." with a **Sign in** button that opens sign-in.

---

## 8. Wishlist

**TC-WISH-01 · List**
1. Save 3 places, then open the Wishlist (Explore ⋮ menu, or Settings).
- Expected: the 3 places, in the order saved. Tapping one opens its place sheet.

**TC-WISH-02 · Mystery stays hidden**
1. Save the mystery place.
- Expected: it shows as "Mystery Place" in the list.

**TC-WISH-03 · Saved pins on the map**
1. Map → Layers → Mine.
- Expected: saved places you haven't found yet show as amber bookmark pins.

---

## 9. Map

**TC-MAP-01 · Map tab**
1. Open Map with location on.
- Expected: a full-screen map centred on you (your avatar in its frame). The top bar has only "Map" and **Layers**.

**TC-MAP-02 · Layers sheet**
1. Tap Layers.
- Expected: three groups:
  - **SHOW:** Nearby, Everything, Mine, Friends, each with one line of explanation and a ✓ on the current one
  - **EXTRAS:** Places to eat, and Suggest more places (build B with AI only)
  - **WHAT THE PINS MEAN:** the legend, with 6 pin types

**TC-MAP-03 · Nearby view (the default)**
- Expected: places you've found, plus "?" pins within about 1 km. Distant unknown places aren't shown.

**TC-MAP-04 · Everything view**
1. Choose Everything.
- Expected: all places. Layers shows a dot because you're not on the default view.

**TC-MAP-05 · Mine view**
1. Choose Mine.
- Expected: only places you've found or saved, plus your past routes as green lines.

**TC-MAP-06 · Friends view**
1. Signed in with a friend who shares their map, choose Friends.
- Expected: their routes as amber lines. With no friends: an empty map, with no errors.

**TC-MAP-07 · Pins**
1. Look at the pins and tap each kind.
- Expected:
  - visited: green with a ✓ badge
  - found: coloured category pin
  - unknown: "?"
  - Each is easy to tap (about a fingertip) and opens the place sheet.

**TC-MAP-08 · Location off**
1. Deny location, then open Map.
- Expected: a "Location is off" banner with **Turn on**. Tapping it asks for permission; once allowed, the map moves to you.

**TC-MAP-09 · Locate me**
1. Pan away, then tap the locate button (bottom right).
- Expected: the map returns to you. With location off: "Turn on location to see where you are."

**TC-MAP-10 · Suggest more places (AI)**
1. Build B with AI: Layers → Suggest more places.
- Expected: a spinner in the top bar, then "Added N places nearby. Explore to reveal them." (or "No new places found near here."). In build A the option is hidden.

**TC-MAP-11 · Places appear without restarting**
1. Open a city page (which fetches its places), then go back to Map.
- Expected: the new places show without restarting the app.

**TC-MAP-12 · Map credit**
- Expected: a small "© OpenStreetMap contributors" in the corner. Tapping it opens the copyright page.

**TC-MAP-13 · Walking reveals places**
1. Walk within 250 m of a "?" place.
- Expected: it turns into a named, coloured pin.

---

## 10. Places to eat

**TC-FOOD-01 · Food layer**
1. Layers → turn on Places to eat.
- Expected: orange restaurant pins near the map's centre, and a **Search this area** button at the bottom.

**TC-FOOD-02 · Search this area**
1. Pan elsewhere, then tap Search this area.
- Expected: pins for the new area. Where there's nothing: "No places to eat mapped near here."

**TC-FOOD-03 · Food sheet**
1. Tap a food pin.
- Expected:
  - name, a veg/non-veg mark if known, and kind · cuisine
  - "Open now" or "Closed now" with today's hours, when known
  - an OpenStreetMap note
  - **Go there**

**TC-FOOD-04 · Go there**
1. Tap Go there.
- Expected: a trip to that spot starts. ⛔ The guidance screen is blocked.

**TC-FOOD-05 · Add to today's plan**
1. With a trip running today, open a food pin.
- Expected: an extra "Add to today's plan · Day N" button. After tapping: "<name> added as your next stop."

**TC-FOOD-06 · Signature dishes**
1. Open a city page.
- Expected: the city's signature dishes are listed.

---

## 11. Voice notes on the map

*Build B, signed in, `MEMORIES_API_URL` set.*

**TC-CAPS-01 · Button only when available**
1. Signed in: look for the mic above the locate button. Then sign out.
- Expected: the mic shows while signed in and disappears when signed out.

**TC-CAPS-02 · Leave a voice note**
1. Tap the mic, record, and post.
- Expected: a purple pin appears where you are.

**TC-CAPS-03 · Limit per spot**
1. Leave 3 notes at the same spot.
- Expected: the 3rd is refused, with a clear message (2 per 50 m).

**TC-CAPS-04 · Discover someone's note**
1. With phone 2, walk near a friend's note.
- Expected: a vibration and "Voice note here: … by <name>" with **Listen**.

**TC-CAPS-05 · Report**
1. Open a note and report it.
- Expected: it's reported. After 3 reports it's hidden for everyone.

---

## 12. Live trip

**TC-TRIP-01 · Free exploring**
1. Explore → Start exploring.
- Expected: the trip screen shows elapsed time, distance and steps while you walk.

**TC-TRIP-02 · Pause and resume**
1. Pause, walk 50 m, then resume.
- Expected: the time and distance don't grow while paused.

**TC-TRIP-03 · Finish a counted trip**
1. Walk at least 200 m for at least 2 minutes, then Finish.
- Expected: a summary with distance, time, steps, "+100 XP" and the trip added to the Journal.

**TC-TRIP-04 · Discard**
1. Start a trip, then Discard and confirm.
- Expected: no trip is saved. The message doesn't claim XP was deleted.

**TC-TRIP-05 · Share the finished trip**
1. On the summary, tap share.
- Expected: the share sheet with a trip card, **Share image** and **Copy text**. The copied text has no emoji and no "#Chandigarh".

**TC-TRIP-06 · Battery saver**
1. Turn on battery saver in Preferences, then start a trip.
- Expected: the trip still records, with fewer location updates.

**TC-TRIP-07 · Trip survives switching apps**
1. During a trip, open another app for 5 minutes, then come back.
- Expected: the trip is still running and the route kept recording.

**TC-TRIP-08 ⛔ · Trip to a place: guidance**
1. Start a trip from a place sheet.
- Expected (once restored): turn-by-turn steps, spoken guidance, and the destination on the map.

**TC-TRIP-09 ⛔ · Arrival and proof photo**
1. Reach the place (within 40 m).
- Expected (once restored): a live proof photo is requested (camera in proof mode, TC-CAM-20), then "+N XP" for the place.

---

## 13. XP rules and trips that don't count

**TC-XP-01 · Too short**
1. Walk 50 m and finish.
- Expected: "Trip not counted", with the reasons in plain words, and no +100 XP.

**TC-XP-02 · In a vehicle**
1. Record part of a trip in a car or bus.
- Expected: that part counts as the journey, not the trek. The trek distance excludes it.

**TC-XP-03 · Fake GPS**
1. Use a mock-location app.
- Expected: the trip isn't counted, and the reason says so.

**TC-XP-04 · Place XP once a week**
1. Visit the same place twice in 7 days.
- Expected: XP for the place only the first time.

**TC-XP-05 · Daily cap**
1. Earn more than 1,500 trip XP in a day (test account).
- Expected: XP stops at the cap for that day.

**TC-XP-06 · Server check (build B with the flag on)**
1. Finish a counted trip.
- Expected: the trip shows "Verified by the server". The all-time leaderboard uses verified XP.

---

## 14. Trip planner

**TC-PLAN-01 · Opening**
1. Trips → Plan a trip.
- Expected:
  - titled "Plan a trip"
  - Where to?, How many days? (3 days), When? (optional), Who's going?, and a collapsed **Tailor it**
  - **Plan my trip** fixed at the bottom and greyed out

**TC-PLAN-02 · Destination enables Plan**
1. Type "Varanasi".
- Expected: Plan my trip becomes active, and a clear (×) appears in the field.

**TC-PLAN-03 · Choose from popular cities**
1. Tap "Choose from popular cities" and pick Goa.
- Expected: Goa fills the field.

**TC-PLAN-04 · Days stepper and dates**
1. Use − and + to set the days.
2. Pick a start date.
- Expected: it goes from 1 to 10 days; − is greyed at 1 and + at 10. The date button shows the range, for example "Mon, 24 Nov – Thu, 27 Nov".

**TC-PLAN-05 · Who's going**
1. Tap each option.
- Expected: one line under the chips describes the selected option.

**TC-PLAN-06 · Tailor it**
1. Expand Tailor it, and change pace, budget, interests, travelling from and language.
- Expected: the collapsed summary line updates, for example "Balanced · Moderate · Heritage, Street Food".

**TC-PLAN-07 · Preferences prefill**
1. Set preferences (section 39), then open the planner.
- Expected: Who's going, pace and interests start from your preferences.

**TC-PLAN-08 · Planning progress**
1. Tap Plan my trip.
- Expected: a full screen "Planning Varanasi" with a step message that changes every few seconds, "This can take a minute or two." and **Cancel**.

**TC-PLAN-09 · Cancel**
1. Tap Cancel (or Back) while planning.
- Expected: back to the form with your inputs kept. No trip appears in My Trips, even later.

**TC-PLAN-10 · Success**
1. Let it finish.
- Expected: the itinerary opens. Back goes to the screen you started from, not the form.

**TC-PLAN-11 · Error**
1. Plan with airplane mode on.
- Expected: back on the form, a "Trip not planned" banner with a friendly reason and **Try again**.

**TC-PLAN-12 · Hindi**
1. Tailor it → हिंदी, then plan.
- Expected: the plan text comes back in Hindi.

**TC-PLAN-13 · Without AI (build A)**
1. Plan a trip.
- Expected: a simpler plan is still produced.

---

## 15. Itinerary

**TC-ITIN-01 · Header**
1. Open a trip.
- Expected:
  - the destination as the title, with album, share and ⋮ in the top bar
  - "Saved on this phone" (or "Backed up" when signed in)
  - a **Plan | Essentials** switch
  - day chips ("Day 1 · 24 Nov" when dated)

**TC-ITIN-02 · Day content**
1. Look at a day.
- Expected:
  - the day title and theme, "N stops · M done", and a map
  - closed-place and local-tip banners, if any
  - stop rows with travel times between them, then Places to eat

**TC-ITIN-03 · The map doesn't steal scrolling**
1. Swipe up over the map.
- Expected: the page scrolls; the map doesn't pan.

**TC-ITIN-04 · Full-screen map**
1. Tap ⛶ on the map.
- Expected: a full-screen map you can pan and zoom, with numbered stops.

**TC-ITIN-05 · Stop details**
1. Tap a stop row.
- Expected:
  - a sheet with photos, time slot and length, opening hours (tap to see the week), the description and the tip
  - buttons: Mark done, Move earlier, Move later, Remove
  - **Go here · +N XP**

**TC-ITIN-06 · Mark done**
1. Mark a stop done.
- Expected: the row shows a ✓ with the name struck through. The bottom button moves to the next stop.

**TC-ITIN-07 · Reorder**
1. Move a stop later.
- Expected: the order changes, and the map numbers follow.

**TC-ITIN-08 · Remove with Undo**
1. Remove a stop, then tap Undo on the message.
- Expected: the stop comes back.

**TC-ITIN-09 · Go to the next stop**
1. Tap the bottom button "Go to stop N: <name>".
- Expected: a trip to that stop starts. ⛔ Guidance is blocked. Once restored: arriving marks the stop done and offers the next one.

**TC-ITIN-10 · Day finished**
1. Mark every stop done.
- Expected: the bottom shows "Day N done".

**TC-ITIN-11 · Empty day**
1. Remove all of a day's stops.
- Expected: "Nothing planned for this day" with **Plan this day**, and no Go button.

**TC-ITIN-12 · Replan a day**
1. ⋮ → Replan this day → Replan day.
- Expected: new stops, and "Day N replanned" with **Undo**. Undo restores the old day.

**TC-ITIN-13 · Closed that day**
1. Date the trip so that a stop falls on a day it's closed.
- Expected: a warning banner naming the place, with **Replan day**. The stop row says "Closed that day".

**TC-ITIN-14 · Safety from the menu**
1. ⋮ → Safety & helplines.
- Expected: the safety tips sheet.

**TC-ITIN-15 · Opening a specific day**
1. From Explore's Now card (a trip today), open the trip.
- Expected: it opens on today's day.

---

## 16. Adjust my day

**TC-ADJ-01 · Opens straight away**
1. On a day with stops left, ⋮ → Running late? Adjust the day.
- Expected: the sheet opens immediately, showing "Finding where you are…" and then a short explanation.

**TC-ADJ-02 · A reason gives a preview**
1. Pick "Running late" (or tired, or rain).
- Expected: "New plan: N stops, done by about HH:MM". Kept stops have numbers; dropped ones are struck through, with a reason each.

**TC-ADJ-03 · A place is closed**
1. Pick the closed-place reason, then tick a stop.
- Expected: that stop is dropped in the preview.

**TC-ADJ-04 · Apply and Undo**
1. Tap Apply new plan, then Undo.
- Expected: the day changes, then goes back.

**TC-ADJ-05 · Location off**
1. Turn location off, then adjust.
- Expected: "Location is off, so it starts from your next stop."

---

## 17. Trip essentials

**TC-ESS-01 · Switching**
1. Tap Essentials.
- Expected: five cards: Dates & weather, Travelling together, Budget, Packing, Book stays & travel.

**TC-ESS-02 · Add dates**
1. On an undated trip, tap **Add dates** and pick a date.
- Expected: the date range, a season note and (within 16 days) a forecast row.

**TC-ESS-03 · Forecast with large text**
1. Set the phone's font size to the largest, then look at the forecast.
- Expected: the tiles grow; nothing is cut off.

**TC-ESS-04 · Budget**
1. Change travellers with − and +.
- Expected: the totals and the per-person amount update.

**TC-ESS-05 · Packing**
1. Tick items.
- Expected: the progress bar and "N of M packed" update. Each row is easy to tap.

**TC-ESS-06 · Travelling together, no friends**
1. Signed in with no friends, open the friend picker.
- Expected: "No friends yet…" with **Find friends**, which opens the Friends tab.

**TC-ESS-07 · Share the trip with a friend**
1. Pick a friend and save.
- Expected: they appear as a member. See section 19.

**TC-ESS-08 · Booking links**
1. Tap a booking link.
- Expected: it opens in the browser. Nothing is booked in the app.

---

## 18. My Trips

**TC-MYT-01 · Groups**
1. Have trips that are today, upcoming, undated and past.
- Expected: sections HAPPENING NOW (highlighted card), UPCOMING (soonest first), NOT DATED YET, and PAST (latest first).

**TC-MYT-02 · Card**
- Expected: the title; dates or "No dates yet" · N days · who's going; a shared tag when shared; and "N stops planned" or "M of N stops done" with a bar.

**TC-MYT-03 · Delete**
1. ⋮ → Delete trip, then confirm.
- Expected: the trip is removed, and "Trip deleted" appears.

**TC-MYT-04 · Leave a shared trip**
1. As a member (not the owner), ⋮ → Leave trip.
- Expected: it's gone for you, and the owner still has it.

**TC-MYT-05 · Empty**
1. With no trips.
- Expected: "No trips yet" with **Plan a trip** in the middle, and no floating button.

**TC-MYT-06 · Pull to refresh**
1. Signed in, pull down.
- Expected: trips from your account are fetched.

---

## 19. Shared trips between phones

*Two phones, A and B, friends.*

**TC-SYNC-01 · Share**
1. A shares a trip with B (TC-ESS-07).
- Expected: B sees it in My Trips with "Shared with you".

**TC-SYNC-02 · Live changes**
1. A marks a stop done while B has the trip open.
- Expected: B's screen updates within a few seconds.

**TC-SYNC-03 · Both edit offline**
1. Put both phones offline. A reorders Day 1; B marks a Day 2 stop done.
2. Bring both online.
- Expected: both changes are kept on both phones.

**TC-SYNC-04 · Owner deletes**
1. A deletes the trip.
- Expected: on B, opening it shows "Trip not found" with **Go to Trips**.

---

## 20. Sharing a trip and publishing a tour

**TC-SHR-01 · Share sheet**
1. Itinerary → share icon.
- Expected: As text, As an image, and "Publish Day N as a tour".

**TC-SHR-02 · As text**
1. Choose As text, then send to yourself on WhatsApp.
- Expected: a readable day-by-day plan.

**TC-SHR-03 · As an image**
1. Choose As an image.
- Expected: a preview card and **Share image** / **Copy text**. The shared image looks the same on every phone, with icons instead of emoji.

**TC-SHR-04 · Long trip image**
1. Share a 7-day trip as an image.
- Expected: the image shows days 1–3 and "+4 more days".

**TC-SHR-05 · Publish as a tour**
1. Publish Day 1 as a tour (signed in), with a title and description.
- Expected: it appears under the city's community tours.

---

## 21. Community tours

*Build B.*

**TC-TOUR-01 · Browse**
1. Open a city with tours.
- Expected: tours listed with their stop count and rating.

**TC-TOUR-02 · Plan this tour**
1. Open a tour → Plan this tour.
- Expected: a new trip is created with those stops.

**TC-TOUR-03 · Rate**
1. Rate a tour with a review.
- Expected: the rating is saved. You can't rate your own tour.

**TC-TOUR-04 · Delete your own**
1. On your tour, Delete tour, then confirm.
- Expected: "Others will no longer see it", and it's gone.

---

## 22. Trip album

**TC-ALB-01 · Open**
1. Itinerary → album icon.
- Expected: "<Trip> album", a status banner, **Add photos**, and Share in the top bar.

**TC-ALB-02 · Build A or signed out**
- Expected: "Album on this phone" (build A) or "Sign in to share the album" with **Sign in**. Photos you add show **On this phone**.

**TC-ALB-03 · Add from the camera**
1. Add photos → Take a photo → take and use it.
- Expected: "1 photo added to the album". The tile appears with its status.

**TC-ALB-04 · Add from Memories**
1. Add photos → Choose from Memories → pick 3 → Add 3.
- Expected: three tiles. Adding the same memory again adds nothing new.

**TC-ALB-05 · Show where they were taken**
1. Add a photo with the switch on, and another with it off.
- Expected: in the shared album, only the first has a **Where** button.

**TC-ALB-06 · Connect Drive**
1. Build B, signed in, trip backed up: tap **Connect** on the "Connect Google Drive" banner.
- Expected: Google asks for Drive access. After allowing, the banner reads "Shared with N people on this trip".

**TC-ALB-07 · Upload states**
1. Add a photo while online.
- Expected: Waiting → Uploading → (no label) Shared. The header shows "1 uploading" during the upload.

**TC-ALB-08 · What's in Drive**
1. Open Google Drive on the web.
- Expected:
  - a folder "Tabi · <trip>" with two files per photo (a thumbnail and the photo)
  - both set to "Anyone with the link can view"
  - the downloaded files have no location in their details

**TC-ALB-09 · Members see it**
1. On phone B (a trip member), open the album.
- Expected: A's photo, with "Photo by <A>" and the date.

**TC-ALB-10 · Offline then online**
1. Airplane mode → add 2 photos.
2. Close the app, turn airplane mode off, and open the app.
- Expected: the photos show Waiting, then upload by themselves when the app opens.

**TC-ALB-11 · Retry after a failure**
1. Delete a queued photo's file from the phone's storage (or simulate a failure).
- Expected: Failed, with a reason in the viewer and **Retry**.

**TC-ALB-12 · Drive access removed**
1. Remove the app's access at myaccount.google.com, then add a photo.
- Expected: Waiting, with "Connect Google Drive again to upload", and the Connect banner returns.

**TC-ALB-13 · Remove**
1. Open your shared photo → Remove → confirm.
- Expected: it's gone for everyone, and its Drive files are deleted. The original stays in Memories.

**TC-ALB-14 · Not a member**
1. Using a non-member account, try to open the album link.
- Expected: no photos are visible.

---

## 23. Share trip photos

**TC-SHP-01 · Opening**
1. Album → Share.
- Expected: "N new since you last shared", with those photos ticked. The message reads "<Trip> · N photos", and **Remove location from photos** is on.

**TC-SHP-02 · Select**
1. Untick a few, then Select all, then Clear.
- Expected: the button changes: "Share N photos", then greyed "Share".

**TC-SHP-03 · Send to WhatsApp**
1. Share 3 photos to a WhatsApp group.
- Expected: the 3 photos arrive with the message.

**TC-SHP-04 · Location removed**
1. Share to yourself (email or Drive) with the switch on, then check the photo's details on a computer.
- Expected: no GPS location. With the switch off, the location is still there.

**TC-SHP-05 · New since last share**
1. Open Share again.
- Expected: "You've shared all of these before", and all are ticked.

**TC-SHP-06 · Cancelled share**
1. Open the share sheet, then back out without choosing an app.
- Expected: the photos still count as not shared.

---

## 24. Camera

*Open from Memories → Add memory → Camera, or from Album → Take a photo.*

**TC-CAM-01 · Look**
- Expected: a black screen with the preview filling it.
  - Top: ✕, flash, timer and grid.
  - Bottom: zoom 1×/2×, PHOTO / VIDEO / SLOW-MO, then gallery · round button · flip, with "Tap for photo · hold for video" underneath.

**TC-CAM-02 · Take a photo**
1. Tap the round button.
- Expected: a vibration, a quick white flash, then the review screen.

**TC-CAM-03 · Hold for video**
1. Press and hold the button for 5 s, then let go.
- Expected: the button grows and turns red with a filling ring. The top shows "● 0:05 / 1:00" and "Release to stop". Letting go opens "Review video".

**TC-CAM-04 · Slide up to zoom while holding**
1. Hold to record and slide your finger up.
- Expected: the picture zooms in, and the zoom label updates.

**TC-CAM-05 · Video mode**
1. Tap VIDEO, then tap the button.
- Expected: recording starts with "Tap to stop", and the limit shows "/ 10:00". Tapping again stops it and opens the review.

**TC-CAM-06 · Pause and resume**
1. In Video mode, record 5 s, tap **Pause** (left of the button), wait 20 s, tap **Resume**, record 3 s, then stop.
- Expected: while paused: "Paused · 0:05 / 10:00" and "Paused · tap to stop". The final clip is about 8 s, with no paused part.

**TC-CAM-07 · 10-minute limit**
1. In Video mode, record until 10:00.
- Expected: it stops by itself at 10:00 and opens the review.

**TC-CAM-08 · 60-second hold limit**
1. Hold to record for over a minute.
- Expected: it stops at 1:00.

**TC-CAM-09 · Slow motion**
1. Tap SLOW-MO.
- Expected: the camera reopens, and the hint reads "Tap to start · ¼ speed, no sound" (or "½ speed" on some phones).
2. Record 3 s of something moving, then stop.
- Expected: "Review slow motion", playing slowed and silent. After saving, the gallery tile has a slow-motion icon and the playing length, for example 0:12.

**TC-CAM-10 · Slow motion unavailable**
1. On a phone that can't film fast.
- Expected: "Slow motion isn't available on this phone." and the camera switches to VIDEO.

**TC-CAM-11 · Back to normal video has sound**
1. From SLOW-MO, tap VIDEO, record and play it back.
- Expected: the clip has sound.

**TC-CAM-12 · Pinch zoom and 1×/2×**
1. Pinch out, then tap 1×, then tap 2×.
- Expected: smooth zoom with the label showing, for example, 1.6×. The chips jump to 1× and 2×.

**TC-CAM-13 · Tap to focus**
1. Tap a spot on the picture.
- Expected: a yellow ring appears there briefly, and focus and brightness adjust.

**TC-CAM-14 · Double-tap to flip**
1. Double-tap the picture, or tap the flip button.
- Expected: it switches to the front camera, then back.

**TC-CAM-15 · Flash**
1. Tap the flash button repeatedly.
- Expected: off → auto → on (the hint reads "Flash: off/auto/on").
2. With flash on: back camera, photo.
- Expected: the flash fires.
3. Back camera, video.
- Expected: the torch stays on while recording.
4. Front camera, photo.
- Expected: the screen lights white.

**TC-CAM-16 · Timer**
1. Set the timer to 3 s, then tap the button.
- Expected: a big 3, 2, 1, then the photo. Tapping during the countdown cancels it. The 10 s timer works the same way.

**TC-CAM-17 · Grid**
1. Toggle the grid.
- Expected: rule-of-thirds lines appear or disappear.

**TC-CAM-18 · Back while recording**
1. Start recording in Video mode, then press the phone's Back.
- Expected: recording stops and the review opens. The clip isn't lost.

**TC-CAM-19 · Gallery button**
1. Tap gallery and pick a photo.
- Expected: it's saved as a memory.

**TC-CAM-20 · Proof mode (place verification photo)**
1. ⛔ Arrive at a place on a trip (or open the camera in proof mode).
- Expected: "Verification photo · location on" (tap it for "Why a live photo?"). No gallery, no VIDEO or SLOW-MO; the hint reads "Tap for photo".

**TC-CAM-21 · Camera permission denied**
1. Deny camera access, then open the camera.
- Expected: a black screen saying camera access is needed, with **Open settings**.

**TC-CAM-22 · Microphone denied**
1. Deny the microphone, then open the camera.
- Expected: photos work, VIDEO and SLOW-MO are hidden, and "Allow the microphone to record video" is offered.

**TC-CAM-23 · Phone call while recording**
1. Receive a call during a recording.
- Expected: the app doesn't crash, and the clip is saved or the review shows.

---

## 25. Review screen

**TC-REV-01 · Photo review**
- Expected: a black screen titled "Review photo", with Retake and **Use photo** (white).

**TC-REV-02 · Retake**
1. Tap Retake (or ✕, or Back).
- Expected: back on the camera, and the photo isn't saved.

**TC-REV-03 · Several photos from the gallery**
1. Add memory → Photos from gallery → pick 3.
- Expected: "Review photos (1/3)". Swipe between them; the bin removes one; **Use 2 photos**.

**TC-REV-04 · Video review**
- Expected: the video plays, with **Record again** and **Use video**.

---

## 26. Memories

**TC-MEM-01 · Gallery**
1. You → Memories.
- Expected:
  - a flat grid of photos and videos, newest first
  - videos are dark tiles with ▶ and their length
  - an **Add memory** button
  - calendar and "Shared by others" icons in the top bar

**TC-MEM-02 · Empty**
1. With no memories.
- Expected: "No memories yet" with **Add memory**.

**TC-MEM-03 · Filters**
1. With photos and voice notes, use All / Photos & videos / Voice notes.
- Expected: the list filters accordingly.

**TC-MEM-04 · Add memory sheet**
1. Tap Add memory.
- Expected: Camera ("Tap for a photo, hold for a video"), Photos from gallery, Video from gallery, Voice note.

**TC-MEM-05 · Voice note**
1. Voice note → tap the mic → speak 5 s → stop → play it back → Save note.
- Expected:
  - while recording: a pulsing red dot, the timer and "Stops by itself at 3:00"
  - after stopping: play back, **Delete**, **Save note**
  - the saved note shows its date and length in the list

**TC-MEM-06 · Voice note, microphone denied**
1. Deny the microphone, then start a voice note.
- Expected: a "Microphone is off" banner inside the sheet, with **Open settings**.

**TC-MEM-07 · Viewer**
1. Tap a photo.
- Expected: full screen, with the date and time as the title. Tap to hide and show the controls; pinch to zoom.

**TC-MEM-08 · Share out**
1. Viewer → Share.
- Expected: the phone's share sheet with the photo.

**TC-MEM-09 · Post**
1. Build B, signed in: Viewer → Post → Friends → caption → Post.
- Expected: progress, then "Shared with friends" in the viewer. The post uses your display name.

**TC-MEM-10 · Stop sharing**
1. Post → Stop sharing.
- Expected: it's no longer shared.

**TC-MEM-11 · Delete**
1. Viewer → Delete → confirm.
- Expected: it's removed from the gallery.

**TC-MEM-12 · Slow-mo in the viewer**
1. Open a slow-motion clip.
- Expected: it plays slowed, with "Slow motion · play at normal speed". The toggle switches the speed.

**TC-MEM-13 · Shared by others**
1. Build B: open Shared by others.
- Expected: Friends / Everyone tabs, with photo tiles showing the name and caption. Opening one shows the name and date, and ⋮ → **Report**.

**TC-MEM-14 · Missing file**
1. Delete a memory's file from the phone's storage, then open it.
- Expected: "This file can't be opened. It may have been deleted." (not a connection error).

---

## 27. Journal, calendar and trip details

**TC-JRN-01 · Journal**
1. You → Journal.
- Expected: past trips grouped by day.

**TC-JRN-02 · Trip details**
1. Open a trip.
- Expected: the route map, distance on foot, time, steps, XP and the memories from that trip.

**TC-JRN-03 · Calendar**
1. You → Calendar.
- Expected: a month view with marked days. Tapping a day shows its trips and memories.

**TC-JRN-04 · Opening by link**
1. From You → Recent trips, tap a trip.
- Expected: the trip details open, and Back returns to You.

---

## 28. You tab

**TC-YOU-01 · Top card**
- Expected:
  - your avatar in its rank frame and your name
  - "<Rank> · Level N" and the streak flame
  - "1,240 XP", a bar, "1,260 XP to Adventurer"
  - **Rank & styles**

**TC-YOU-02 · Rank & styles**
1. Tap Rank & styles.
- Expected: every rank's frame, previewed with your initial. Locked ones show a 🔒 and "Unlocks at N XP". Tapping an unlocked one wears it ("Wearing the X style").

**TC-YOU-03 · Stats**
- Expected: Trips · km On foot · Places visited.

**TC-YOU-04 · Collections**
- Expected: three tiles: Stars (with a **Claim** tag when XP is waiting), City stamps, and Map (routes & poster). Each opens its screen.

**TC-YOU-05 · Exploration**
1. As a new user.
- Expected: "Places you discover fill in your map here."
2. After exploring.
- Expected: your top city with "N of M places", and **All regions**.

**TC-YOU-06 · All regions**
1. Tap All regions.
- Expected: Cities, Neighbourhoods, Districts, States and Countries. Places not started are hidden until you turn on "Show places not started".

**TC-YOU-07 · Recent trips**
- Expected: up to 3 trips, with "Today / Yesterday / 3 days ago" or a date, km on foot and +XP.

**TC-YOU-08 · Your trips & photos**
- Expected: Journal, Memories and Calendar rows.

**TC-YOU-09 · Settings**
1. Tap the gear.
- Expected: Settings opens.

---

## 29. Achievements

**TC-ACH-01 · List**
1. Open Stars.
- Expected: achievements with stars and progress bars. Ones ready to claim come first.

**TC-ACH-02 · Claim**
1. Claim one.
- Expected: a reward window with "+N XP" and **Continue**. The XP on You goes up.

**TC-ACH-03 · Ranks aren't here**
- Expected: no rank rewards list on this screen (it moved to Rank & styles).

---

## 30. Passport stamps

**TC-STMP-01 · Earn a stamp**
1. Complete a counted visit in a new city.
- Expected: a stamp for that city appears in Passport stamps.

**TC-STMP-02 · Stamp detail and share**
1. Open a stamp → Share stamp.
- Expected: the share sheet with a stamp image.

**TC-STMP-03 · Empty**
- Expected: "No stamps yet", with a short explanation.

**TC-STMP-04 · Tablet grid**
1. On a tablet.
- Expected: more stamps per row, at a normal size.

---

## 31. Exploration map and poster

**TC-HEAT-01 · Map**
1. You → Map (routes & poster).
- Expected: all your routes drawn on a map. Empty: "No routes yet".

**TC-HEAT-02 · Poster**
1. Create poster → pick a colour style.
- Expected: a line-art poster with your name, km walked and places visited.

**TC-HEAT-03 · Share poster**
1. Tap Share poster.
- Expected: the share sheet with a sharp image.

---

## 32. Streak and daily challenge

**TC-STRK-01 · Daily challenge**
1. Read the challenge, then complete it (for example, visit a place).
- Expected: it shows as done, with **Claim XP** available.

**TC-STRK-02 · Streak**
1. Finish a counted trip on 2 days in a row.
- Expected: the streak flame shows 2. Tapping it explains the streak.

**TC-STRK-03 · Streak freeze**
1. Miss a day while you have a freeze.
- Expected: the streak survives and one freeze is used. You earn 1 freeze every 7 days.

---

## 33. Friends

*Build B. Phones A and B.*

**TC-FRD-01 · Layout**
1. Open Friends.
- Expected:
  - the "Friends" title
  - shortcuts Groups · Meetups · Leaderboard · Feed, all visible
  - your profile card
  - Requests (when there are any)
  - Your friends
  - Find explorers, with search

**TC-FRD-02 · Signed out**
- Expected: "Sign in to add friends, join groups and see the leaderboard", with **Sign in**.

**TC-FRD-03 · Send a request**
1. On A, Find explorers → search B → **Add**.
- Expected: the button changes to **Requested**.

**TC-FRD-04 · Cancel a request**
1. Tap Requested.
- Expected: it asks first, then goes back to Add.

**TC-FRD-05 · Accept**
1. On B, open Requests.
- Expected: A's real name, "Wants to be friends", and **Accept** / **Decline**. After Accept, A is listed under "Your friends" on both phones.

**TC-FRD-06 · Friend's map**
1. Tap a friend.
- Expected: their footprint map opens (if they share it).

**TC-FRD-07 · Remove a friend**
1. ⋮ → Remove friend.
- Expected: it asks first, then they move back to Find explorers.

**TC-FRD-08 · Mute, block, report**
1. Mute someone; block someone (with confirmation); report someone (with a reason).
- Expected: muted people's posts are hidden from the feed. Blocked people disappear from search and lists. Report says thanks.

**TC-FRD-09 · Search**
1. Type part of a name.
- Expected: Find explorers filters as you type. Your friends list doesn't change.

**TC-FRD-10 · Edit profile**
1. Tap edit on your card → change name, bio and photo → save.
- Expected: the changes show here and to friends.

---

## 34. Groups and meetups

**TC-GRP-01 · Create a group**
1. Groups → Create Group → name it → public or private.
- Expected: it appears in My Groups.

**TC-GRP-02 · Group chat**
1. Send messages from A and B.
- Expected: messages appear live on both phones.

**TC-GRP-03 · Delete a group**
1. As the creator, Delete group → confirm.
- Expected: it's gone for everyone, with its chat.

**TC-GRP-04 · Meetups (group adventures)**
1. Meetups → Create Group Adventure → location, meeting point, date and visibility.
- Expected: it's listed. Others can join until the group size limit.

**TC-GRP-05 · Live map and radar**
1. Two members start the meetup as a trip, with "Share live location" on.
- Expected: both appear on the Live Map. "Nobody is live right now" when no one is.

**TC-GRP-06 · Ping group**
1. Tap Ping group.
- Expected: the other members get the ping.

**TC-GRP-07 · Cancel a meetup**
1. As the creator, Cancel adventure.
- Expected: it's gone for everyone who joined.

---

## 35. Leaderboard, feed and footprints

**TC-LDR-01 · Leaderboard**
1. Open Leaderboard and switch between This Week / All-Time and Friends / everyone.
- Expected: rankings with you highlighted. "Resets every Monday" on This Week.

**TC-LDR-02 · No friends**
- Expected: "No friends to compare with yet", with a hint.

**TC-FEED-01 · Activity feed**
1. A friend finishes a trip.
- Expected: it appears in your Feed. Posts from muted people don't.

**TC-FOOT-01 · Footprint privacy**
1. Settings → Privacy → Who can see my map → Private / Friends / Public.
- Expected: with Private, friends see "Nothing on this map yet". With Friends, they see your routes.

---

## 36. Friend challenges

**TC-FCH-01 · Send**
1. Friends → Friend challenges → Challenge → pick a friend → 5 km → Send.
- Expected: it's listed as pending.

**TC-FCH-02 · Accept and race**
1. On B, Accept, then both walk.
- Expected: two progress bars update. The winner is shown at the end.

**TC-FCH-03 · Decline**
1. On B, Decline.
- Expected: it disappears for both.

---

## 37. Safety and SOS

**TC-SOS-01 · Safety screen**
1. Settings → Safety & SOS.
- Expected: SOS (hold 2 s), Emergency contacts, Helplines in India, and **Call 112**.

**TC-SOS-02 · Add a contact**
1. Add contact → name, phone, relationship → Save.
- Expected: it's listed. An empty name or number is refused ("Enter a name" / "Enter a phone number").

**TC-SOS-03 · Remove a contact**
1. Remove one, then tap Undo.
- Expected: it comes back.

**TC-SOS-04 · Hold SOS**
1. With a contact added, hold SOS for 2 seconds.
- Expected: the messages app opens with a text to your contacts containing your location link. Releasing early does nothing.

**TC-SOS-05 · SOS without contacts**
- Expected: it says to add a contact first, and Call 112 still works.

**TC-SOS-06 · SOS from the trip bar**
1. During a trip, tap SOS in the active trip bar.
- Expected: the Safety screen opens.

**TC-SOS-07 · Call 112**
1. Tap Call 112 (use a test device; cancel before calling).
- Expected: the dialler opens with 112.

---

## 38. Weather advice

**TC-WX-01 · Bad weather banner**
1. When the forecast is rain, storm or very hot (or on a test build), look at Around you.
- Expected: a banner, for example "Thunderstorm nearby" or "Heavy rain or snow", saying what's left out.

**TC-WX-02 · Hide unsuitable / Show all**
1. Toggle between them.
- Expected: "Showing sheltered places…" versus "Showing every place, whatever the weather."

---

## 39. Preferences and reminders

**TC-PREF-01 · Save preferences**
1. Settings → Preferences & reminders → change interests, duration, difficulty and social preference → Save.
- Expected: "Preferences saved." Around you's radius and the planner defaults follow them.

**TC-REM-01 · Turn on reminders**
1. Turn on streak, daily challenge and friends reminders.
- Expected: Android 13+ asks for notification permission.

**TC-REM-02 · Reminder arrives**
1. Leave the phone until the reminder time (or change the phone's time).
- Expected: a notification, for example "Keep your streak alive". Tapping it opens the app.

**TC-REM-03 · Turn off**
1. Turn the reminders off.
- Expected: no more notifications.

**TC-REM-04 · After a restart**
1. Restart the phone.
- Expected: reminders still arrive at their times.

---

## 40. Settings and privacy

**TC-SET-01 · Groups**
- Expected: ACCOUNT, APP, OFFLINE MAPS, PRIVACY and ABOUT. Build A hides the account group.

**TC-SET-02 · Privacy screen**
1. PRIVACY → Privacy.
- Expected: "Who can see my map" (Private / Friends / Public), plus Blocked (N) and Muted (N) with Unblock / Unmute. Signed out: a sign-in prompt.

**TC-SET-03 · Unblock**
1. Unblock someone.
- Expected: they reappear in Find explorers.

**TC-SET-04 · Licences**
1. ABOUT → Open-source licences.
- Expected: the list includes Inter and Noto Sans Devanagari.

---

## 41. Offline maps

*Build B with `MAPTILER_KEY`.*

**TC-OFF-01 · Download a city**
1. Settings → OFFLINE MAPS → pick a city → Download.
- Expected: progress, then the size. **Stop** pauses a download.

**TC-OFF-02 · Use offline**
1. Airplane mode → open the Map over that city.
- Expected: the map tiles show.

**TC-OFF-03 · Delete**
1. Delete the pack.
- Expected: the space is freed.

**TC-OFF-04 · Space limit**
1. Download until full.
- Expected: "Offline maps are using all their space. Delete a city first."

**TC-OFF-05 · No key (build A)**
- Expected: offline maps say they aren't available, with no crash.

---

## 42. AR guide and Identify (Lens)

**TC-AR-01 · AR guide**
1. Within 2 km of a place: ⋮ → Point me there (AR).
- Expected: the camera view with an arrow, the distance and the turn direction. Turning the phone moves the arrow.

**TC-AR-02 · AR idle**
1. Leave AR untouched for 90 s.
- Expected: it closes by itself to save battery.

**TC-LENS-01 · Identify**
1. Build B: ⋮ → Identify what's here → take a photo of a landmark.
- Expected: a description of what it is.

**TC-LENS-02 · Daily limit**
1. Use it more than 30 times in a day.
- Expected: a friendly message that the limit has been reached.

---

## 43. Ecosystem (hidden)

**TC-ECO-01 · Hidden in v1**
- Expected: no Ecosystem entry anywhere in the app (the flag is off).

**TC-ECO-02 · With the flag on (dev build)**
- Expected: every screen shows the "sample data" banner.

---

## 44. Accessibility

**TC-A11Y-01 · TalkBack / VoiceOver tour**
1. Turn on TalkBack and swipe through:
   - Explore
   - a place sheet
   - Map (pins)
   - the itinerary
   - You
   - Friends
   - the camera
- Expected: every button says what it does, for example:
  - "Take photo"
  - "Start recording"
  - "Stop 2, Kashi Vishwanath, Morning, next"
  - "Photo by Asha, 18 Nov"

  No button is read only as "button".

**TC-A11Y-02 · Recording by screen reader**
1. With TalkBack on, double-tap and hold the camera button.
- Expected: recording starts or stops (the long-press action).

**TC-A11Y-03 · Large text**
1. Set the largest font size, then visit the same screens.
- Expected: nothing is cut off or overlapping. Buttons and chips wrap.

**TC-A11Y-04 · Small screen**
1. On a 320–360 dp wide phone at 1.3× text.
- Expected: no overflow stripes and no clipped buttons.

**TC-A11Y-05 · Reduce motion**
1. Turn on "Remove animations".
- Expected: the rank bar, the recording dot and the fades don't animate.

**TC-A11Y-06 · Contrast**
1. Use the app outdoors in sunlight.
- Expected: text is readable, and status is never shown by colour alone (labels such as "Waiting" or "Failed").

---

## 45. Tablets and landscape

**TC-TAB-01 · Side rail**
1. Open on a tablet, or a phone in landscape 600 dp or wider.
- Expected: tabs on the left. Pages are no wider than a comfortable reading width; the Map uses the full width.

**TC-TAB-02 · Rotate**
1. Rotate during a trip, the camera and the planner.
- Expected: no reset or loss of state. The camera preview fills the screen.

---

## 46. No signal and bad connections

**TC-NET-01 · Start offline**
1. Airplane mode, then open the app.
- Expected: it opens. Saved trips, memories and the journal all work, and network parts show friendly "Try again" messages.

**TC-NET-02 · Lose signal mid-action**
1. Turn off data while:
   - planning a trip
   - posting a memory
   - uploading to the album
   - loading Around you
- Expected: no crash, a clear message, and a retry or automatic retry (the album).

**TC-NET-03 · Slow network**
1. Use a very slow connection (developer settings).
- Expected: loading states (skeletons or progress), not frozen screens.

**TC-NET-04 · Server asleep (Render free tier)**
1. Open Shared by others after an hour of no use.
- Expected: the first load may be slow but finishes, or offers Try again.

---

## 47. Updating from an older version

**TC-UPG-01 · Keep data after updating**
1. Install the previous release and create trips, memories, a journal trip and wishlist items.
2. Install this build over it (don't uninstall).
- Expected: everything is still there. The album and slow-mo work (the database upgrades to version 11 on its own).

**TC-UPG-02 · Old memories**
- Expected: old videos play at normal speed, and old photos open.

**TC-UPG-03 · Signed in stays signed in**
- Expected: no sign-in required after the update.
