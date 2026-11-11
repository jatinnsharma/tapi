# Tasks: Taking the App from Chandigarh to All of India

## What the app has today
- **Chandigarh-only lock:** `lib/core/config/service_area.dart` is a single hard-coded circle. These files filter against it:
  - `lib/features/locations/data/location_repository.dart` (line 66)
  - `lib/features/map/map_screen.dart`
  - `lib/features/home/home_screen.dart`
  - `lib/features/locations/presentation/place_sheet.dart` (line 76), which blocks starting a trip outside the circle
- **Nearby places:** `lib/features/locations/data/nearby_places_service.dart` already pulls places from Wikipedia and OpenStreetMap around any point. The seed data (`location_seed.dart`) is Chandigarh-only.
- **AI:** `lib/features/ai/application/ai_places_service.dart` and a Gemini client already exist.
- **Other pieces:** weather, wishlist, groups, accommodation, transport and guides.

## Phase 1: Go all-India (foundation)
1. **Remove the Chandigarh lock.** Replace the `ServiceArea` circle with "the area around wherever the user is, or whichever city they picked". Update the filters in the repository, map, home and place sheet. Drop the "Only in Chandigarh" banner and the trip-start block.
2. **Add an India city catalog.** Build a bundled JSON of about 150 to 300 cities and tourist hubs, each with name, state, latitude, longitude, a one-line blurb and an image. Include Varanasi, Jaipur, Goa, Manali, Rishikesh, Kochi, Leh and so on. It works offline and doubles as the "top nearby cities" source.
3. **Fix the fetch cache.** Key it by city or area instead of one global fetch point, so Varanasi and Jaipur each cache separately.
4. **Make the seed data optional.** Keep the Chandigarh seed as a fallback and fetch everything else live.

## Phase 2: Explore tab
5. **Search bar** for any place or city in India. Use OSM Nominatim for geocoding, plus the local city catalog for instant suggestions.
6. **"Top nearby cities" section.** Find the user's GPS location, sort the catalog by distance, and show city cards with name, km away and a photo.
7. **City detail screen.** Tapping a city opens its places, using the existing Wikipedia and Overpass fetch, with category filter chips (heritage, food, viewpoints and so on). Tapping a place opens the existing place sheet.
8. **"Near you now" section.** Use the current GPS fix, show places within 5 to 25 km sorted by distance, add a radius slider, and handle permission-denied with a manual "pick a city" fallback.
9. **Add "Plan a trip" buttons** on the city detail screen and on search results.

## Phase 3: AI trip planner (e.g. "Varanasi, 5 days, with a childhood friend")
10. **Trip planner form.** Ask for destination, number of days, who's going (solo, friends, couple, family) and the type of trip.
    - Optional: budget, interests (spiritual, food, adventure), pace (relaxed or packed), start date and where they're travelling from.
11. **Itinerary generation.** Send the form to Gemini with a strict JSON schema, then validate and repair the output. Each day gets morning, afternoon and evening blocks with:
    - the place
    - estimated time to spend there
    
    - travel time between stops
    - a food suggestion
    - a short tip
12. **Ground the AI in real data.** Feed it the real places fetched for that city so it doesn't invent places, and geocode each stop so it can be shown on the map.
13. **Itinerary screen.**
    - Day tabs.
    - A route map per day, using the existing `directions_service.dart`.
    - Reorder and delete stops.
    - A "regenerate this day" button.
14. **Save trips** to the local DB and Firestore. Add a "My Trips" list that works offline.
15. **Friend/group trips.** Share a trip with the friend you're travelling with, using the existing groups and friends features, and let both edit it.
16. **Extras for each trip:**
    - Weather for the travel dates (weather already exists).
    - Hotels via the accommodation screen.
    - Train, bus and flight links via the transport screen.
    - A packing checklist.
    - A budget estimate.
    - A share-as-PDF or share-as-image option.
17. **Link trips to tracking.** "Start today's plan" begins a tracked adventure, so XP, streaks and the journal keep working across India.

## Phase 4: Polish
18. **Offline caching** of city places and saved itineraries.
19. **Hindi and regional language support** for AI output and the UI.
20. **Safety and local tips:** best season to visit, local etiquette, and emergency numbers.
21. **API key and cost guards.** Rate-limit Gemini calls, cache itineraries by city, days and interests, and keep a non-AI fallback that builds a simple plan from the top-rated places.

## Suggested build order
Tasks 1–4 first, then 5–8, then 10–14. Tasks 15–21 can come after.

## Status (2026-10-17)
Tasks 1–21 are built in code. Phase 3's gaps (AI output repair and grounding, real day routes, stop-by-stop tracking) were closed on 2026-10-17. What still needs doing outside the code:
- **Publish the Firestore rules** (`firebase deploy --only firestore:rules`). Trip backup and sharing (tasks 14–15) use the new `trip_plans` rule. Until it's live, trips stay on the phone and sharing shows an error.
- **Test on a phone with two accounts:** share a trip, edit it on both phones, then delete or leave it.

Known limits:
- If two people edit a shared trip at the same moment, the last save wins.
- The owner can add any uid as a member. The rule doesn't check that they are friends.
- Weather is shown only within 16 days of the trip. Before that, the app shows a season note instead.
- Sharing is text or image. PDF was skipped because the PDF fonts can't render Hindi itineraries.
- A stop counts as done only when its arrival is confirmed with the live photo, the same rule as any place. "Mark done" is the manual override.
- Hindi place names rarely match the English place list, so Hindi itineraries rely more on geocoding and the AI's coordinates.
- Day routes use the free FOSSGIS car router. Offline, the map falls back to dotted straight lines and the AI's travel-time text.

## Open questions
- Is a Gemini API key already configured?
- Should itineraries be fully AI-generated, or built by a rules engine over fetched places? Recommended: AI on top of real places, with the rules-based plan as the fallback.
