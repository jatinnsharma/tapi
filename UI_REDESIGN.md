# Tabi: UI audit and premium redesign plan

Snapshot of the code on 2026-11-17.

This is a review of every screen's code, with one goal: make Tabi feel like a professional, premium app that is easy to use.

- **Part 1** gives the verdict and the plan: the design system, the navigation and how to roll it out.
- **Part 2** goes screen by screen: what renders today, its problems with `file:line` references, and a redesign target for each screen.

## Contents

**Part 1: Verdict and plan**
1. [Verdict](#1-verdict)
2. [What holds the UI back](#2-what-holds-the-ui-back)
3. [Design principles for the redesign](#3-design-principles-for-the-redesign)
4. [New navigation and information architecture](#4-new-navigation-and-information-architecture)
5. [Design system v2](#5-design-system-v2)
6. [Blueprints for the key screens](#6-blueprints-for-the-key-screens)
7. [Copy and tone](#7-copy-and-tone)
8. [Quality bar: accessibility, states, motion](#8-quality-bar-accessibility-states-motion)
9. [Roadmap](#9-roadmap)

**Part 2: Screen-by-screen audit**
- [A. Design system, shell, first run, Home, settings](#ui-audit-a-shell-first-run-home-settings-type-screens)
- [B. Discovery: city, place sheet, map, place tools](#ui-audit-b-discovery-screens-city-detail-place-sheet-map-tab-place-tools)
- [C. Trips: planner, itinerary, live trip, trip art](#ui-audit-c-trip-planning-live-trips-trip-art)
- [D. Passport, gamification, journal, memories](#ui-audit-d-passport-tab-gamification-journal-memories)
- [E. Social, groups, leaderboard, ecosystem](#ui-audit-e-social-tab-groups-leaderboard-feed-footprint-ecosystem)

**How this was made.** Five reviews read every presentation file, about 80 files, plus the theme and components. The headline claims were then re-checked in the code: the wrong XP numbers, the invisible pills, the level/rank mismatch and the login screen with no way out. One screen could not be reviewed. `lib/features/tracking/presentation/navigation_view.dart`, the turn-by-turn trip screen, is temporarily empty, so its review waits until it is restored.

---

# Part 1: Verdict and plan

## 1. Verdict

Tabi has more features than most travel apps. The UI does not make them feel premium or simple yet. The problems are not a lack of polish on single screens. They come from four systemic issues:

1. **There is no real design system.** The brand colours are not wired into Material's `ColorScheme`, so standard widgets draw generic greens. The code uses 31 different font sizes, about 28 of them below 12 sp. There are 366 raw `Colors.*` values, 19 different corner radii, a different glow shadow on every component, and about 4 ways to draw a primary button. Every screen therefore looks slightly different, and everything floats at the same height, so nothing reads as the primary element.
2. **Screens try to do everything at once.**
   - Home stacks up to 11 blocks, and the core action (start exploring) is below the fold.
   - The Social tab holds 9 sections, including sign-out and delete account.
   - The Passport tab shows 7 separate progress systems.
   - The place sheet puts trip rules before the place description and the Start button 700 px down.
3. **Hard things are hidden and easy things are noisy.**
   - Key features hide behind unlabeled 42–46 px icons: 4 on the Map, 4 on Social and 3 on the Home header.
   - Destructive actions (unfriend, delete group, discard trip, remove stop) happen on one tap with no confirmation or undo.
   - The live trip screen, which people read while walking, has 12.5 sp time and 15 px status pills.
4. **The app talks to users like a developer or a game.** It shows raw exception text in more than 25 places, developer instructions such as "See PENDING_TASKS.md" and "Add GEMINI_API_KEY", emoji, exclamation copy, jargon ("trek", "journey"), and in-app XP rules that contradict the real ones.

The good news is that the structure is sound. It uses Riverpod and go_router, there are a few decent shared components (`EmptyStateCard`, `SectionHeader`, `Shimmer`, `FadeSlideIn`), and the brand palette is pleasant. A redesign can stay incremental: build the system first, then re-skin screen by screen, with no rewrite.

## 2. What holds the UI back

Each issue below is verified in the code. Details and line numbers are in Part 2.

| # | Issue | Evidence | Effect on users |
|---|---|---|---|
| 1 | Brand colours outside `ColorScheme`; no semantic colours | `app_theme.dart:81` seeds from `Colors.green`; red, orange and blue used raw | Switches, chips and progress bars look off-brand. Warnings and rewards share amber. |
| 2 | No type scale | 31 font sizes, 369 inline `fontSize:`; `textTheme` used once in features | Uneven rhythm, tiny labels, a "busy" look |
| 3 | Shadows, gradients and glass on everything | Each component has its own glow (`components.dart`, `glass.dart`); gradient page wash; `GlassCard` blur over a smooth gradient is invisible but costs GPU | Template look; no visual hierarchy; slow on low-end phones |
| 4 | Overloaded screens | Home has up to 11 blocks; Social has 9 sections and 6 dialogs; Passport has 7 progress systems | Users don't know where to look or what to do next |
| 5 | Primary action not obvious or not reachable | Place sheet Start below about 700 px (`place_sheet.dart:313`); planner Generate below 10 inputs; Home Start second to last | More taps and scrolling; lower conversion to the core loop |
| 6 | Icon-only, under-sized controls | `RoundIconButton` 46 px; Map has 4 unlabeled actions; Social header has 4; itinerary reorder targets about 18 px | Hidden features; mis-taps; fails the 48 px guideline |
| 7 | Same object, different UI | Three different place sheets (place, map marker, food); three share implementations; six person-row variants; six pill variants | Feels unfinished; users relearn each screen |
| 8 | Destructive actions without confirmation or undo | Unfriend, cancel request, delete group, cancel adventure, discard trip, remove stop, delete contact | Data loss by accident; anxiety |
| 9 | Developer copy and raw errors | "See PENDING_TASKS.md", "Add GEMINI_API_KEY", `'$error'` in more than 25 places | Looks broken and untrustworthy |
| 10 | Wrong rules shown to users | In-app XP help says 3 min, 150 m and 500 XP/day; the code uses 2 min, 100 m and 1,500 XP (`trip_not_counted_checklist.dart:57-76` vs `TripGuard`, `TrackingService`) | Users are told the wrong rules for what counts |
| 11 | Incoherent gamification | "Level 11 · Explorer" while the tier table says Explorer is level 5 (`explorer_level.dart:14` vs `:39-41`); XP shown 3–4 times; bar resets every 100 XP | No mental model of progress |
| 12 | Invisible or low-contrast text | `MetaPill` default is white on 16 % white, used on light surfaces (`city_detail_screen.dart:234,236,461`); amber icons on white about 2:1; orange text about 2.2:1 | Unreadable labels; accessibility failures |
| 13 | Navigation quirks | Zoom transition on iOS removes back-swipe (`app_theme.dart:130`); login has no back or close; 16+ imperative `Navigator.push` to screens without routes | Users get stuck; no deep links; inconsistent back |
| 14 | Settings scattered, no account hub | Safety, Preferences and Wishlist sit in the Home header; sign-out and delete account sit inside Social | Hard to find; the Home header overflows on 360 dp |
| 15 | Live trip screen not glanceable | No map; elapsed time in a 12.5 sp chip; status in a 15 px pill; empty "Checkpoints" always shown; Discard red and the same size as Finish with no confirm | Unsafe and confusing while walking |

## 3. Design principles for the redesign

1. **One screen, one job, one primary button.** Every screen gets a single obvious primary action, sticky at the bottom when the content scrolls. Everything else is secondary or goes in an overflow menu.
2. **Calm surfaces, colour with meaning.** Use neutral backgrounds and white cards. Brand green is for primary actions and selection. Amber is only for rewards. Red, amber, green and blue are only for status. Gradients appear only on hero imagery.
3. **Content first.** Photos and maps run edge to edge with small radii. No decorative mountain silhouettes, pastel icon circles or white borders around images.
4. **Progressive disclosure.** Rules, XP mechanics and settings live in help sheets and settings, not in the flow. Show one line of XP near the action, never three.
5. **Glanceable on the move.** The in-trip UI uses large numbers, one status line and at most two controls. Everything else waits until the trip ends.
6. **Forgiving.** Every destructive action has a confirmation or an undo. Every error has a friendly message and a retry. Every gated feature explains how to unlock it, with a button.
7. **Consistent.** The same object always looks and behaves the same: a place, a person, a trip, a pill, a list row, a sheet.
8. **Accessible by default.** Targets of 48 px or more, AA contrast, text of 12 sp or more, screen-reader labels, reduced-motion respected, dark mode.

## 4. New navigation and information architecture

**Today** there are 4 tabs (Explore, Map, Social, Passport). Trips have no home: the planner is a Home quick action and My Trips is a link. Settings are split between the Home header and the Social tab.

**Proposed:** 5 tabs, plus a global active-trip bar.

| Tab | Purpose | Contains (moved from) |
|---|---|---|
| **Explore** | Discover and start | Search, "Now" card (state-aware: active trip, trip today, upcoming trip, or "Start exploring" with the daily challenge), Around you, Destinations. *Removes* the quick-actions row, the big headline, duplicate weather and the header icons. |
| **Map** | See and go | Full-screen map with a single **Layers** button (mode, food, capsules, legend) and a single primary FAB (**Start here**). Moves AI discover and Record capsule into the layers or more sheet. |
| **Trips** *(new)* | Plan and follow | My Trips (upcoming, today, past), **Plan a trip** primary button, itinerary, essentials. Moves the planner and My Trips here from Home. |
| **Friends** *(was Social)* | People | Friends list (real list plus search, not "first 100 explorers"), requests, groups, group adventures, leaderboard, feed, as **labelled segments**. *Removes* account settings, map privacy, blocked and muted lists (moved to You → Settings). |
| **You** *(was Passport)* | Me and progress | Profile hero with **one RankMeter**, a Collections row (achievements, stamps, regions, streak), Journal and Calendar, Memories, exploration map and poster, and **Settings** (Account, Privacy, Preferences, Reminders, Safety, Offline maps, Wishlist, About). |

**Global elements**
- **ActiveAdventureBar:** while a trip runs, a slim bar above the tab bar on every tab shows time, distance and status, with **Resume** and **SOS**. It solves the duplicate Resume on Home, cross-tab resume, and SOS reachability.
- **Routes for everything.** Every pushed screen gets a go_router route (itinerary, memory viewer, stamp detail, tour, lens, AR, poster, trip summary). That gives predictable back behaviour, deep links and one shared page transition (Cupertino on iOS, fade-through on Android).
- **Sheets over dialogs.** Forms and multi-step flows use `FormSheet` or full-screen routes. Dialogs are only for destructive confirmation.

## 5. Design system v2

All tokens live in `lib/core/theme/` as a `ColorScheme` plus `ThemeExtension`s, so feature code never uses raw `Colors.*`, `fontSize:` or `circular(n)`. Add a custom lint or a CI `grep` check that fails on new raw values in `lib/features`.

### 5.1 Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `brand` (`primary`) | `#1F6F4A` | `#5FC79A` | Primary buttons, selection, links |
| `brandContainer` | `#DCEFE4` | `#123D2B` | Selected chips, tonal buttons |
| `bg` | `#F6F7F5` | `#0E1311` | Page background (flat, no gradient) |
| `surface` | `#FFFFFF` | `#161C19` | Cards, sheets |
| `surfaceRaised` | `#FFFFFF` + shadow 1 | `#1D2420` | The one floating layer (sheets, FAB, sticky bars) |
| `textPrimary` / `textSecondary` / `textDisabled` | `#14201A` / `#56635B` / `#9AA59F` | `#E9EEEB` / `#A9B4AE` / `#66716B` | Text |
| `reward` | `#C97A00` (text), `#F5A623` (fill) | `#F5B547` | XP, stars, stamps only |
| `success` / `warning` / `danger` / `info` | `#1E7F4F` / `#B26A00` / `#C62828` / `#2563EB` | lighter tones | Status, banners, destructive actions |
| `categoryStyle[c]` | One colour and one icon per place category | same | Map pins, place tags, placeholders (replaces the two disagreeing maps) |

All text colours must meet WCAG AA (4.5:1 body, 3:1 large text and icons) on their surfaces. The current emerald focus border and amber icons on white fail this.

### 5.2 Typography

- **One family, bundled:** **Inter** (variable) for UI, with **Noto Sans Devanagari** in `fontFamilyFallback`, because AI itineraries can be in Hindi. Bundle the fonts (not `google_fonts` at runtime) so they work offline.
- **Scale (sp):**

  | Role | Size | Weight |
  |---|---|---|
  | display | 32 | 700 |
  | headline | 24 | 700 |
  | title | 20 | 600 |
  | titleSmall | 17 | 600 |
  | body | 16 | 400 |
  | bodySmall | 14 | 400 |
  | label | 13 | 600 |
  | caption | 12 | 500 |

  Nothing goes below 12. The 800/900 weights are retired; calm weights read as premium.
- Use tabular figures (`FontFeature.tabularFigures()`) for live stats, distances and times.
- Respect text scaling up to 1.3×. Layouts must not use fixed heights for text blocks.

### 5.3 Space, radius, elevation, motion

- **Spacing:** 4-pt scale 4/8/12/16/24/32/48. Page gutter 16 on phones, 24 on tablets, with a max content width of 720 for reading screens.
- **Radius:** `sm 8` (chips, small images), `md 12` (cards, inputs), `lg 20` (sheets, hero media), `pill`. Four values replace the current 19.
- **Elevation:** level 0 (flat, separated by colour and space) for almost everything. Level 1 (soft shadow) only for the single floating layer: sheets, FAB, sticky action bars, the tab bar. No coloured glows.
- **Motion:** `fast 150 ms`, `base 250 ms`, `slow 400 ms`, using standard M3 easing. Use Hero transitions for place photos, memories and stamps, and a shared-axis transition for tabs and segments. Every animation checks `MediaQuery.disableAnimations`. Shimmer is used only on first load, never as an infinite decoration.
- **Iconography:** Material Symbols **Rounded**, one weight (400) and one optical size, used everywhere. No emoji in the UI.

### 5.4 Components to build (and what they replace)

| Component | Replaces | Notes |
|---|---|---|
| `AppButton.primary/secondary/tertiary/danger` | 4 primary styles, ~15 `ElevatedButton`, per-call `styleFrom`, `AmberPillButton`, `GlowButton` (delete) | 48 px min height, loading state, optional icon |
| `AppIconButton` | `RoundIconButton` (46 px), bare `IconButton`s with `BoxConstraints()` | 48 px target, tooltip required |
| `LabeledIconAction` | Unlabelled header icons (Social, Map, Group adventures) | Icon with a visible label |
| `StickyActionBar` / `SheetActionBar` | CTAs at the end of long scrolls | Place sheet, tour, lens, planner, itinerary |
| `AppSheet` / `FormSheet` | Hand-made sheets and AlertDialog forms | Handle, title, close, keyboard insets, sticky primary |
| `PlaceSheetScaffold` | 3 divergent place sheets | Gallery, title, meta row, body slots, sticky actions |
| `AppListTile`, `SettingsTile`, `PersonTile`, `TripListTile` | 6 person rows, many hand-built "icon tile + title + chevron" rows | One leading/title/subtitle/trailing model |
| `Tag` (neutral, brand, reward, onImage) | `MetaPill`, `_Label`, `_DarkPill`, XP pill, "All India" tag, distance pill | Explicit tone; never invisible |
| `StatusBanner` (info, warning, error, success, offline) and `StatusBadge` | Hand-rolled banners; emoji and colour-only status | Icon + text + token colour |
| `ErrorState`, `EmptyState`, `GateCard`, `SignInPrompt` | `'$error'` text, dead-end signed-out cards, developer copy | Friendly copy, retry, a real unlock action |
| `confirmDestructive()` + undo `SnackBar` | One-tap destructive actions | Confirmation sheet with a red primary |
| `RankMeter`, `CollectionTile` | 7 competing progress displays | One meter; collections row |
| `MediaShell`, `MemoryThumb` | Light-theme camera; hand-rolled black viewers; video tiles with no thumbnail | Dark media UI; cached thumbnails |
| `MapPin`, `ClusterPin`, `MapLegend` | 7 marker styles with no legend; 34–40 px pins | 44–48 px hit area, clustering, legend |
| `CarouselSection`, `MediaCard` | Two carousels with fixed heights | Intrinsic height, skeletons, "See all" |
| `StopTimelineRow`, `DaySelector`, `LiveStatsPanel`, `HoldToConfirmButton`, `ShareCardSheet` | Dense itinerary cards; live trip chips; 3 share flows | See section 6 |
| `friendlyError(e)`, `AppDate`, `formatRelativeTime` | Raw exceptions; 4 month arrays; 3 relative-time formatters | Shared helpers in `core/` |

## 6. Blueprints for the key screens

Short target layouts. The full reasoning per screen is in Part 2.

**Explore (Home)**
- Compact header: avatar, a tappable location chip ("Varanasi ▾"), and one overflow menu.
- Search field.
- **Now card**, one of: active trip, today's plan stop, upcoming trip countdown, or "Start exploring" with today's challenge and streak.
- **Around you:** filter chips, then a carousel of `MediaCard`s.
- **Destinations:** carousel of cities.

The big headline, the quick-actions row, duplicate weather, the duplicate Resume and the header icons all go (they move to tabs and Settings). The weather advisory becomes one `StatusBanner` inside Around you.

**Place sheet** (one scaffold everywhere)
- Edge-to-edge photo gallery.
- Name, then a meta row (category tag, distance, open now, rating). One subtle "+80 XP" tag.
- Description, then opening hours, then tips (collapsed).
- **Sticky action bar:** **Start** (primary), Save (icon), More (AR guide, What's this?, directions, share).

Trip rules move behind an "How trips count" info link.

**Map**
- Full-screen map with a search pill on top.
- Bottom-right: Locate. Top-right: **Layers** (Exploring / All places / My places / Friends, plus Food, Capsules and the legend).
- Bottom: **Start here** FAB.

Markers become `MapPin`s with clustering. Tapping one opens the shared `PlaceSheetScaffold`. AI discover and Record capsule move into the More menu, and are hidden when not configured, never showing developer copy.

**Live trip**
- Map on top (the route so far plus the destination).
- `LiveStatsPanel`: elapsed time large, then distance and steps.
- One status line in words: "Counting: you're walking" or "On the way (by vehicle)".
- Primary **Finish** (`HoldToConfirmButton`); Pause as secondary; Discard moves to More with a confirmation.
- SOS is always in the app bar.

The empty Checkpoints section goes. The arrival flow becomes one sheet: the camera, then a "You made it" state inside it.

**Itinerary**
- `DaySelector`, then a collapsible day map.
- A timeline of compact `StopTimelineRow`s (time, name, duration, open/closed). Tapping a row opens a stop detail sheet.
- One sticky "Start next stop" button.
- Editing (reorder, remove, regenerate, adjust my day) happens in an **Edit** mode with drag handles and undo.
- Essentials (weather, packing, budget, safety) is a separate tab or route, not a fake day chip.

**Planner**
- Step 1: destination, days, who. **Generate is visible from the start**, with a sticky bottom bar.
- "More options" (pace, budget, interests, language, start date, origin) is collapsed.
- Generation shows progress with a Cancel button, then replaces the form with the itinerary, so Back can't reach the form or create duplicates.

**You (Passport)**
- Hero: avatar with rank frame, name, and a **RankMeter** (tier, bar to the next tier, preview of its reward). A streak chip sits in the hero.
- Collections row: Achievements n/N stars, Stamps n cities, Regions x% (only discovered regions).
- List: Journal, Calendar, Memories, Exploration map.
- Settings entry.

XP appears once, as a currency chip. The per-100-XP "level" is removed or derived from the tiers.

**Friends**
- Segments: **Friends · Groups · Adventures · Leaderboard · Feed**.
- The Friends segment shows requests (with labelled Accept and Decline), then the friends list with search, then "Find explorers".
- Person actions sit in a ⋮ menu (view map, challenge, remove friend with a confirmation).
- Signed-out users see one `SignInPrompt` with a button.

**Camera and memories** (inside `MediaShell`)
- Black UI with a round shutter and flash, flip and grid controls, and a short capture animation.
- Proof mode shows a one-line banner explaining why a live photo is needed.
- The viewer is swipeable full-screen with a Hero transition. Share, delete and info open as sheets, not a permanent panel.
- Gallery: cached thumbnails with a video duration badge, and an extended **Add** FAB.

## 7. Copy and tone

- **Voice:** calm, helpful, plain English. "Start", "Save", "Got it", "Try again". No "Awesome!", "???", 🎉 or 🔥.
- **No jargon in the main flow.** Use "walking" and "on the way" instead of "trek" and "journey". "Profile frame" instead of "Frame + trail colour". "Grid" instead of "AI Photo Assistant". "Not verified: see why" instead of "Not counted".
- **No developer text ever.** Missing configuration shows a `GateCard` ("Sharing isn't available yet") or hides the feature. Errors use `friendlyError()`, with details only in logs.
- **One source of truth for rules.** An `XpRules` object feeds the help sheet, the trip checklist and the start screen, so the copy can't drift from the code again.
- **Dates and numbers:** use `intl` everywhere (relative for up to 7 days, then "12 Apr 2026"). Use metric units with one decimal place under 10 km.

## 8. Quality bar: accessibility, states, motion

Every screen is "done" only when all of these hold:

- [ ] Primary action visible without scrolling, or sticky.
- [ ] Loading (skeleton with fixed height), empty (with an action), error (friendly, with retry), offline, signed-out and permission-denied states all designed.
- [ ] All tap targets 48×48 or larger; every icon button has a tooltip or `Semantics` label.
- [ ] Contrast AA; no meaning carried by colour alone.
- [ ] Works at 320 dp width and at 1.3× text scale; no overflow; tablet layout capped at a max width.
- [ ] Destructive actions confirm or offer undo.
- [ ] Motion respects reduced motion; no infinite decorative animation.
- [ ] Dark mode checked.
- [ ] Opens through a named route (deep-linkable); back behaves as the platform expects.
- [ ] Golden test (light and dark, small and large text) for its main states.

## 9. Roadmap

Effort: **S** about 1 day, **M** about 2 to 4 days, **L** about 1 to 2 weeks (one developer).

**Phase 0: bug-level fixes, before any redesign (about 1 week).** These are wrong or broken today, and each is listed with `file:line` in Part 2.

> **Status, 2026-11-17: all 10 done.**
> - Shared helpers added in `lib/core/ui/`: `confirmDestructive`, `showUndoSnackBar`, `friendlyError`, `UserFacingError`.
> - **Correction to the audit:** the "Live photo taken at destination" checklist row does work. Its phrase "confirmation photo" is in the arrival notice in `tracking_service.dart`. Only the numbers were wrong.
> - **Not covered:** Discard got its confirmation, but the live trip screen as a whole still waits for `navigation_view.dart` to be restored.

| # | Fix | Size |
|---|---|---|
| 1 | Make the XP help and the "not counted" checklist read from `TripGuard` and `TrackingService` (2 min, 100 m, 1,500 XP/day), and fix the checklist row that can never show | S |
| 2 | Fix invisible `MetaPill`s on city pages and place cards | S |
| 3 | Fix the level and tier mismatch on Passport | S |
| 4 | Login: add close and back, remove "See PENDING_TASKS.md", add a password show toggle and friendly errors | S |
| 5 | Restore iOS back-swipe (Cupertino transition on iOS) | S |
| 6 | Add confirmation or undo to unfriend, cancel request, delete group, cancel adventure, discard trip, remove stop, delete contact and remove wishlist item | M |
| 7 | Replace raw `'$error'` and developer copy with `friendlyError()` and `GateCard` (about 25 places) | M |
| 8 | Fix the Home header overflow on 360 dp; remove the duplicate Resume | S |
| 9 | Onboarding "Skip" should not trigger the location prompt | S |
| 10 | Chat should not jump to the bottom on every rebuild; use real date and time pickers for group adventures | S |

**Phase 1: design-system foundation (about 2 weeks).**

> **Status, 2026-11-18: done, with two exceptions.**
> - **Tokens and theme:** `AppColors` extension (light and dark), `ColorScheme` from the brand colour, the type scale, `AppRadius`, `AppElevation` and `AppMotion`, plus theme-level styles for buttons, chips, inputs, sheets, dialogs, snackbars and tooltips. These live in `lib/core/theme/app_theme.dart`.
> - **Fonts:** Inter (400–700) with Noto Sans Devanagari, bundled in `assets/fonts`.
> - **Components:** `lib/core/theme/app_components.dart`.
> - **Removed:** `GlowButton` is deleted, `GlassCard` is now a flat surface with no blur, the gradient page wash is gone, and all component glows are removed.
> - **CI:** `tool/check_design_tokens.sh` is a ratchet. Baseline: 518 raw colours and 369 inline font sizes.
> - **Tests:** contrast and type-scale checks in `test/design_system_test.dart`.
> - **Not done: golden tests.** They need fonts loaded in tests and fixed device sizes, so they are deferred to Phase 3.
> - **Not done: dark mode is defined but not switched on,** until screens stop using raw colours.
- Tokens: `ColorScheme` plus extensions, type scale and bundled fonts, radius, elevation, motion, and the dark theme.
- Components: `AppButton`, `AppIconButton`, `Tag`, `AppListTile` and its family, `StatusBanner`/`StatusBadge`, `AppSheet`/`FormSheet`, `ErrorState`/`EmptyState`/`GateCard`/`SignInPrompt`, `confirmDestructive`.
- Delete `GlowButton`, retire `GlassCard`, and remove the gradient page wash.
- Add the CI check against raw colours and font sizes, plus golden tests for the components.

**Phase 2: navigation and shell (about 1 week).**

> **Status, 2026-11-18: done, with routes still to convert.**
> - **Tabs:** five tabs, Explore, Map, **Trips** (`/trips`), **Friends** (`/social`) and **You** (`/passport`).
> - **Trip bar:** `ActiveAdventureBar` shows on every tab with Open or Resume plus SOS. It replaces the Home "continue" card.
> - **Settings:** `/settings` holds account (sign in, sign out with confirm, delete account), preferences and reminders, safety, wishlist, offline maps, privacy and open-source licences (including the fonts). Account actions moved out of the Friends tab, and the You tab header has a Settings gear.
> - **Trip routes:** trips open at `/trips/:tripId?day=N`. The old `/my-trips` redirects. After generating, the planner replaces itself with the trip.
> - **Still to convert to routes in Phase 3:** the memory viewer, stamp detail, tour detail, lens, AR, poster and trip summary.
> - **Not done: privacy settings** (map visibility, blocked and muted people) still live in Friends, and Settings links there.
- 5-tab shell (Explore, Map, Trips, Friends, You).
- `ActiveAdventureBar` with SOS.
- You → Settings hub (Account, Privacy, Preferences, Reminders, Safety, Offline maps, Wishlist).
- Routes for every pushed screen, with one page transition.

**Phase 3: core flows (about 3–4 weeks).** In order of user impact:
1. Explore (Home)
2. Place sheet and Map: `PlaceSheetScaffold`, `MapPin`, Layers
3. Live trip (after `navigation_view.dart` is restored)
4. Planner and itinerary
5. You (Passport): `RankMeter` and Collections
6. Friends

> **Status, 2026-11-18: steps 1, 2, 4, 5 and 6 done; step 3 (live trip) blocked on the `navigation_view.dart` restore.**
> - **Home:** one "Now" card (your trip today, upcoming or being planned, else "Explore around you" with Start exploring / Plan a trip), then the daily challenge, Around you, Destinations and the AI pick. The big headline, the quick-actions row and the separate hero are gone. The location line is a button that opens the city picker. Journal, Memories and Calendar moved to a "Your trips & photos" list on You.
> - **Place sheet:** one sheet everywhere (Home, City, Wishlist, search, Map). It drags from 70 % to full height, and has a sticky bar: "Start trip" ("Start the hunt" for a mystery), a bookmark, and More (AR "Point me there" only within 2 km, "Identify what's here"). XP is one line above the button. The order is photos, title, at most 2 tags, distance and walk time, description (3 lines + More), Getting there, then tips. The trek rule moved behind an info button ("How trips are counted"). Tips sit in the sheet, and signed out they offer a Sign in button. Places still under the fog open as "Unknown place" with "Head that way", with no name, photos, XP or saving.
> - **Map:** the title "Map" and one **Layers** button (with a dot when not on defaults). The Layers sheet has the view (Nearby / Everything / Mine / Friends, each explained), Places to eat, Suggest more places (only when AI is set up) and a pin legend. Pins are `MapPin`s (44 px, halo, screen-reader label). The mode pill and the map's own place sheet are gone. A "Location is off" banner with Turn on replaces the silent fallback. The voice-note button sits above Locate, and is hidden unless signed in with a memories server.
> - **Food sheet:** "Go there" always works (a tracked trip), with "Open now / Closed now" and today's hours in words. "Add to today's plan" is the secondary action when a trip is on.
> - **Not done here:** marker clustering, a muted MapTiler map style, and merging the two category colour maps into one `CategoryStyle`. The voice-note recorder flow and the AR and Lens screens still have their own issues from the audit.
> - Token ratchet: 517 → 500 raw colours, 367 → 344 inline font sizes.
>
> **Step 4 (planner and itinerary): done, 2026-11-18.**
> - **Planner:** titled "Plan a trip". The form asks only Where to? (with "Choose from popular cities"), How many days? (a 1–10 stepper), When? (optional) and Who's going? Pace, budget, interests, origin and language sit under a collapsed "Tailor it" with a one-line summary. Each choice group shows the selected option's description. **Plan my trip** is fixed at the bottom and disabled until there's a destination. Planning shows a full-screen progress view with staged messages and **Cancel**; Back also cancels, and a cancelled result is never saved. Errors use a `StatusBanner` with Try again. The marketing hero card and the Safety button are gone (Safety moved to the itinerary's More menu).
> - **Itinerary:** a "Saved on this phone / Backed up" line replaces the fake bookmark button. A **Plan | Essentials** switch replaces the fake Essentials day chip, and day chips show dates. The day map no longer pans while you scroll, and has a full-screen button. Stops are compact rows (number badge, name, time slot and duration, "Closed that day" / "May be closed then"); tapping one opens a sheet with photos, hours, description, tip, Mark done, Move earlier/later, Remove (with Undo) and "Go here · +XP". The only main action is the sticky "Go to stop N", with the XP on a line above. Adjust day, Replan day (now with Undo) and Safety are in More. Share opens a sheet (text, image, publish as tour). The closed-stop and tip banners are `StatusBanner`s. An empty day shows "Plan this day" instead of a dead button.
> - **My Trips:** grouped into Happening now / Upcoming / Not dated yet / Past (`planner/domain/trip_groups.dart`). Each `TripCard` shows dates, days, companion, shared status and a progress bar; delete or leave is in a ⋮ menu with `confirmDestructive`. The empty state carries the only CTA (no FAB); errors use `ErrorState`.
> - **Adjust my day:** opens at once and finds your location inside the sheet. Kept stops use the same `StopNumberBadge` as the itinerary and map, and **Apply new plan** is sticky.
> - **Essentials:** "Add dates" is the main action when a trip has no dates. Forecast tiles grow with the text size. Packing rows are full height. The empty friend picker links to Friends. All inline font sizes are gone.
> - **Shared pieces:** `StopHours` lets its chips wrap under the hours instead of truncating them, and uses status tokens. The map credit is our own small "© OpenStreetMap contributors" that shrinks with the map. The trip image uses icons instead of emoji.
> - **Not done:** merging the traveller count into "Travelling together", reordering by drag, a fixed-width share image, and restyling the Home trip card (`trip_home_card.dart`).
> - Token ratchet: 500 → 478 raw colours, 344 → 278 inline font sizes.
>
> **Step 5 (You): done, 2026-11-18.**
> - Title "You" with one Settings button. The hero has the avatar in its rank frame, name, "Explorer · Level 5", the streak badge, and **one meter**: total XP, a bar to the next rank and "1,260 XP to Adventurer" (`ExplorerLevel.rankProgress`). The bar respects reduced motion. "Rank & styles" opens a sheet with every frame previewed with your own initial, locked ones at full contrast with "Unlocks at N XP" (the card left Achievements).
> - Three stats in one card: Trips · km On foot · Places visited ("Total XP" is gone).
> - Collections: three `CollectionTile`s (Stars with a Claim badge, City stamps, Map: routes & poster).
> - Exploration: only your most-explored city, with "All regions" opening `/regions` (grouped, places not started hidden behind a switch). A new explorer sees one line instead of about 24 bars at 0%.
> - Recent trips: three rows that open `/journal/:id` (the route, not a pushed page), dated "3 days ago" for a week and then "2 Jul".
> - Achievements: the reward dialog's button says "Continue".
> - **Not done:** grouping achievements into Ready / In progress / Completed with "Claim all", and a reduced-motion reward animation.
>
> **Step 6 (Friends): done, 2026-11-18.**
> - Title "Friends" and labelled shortcuts (Groups · Meetups · Leaderboard · Feed) that wrap instead of four look-alike icons.
> - Requests come first, with real names (profiles are fetched when they're not among the first 100 explorers) and labelled Accept and Decline buttons.
> - "Your friends (n)" is its own list; tapping a friend opens their map. "Find explorers" has a name search and lists everyone else.
> - `PersonTile` rows: one action (Add, or Requested, which asks before cancelling) and a ⋮ menu (View map and Remove friend for friends; Mute, Block, Report). Blocking asks with `confirmDestructive`.
> - Map visibility and the blocked and muted lists moved to **Settings → Privacy** (`/settings/privacy`); the Account link left Friends.
> - Signed out: one `SignInPrompt` ("add friends, join groups and see the leaderboard").
> - **Not done:** the edit-profile dialog (still a dialog with no error message on save), a tappable "Friends live now", groups, meetups, leaderboard and feed screens themselves.
> - The ratchet no longer counts `AppColors.of` as a raw `Colors.` use (its pattern matched it). Now 439 raw colours, 252 inline font sizes.

**Phase 4: media and polish (about 2 weeks).**
- `MediaShell` for the camera, viewers and voice recorder, plus Hero transitions and thumbnails.
- Share card unification.
- Tablet layouts.
- Final accessibility pass with TalkBack and VoiceOver.
- Hindi UI strings: the app is English-only today, so this needs `flutter_localizations` and ARB files.

> **Status, 2026-11-18: done except Hindi.**
> - **Media shell** (`core/theme/media_shell.dart`): black, edge-to-edge chrome with scrimmed top and bottom bars, white controls and a white primary button, used by the camera, the review screen and both memory viewers. `ShutterButton` is the round 76 dp shutter.
> - **Camera:** full-bleed preview; top bar with close, flash (back camera) and a labelled "Grid" toggle; bottom row with gallery, shutter and flip in three equal slots; haptic and a white flash on capture. Proof mode shows "Verification photo · location on" with a "Why a live photo?" sheet. Loading and errors stay on the black shell with a close button, and a blocked camera offers **Open settings**. The duplicate `PhotoReviewScreen` is gone: the camera uses `MediaReviewScreen`.
> - **Viewer:** full screen with the date as title; tap hides the controls; Hero from the grid. Bottom bar: **Share** (phone share sheet), **Post** (friends or everyone, caption, stop sharing, in a sheet) and **Delete** (confirmed). Posts use your display name, not your email. Someone else's post has **Report** in ⋮. Local files that are missing say so instead of "check your connection".
> - **Gallery:** flat 2 px-gutter grid (`MemoryThumb`) with thumbnails decoded at tile size, fade-in, broken-file fallback, video tiles with play and length, shared badge and screen-reader labels; an **Add memory** button (and in the empty state); All / Photos & videos / Voice notes filters. Voice notes show date and length, and their play button has a label. Community tiles are flat with Hero and labels.
> - **Voice notes:** messages and the "Open settings" for the microphone appear in the sheet (not a hidden snackbar); recordings stop at 3:00; a pulsing red dot while recording; after recording, play back, **Delete** or **Save note**. Errors are caught.
> - **Share card** (`core/ui/share_card.dart`): one sheet for the itinerary and trip summary (fixed 360 dp layout exported at 1080 px, **Share image** and **Copy text**); the poster uses the same renderer. Long trips show three days and "+N more days"; the summary text has no emoji.
> - **Tablets:** from 600 dp the tabs move to a `NavigationRail`, and every tab except Map is capped at 720 dp. The stamps grid adapts its columns.
> - **Accessibility:** automated checks (48 dp targets, labelled controls, text contrast) on the place sheet, planner, itinerary, You, Friends, camera and tablet rail, plus a 320 dp / 1.3× text test on five screens. They found and fixed three overflows (itinerary sync line, Friends challenges header, explorer rows).
> - **Not done:** real video thumbnails (needs a package such as `video_thumbnail`), pinch zoom and tap-to-focus in the camera, swiping between memories in the viewer, a hands-on TalkBack / VoiceOver run on devices, and **Hindi** (needs a decision: see below).
> - Token ratchet: 439 → 402 raw colours, 252 → 240 inline font sizes.

**How to know it worked:**
- Time to first adventure from a fresh install: aim for under 60 s.
- Taps from Home to starting a place: aim for 2.
- Crash-free and ANR rates stay the same or improve.
- Zero raw colours or font sizes in `lib/features`.
- 100 % of screens pass the checklist in section 8.
- An app-store screenshot review against 2–3 premium references (for example Airbnb, AllTrails and Google Travel) shows a consistent visual language.

---

# Part 2: Screen-by-screen audit

Each section below covers one group of screens. Every screen lists its job, layout, states, what works, problems (severity **H**/**M**/**L** with `file:line`) and a redesign recommendation. Each group ends with its shared patterns and quick wins. Paths are relative to the repo root unless a section says otherwise.

## UI audit A: shell, first run, Home, settings-type screens

Reviewer scope: theme/components/glass, MainLayout + main.dart, Onboarding, Login, Home (Explore tab) and its widgets, Preferences, Safety/SOS, Wishlist. All paths are relative to `/home/cts/wrk/time-tracker-t`. Every file in scope was read in full.

---

### Design system

**Tokens**
- **Brand colours sit outside the `ColorScheme`.** The scheme is `fromSeed(Colors.green)` with only `primary` and `surface` overridden (`lib/core/theme/app_theme.dart:81-84`). Every M3 widget that reads the scheme (Switch, ChoiceChip, `FilledButton.tonal`, ProgressIndicator track, ListTile) therefore paints in generic seed greens. Example: the helpline call buttons use the seed `secondaryContainer` (`lib/features/safety/presentation/safety_screen.dart:111`). **H**
- **No semantic colours.** There is no danger, warning, success or info token:
  - Red is raw `Colors.red.*` (`login_screen.dart:169,369,375`, `sos_button.dart:91,101,203`, `ai_recommendation_card.dart:134`).
  - Amber does double duty as "reward/XP" (`daily_challenge_card.dart:68`) and "weather warning" (`weather_advisory_banner.dart:43`).
  - Orange and blue appear off-palette (`streak_flame_badge.dart:28,81,160,194`). **H**
- **Typography has no type scale.**
  - No custom font (`app_theme.dart:86`). Only 6 text styles are overridden (`app_theme.dart:87-114`), and `textTheme` is referenced once in all of `lib/features` (`home_screen.dart:160`).
  - The codebase uses **31 distinct `fontSize` values**. The most common is 12.5 (77 uses). About 28 uses are below 12 sp (7, 8, 8.5, 10.5, 11, 11.5).
  - `components.dart` itself has 14 inline `fontSize`s. **H**
- **Radius tokens are bypassed.** `AppRadius` (`app_theme.dart:18-25`) is referenced 9 times in all of `lib`. The components hard-code 32/24/22/26/30/20/36/18 (`components.dart:116,216,258,398,502,573`; `glass.dart:81,278`). There are 19 distinct `circular()` literals. **M**
- **No shadow/elevation tokens.** Each component invents its own shadow: HeroCard 0.32/30/14 (`components.dart:132-137`), SoftCard 0.10/22/8 (`:522-527`), GlassCard 0.14/26/10 (`glass.dart:118-123`), PlaceCard tinted 0.35 (`:582-587`), AmberPill amber 0.5 glow (`:259-264`), CategoryChip (`:403-409`), NavBar 0.18/30 plus a selected-pill shadow 0.35 (`:969-975,1028-1035`). Everything floats at about the same height, so nothing reads as primary. **M**
- **No motion tokens.** Durations are 160/220/250/260/300/550 ms. Only `FadeSlideIn` respects reduced motion (`glass.dart:241`). `PressableScale`, the infinite `Shimmer` (`components.dart:834`), chip and nav `AnimatedContainer`s and the onboarding pager do not. **L**
- **Page transitions break iOS back-swipe.** `ZoomPageTransitionsBuilder` is used on iOS too (`app_theme.dart:130`). That removes the iOS edge-swipe-back gesture on every pushed route. **H**
- **Light mode only.** `themeMode: ThemeMode.light` (`lib/main.dart:50`). There are no localization delegates and no text-scale clamping.

**Components**
- **Button roles are a free-for-all.** The theme defines Filled, Elevated, Outlined and Text buttons with a radius-16 shape (`app_theme.dart:116-118`). Almost every call site overrides that to `StadiumBorder`: `login_screen.dart:385,425`, `home_screen.dart:502`, `trip_home_card.dart:283,292,482,493`, `ai_recommendation_card.dart:155,171`, `components.dart:798`, `streak_flame_badge.dart:138`. On top of that:
  - `AmberPillButton` is used for the "main action on dark".
  - `GlowButton` (`glass.dart:264`) is dead code with 0 uses.
  - `ElevatedButton` still appears 15 times in features.
  - So a primary CTA is drawn about 4 different ways. **H**
- **Three near-identical white surfaces, with no rule for when to use which.** `SoftCard` (white 0.96), `GlassCard` (white 0.8 to 0.52 with a backdrop blur) and the theme `cardTheme` (white 0.94, unused) differ only slightly.
  - `GlassCard`'s `BackdropFilter` (`glass.dart:128`) blurs a smooth gradient, so the effect is invisible, and it costs GPU time on low-end Android.
  - On Home, GlassCards (challenge, AI) sit between SoftCards and look like random variation. **M**
- **Pills and badges are re-implemented about six times:** `MetaPill`, `_Label` (`trip_home_card.dart:171`), the daily challenge XP pill (`daily_challenge_card.dart:62-79`), `_DarkPill` (`around_you_section.dart:473`), the "All India" tag (`explore_search_bar.dart:83-97`) and the city distance pill (`nearby_cities_section.dart:143-160`). **M**
- **No shared list row or settings tile,** and no status banner. Banners are re-drawn per screen: login error box (`login_screen.dart:366-379`), search `_Notice` (`explore_search_bar.dart:554`), `WeatherAdvisoryBanner`. **M**
- **No sheet scaffold.** The drag handle is drawn by hand twice (`explore_search_bar.dart:333-340`, `city_picker_modal.dart:80-87`). Those two sheets use a 24 radius, against 28 in `bottomSheetTheme` and the default handle used in `sos_button.dart:168`. **L**
- **`SectionHeader` is underused.** Home re-implements it inline at 20 sp twice (`around_you_section.dart:119-127`, `nearby_cities_section.dart:39-47`). Its action is a bare `InkWell` with 6 px padding, about 30 px tall (`components.dart:470-475`). **M**
- **Touch targets:**
  - `RoundIconButton` defaults to 46 px (`components.dart:311`).
  - `EmptyStateCard` has a fixed 84 px illustration circle (`:759`). It is always a horizontal row, so on 320 px it squeezes the text column to about 170 px.
- **Duplicate screen-reader announcements.** `Semantics(button, label)` wraps an `InkWell` whose `Text` child is still announced (`components.dart:387-391,1012-1016`). Use `MergeSemantics` or `excludeSemantics: true`. **L**
- **Contrast failures:**
  - `MetaPill` default is white 13 sp on 16 %-white over emerald `#26996C`, about 3.3:1 (`components.dart:215,228`).
  - Emerald `#1FA36B` on white is about 3:1, used for the focused input border and progress.
  - Amber `#F5A623` icons on white are about 2:1 (`wishlist_screen.dart:184`).

**What feels non-premium**
- Every surface has a coloured glow shadow.
- Mountain-silhouette painter on every hero, plus gradient place cards with the same silhouettes when there is no photo (`components.dart:611`).
- Pastel Material-palette circles with stock icons used as "illustrations" (onboarding, empty states).
- 800/900 weights everywhere: SectionHeader w800, titles w800, nav label w800. No calm text level.
- Emoji in copy (`daily_challenge_card.dart:167`, `streak_flame_badge.dart:58`).

**Recommended token set for the redesign**
- `AppColors` folded into `ColorScheme` plus a `ThemeExtension`: brand, surface tiers (bg / surface / raised), text (primary / secondary / disabled), and semantic colours (danger / warning / success / info / reward).
- Type scale of 7 steps (display 32, title 22, title-sm 18, body 16, body-sm 14, label 13, caption 12; nothing below 12), applied through `textTheme`, with one licensed font.
- Radius sm 8 / md 12 / lg 20 / pill.
- Elevation 0/1/2 (only one level floats).
- Motion fast 150 / base 250 / slow 400, all honouring `disableAnimations`.
- Delete `GlowButton`. Retire `GlassCard` or reserve it for overlays on the map.

---

#### App shell — `StatefulShellRoute` (4 tabs) — `lib/core/router/main_layout.dart`, `lib/core/theme/components.dart:930-1094`, `lib/main.dart`
- **Job:** switch between Explore, Map, Social and Passport, and always know where you are.
- **Layout today:**
  - `MaterialApp.router` → `AppBackground` (gradient plus 3 radial lights, content capped at 960 px, `glass.dart:18-69`) → Scaffold with a transparent background.
  - `FloatingNavBar` sits in the `bottomNavigationBar` slot. It is a white pill, radius 36, with 4 items: icon 26 plus label 11.5 sp. The selected item is a forest capsule with white content.
- **States:** no splash or loading state. The Firebase failure is silent (`main.dart:21-27`). The badge count is supported but never set (`main_layout.dart:27-47`).
- **What works:** 4 tabs is the right number; there is selected-icon swapping; tab re-tap returns to the branch root (`main_layout.dart:12-15`).
- **Problems:**
  - **H** — No persistent "adventure in progress" indicator in the shell. The way back to a running tracker exists only on Home (`home_screen.dart:142-152`). From Map, Social or Passport there is none.
  - **M** — `extendBody` is not set, so the "floating" pill sits in its own band of about 90 px plus the safe area (`components.dart:960-978`). Content never scrolls beneath it, so it reads as a thick bottom bar with a shadow, not a floating one.
  - **M** — Label 11.5 sp and badge 10.5 sp (`components.dart:1082,1068`). The selected state shows two stacked shadows (bar plus capsule, `:969-975,1028-1035`).
  - **M** — "Passport" (`main_layout.dart:46`) is a metaphor for Profile/Account. First-time users will not find settings there. "Explore" opens a page titled "Where to next?" that is mostly trip planning.
  - **M** — No `NavigationRail` for widths of 600 px and up. On a tablet or the web the pill stretches to 932 px (`glass.dart:10`).
  - **L** — Semantics are announced twice (`components.dart:1012`). There is no haptic feedback on tab change.
  - **L** — Light theme only. `themeMode` is hard-coded (`main.dart:50`).
- **Redesign recommendation:**
  - Keep 4 tabs. Rename them **Explore / Map / Friends / You**. Put the passport stamps and level inside "You".
  - Add a shell-level `ActiveAdventureBar`: a slim pill above the nav showing title, timer and Resume, on every tab while a session exists. It replaces `_ContinueAdventureCard` and the Home "Resume" CTA.
  - Make the nav a flat surface: one hairline border plus elevation-1. Use `extendBody: true` with bottom padding in scroll views. Labels 12 sp w600, selected state as a tinted indicator, not an inverted capsule.
  - Use a `NavigationRail` at 600 px and up. Wire `badgeCount` for Friends (unread chats or invites).
  - Add a branded splash/boot screen. Add `darkTheme` and l10n scaffolding even if only `en` ships.

#### Onboarding — `/onboarding` (forced by redirect, `app_router.dart:52-56`) — `lib/features/onboarding/presentation/onboarding_screen.dart`
- **Job:** understand what Tabi is and grant location, then land on Home.
- **Layout today:**
  - "Skip" text button at top right.
  - `PageView` with 3 pages, each: 140 px pastel gradient circle with a Material icon, a 26 sp w900 title, a 16 sp green subtitle and a 15 sp grey paragraph.
  - Dot indicator, then a 52 px forest `FilledButton`: "Continue", then "Enable Location & Start Exploring".
- **States:** no handling of permission denial; the user goes straight to `/explore` (`:47-54`). No back control; swipe only.
- **What works:** short (3 pages); the location rationale comes before the OS prompt; the dots animate.
- **Problems:**
  - **H** — **"Skip" requests location permission** (`:87` → `_finishOnboarding` `:50`). Skipping fires the OS dialog without context, which is the opposite of what the user asked for.
  - **H** — Page 2 "How XP Works" (`:33-36`) front-loads rules (verify with a live camera photo, ranks, badges) before the user has seen anything. This is jargon on first contact.
  - **M** — The "illustrations" are stock icons in Material pastel circles with off-brand colours (`:24,32,40`: `E8F5E9`, `FFF8E1`, `E0F2F1`). The logo (`assets/branding/tabi_logo.png`, used in login) never appears. This looks like a template.
  - **M** — Fixed 52 px button height with a long label (`:194-213`). "Enable Location & Start Exploring" clips at large text scale. The button radius 26 overrides the theme (`:202`).
  - **M** — The `Column(mainAxisAlignment.center)` in the page (`:107-109`) has no scroll. It overflows on 5" phones at 1.3× text.
  - **M** — Paragraphs of about 35 words, centred, at 15 sp (`:27,35,43`). Centred multi-line body text is hard to read.
  - **L** — Inline font sizes 26/16/15/16 (`:139,150,159,210`). Dots are not tappable and have no Semantics (`:175-192`).
- **Redesign recommendation:**
  - Use 2 screens.
    - Screen 1: full-bleed photo or illustration with the brand mark: "Walk to real places. Collect them." One sentence.
    - Screen 2: a dedicated location-permission screen with a benefit list (3 icon rows), a primary "Allow location" button and a secondary "Not now".
  - "Skip" only completes onboarding. It never prompts.
  - Optionally add a 3rd step "What do you enjoy?" with interest chips. This removes the need to discover Preferences later.
  - Explain XP in context: the first time a place card is opened, or with an "i" on the challenge card.
  - Left-align text, 22–28 sp title, 16 sp body, max about 25 words.
  - Primary button: full width, min height 52 (not fixed), stadium.

#### Login — `/login` (pushed from Social, Leaderboard, Memories, Tours) — `lib/features/auth/presentation/login_screen.dart`
- **Job:** sign in or create an account to use the social features, then go back.
- **Layout today:**
  - No app bar.
  - HeroCard with the logo, 64 px, and a 28 sp white title ("Welcome back, Explorer" or "Create your Explorer account"), with 52 px of bottom padding to show the mountains.
  - SoftCard: email field, password field, "Forgot password?" (13 sp), an error box, a "Sign In" FilledButton, an "or" divider, an outlined "Continue with Google".
  - Then a TextButton toggling sign-in and sign-up.
- **States:**
  - Firebase missing: an `EmptyStateCard` that tells end users to read `PENDING_TASKS.md` (`:247-263`).
  - Submitting: a spinner in the button.
  - Errors: shown in a red box.
- **What works:** a single form toggling modes; reset password prefills the email; the max-width 440 column works on tablets (`:272`).
- **Problems:**
  - **H** — No back or close affordance (`:266-268`). With zoom transitions on iOS (`app_theme.dart:130`) there is no swipe-back either, so users are trapped on iOS.
  - **H** — Developer copy is shown to end users: "Firebase isn't configured… See PENDING_TASKS.md" (`:257-258`).
  - **M** — Raw `FirebaseAuthException.message` is shown verbatim (`:71`, also `:215`). `_submit` has no generic `catch`, so a failing `upsertProfile` (`:53-61`) leaves the user with no message.
  - **M** — The password field has no show/hide toggle, no `autofillHints`, and no `textInputAction` or `onFieldSubmitted` (`:319-343`). The keyboard's Done key does not submit, and password managers don't engage.
  - **M** — Sign-up silently uses the email prefix as the display name (`:58`), which then appears in the Home greeting.
  - **M** — The Google button uses `Icons.g_mobiledata` (`:422`), a fake "G", and is styled as secondary below email. For a consumer app, one-tap Google should lead.
  - **M** — The page never says *why* to sign in (friends, leaderboard, backup). The hero spends about 200 px on a greeting only.
  - **L** — The dialog radius override of 24 (`:139-141`) fights the theme's 28. "Forgot password?" is a compact 13 sp target (`:351-361`). There are no terms or privacy notes on sign-up.
- **Redesign recommendation:**
  - Present Login as a **full-height bottom sheet or modal route with a close (X)**. Opened from a "Sign in to see friends" prompt, it returns to the caller.
  - Order:
    1. Brand mark plus a one-line value proposition ("Sync your passport and explore with friends").
    2. Official "Continue with Google" button, primary.
    3. "or use email" divider.
    4. Email and password fields with visibility toggle, autofill hints and `TextInputAction.next`/`done`.
    5. Primary "Sign in".
    6. A segmented control or link for "Create account".
  - On sign-up, ask for a display name.
  - Map auth error codes to friendly copy through a shared `friendlyAuthError(code)`, shown in a `StatusBanner(error)`.
  - Firebase-missing state: "Sign-in isn't available right now" plus a Back button. No file names.

---

#### Home — `/explore` (tab 1) — `lib/features/home/home_screen.dart`

**Section order as rendered** (`home_screen.dart:127-247`). Viewport estimates are for a 360×740 dp phone, with about 640 dp visible above the nav.

| # | Section | Code | Approx. height | Visible on first screen? |
|---|---|---|---|---|
| 1 | Header: avatar 54, greeting plus location line, streak badge, 3 `RoundIconButton`s (Safety, Preferences, Wishlist) | `:130-141`, `:255-358` | 54 | yes |
| 2 | Continue-adventure card (only while a session exists) | `:142-152`, `:441-509` | 76 | yes |
| 3 | "Where to next?" headline at 38 sp | `:154-164` | 46 | yes |
| 4 | Search bar (opens SearchSheet) | `:166-172` | 50 | yes |
| 5 | **TripHomeCard**: "Your trip" header plus Today / Upcoming / Planning card, or a deep-green **HeroCard "Plan a trip anywhere in India"** with an amber "Plan a trip" button | `:174-177` | 200–260 | yes; dominates |
| 6 | NearbyCitiesSection "Top Nearby Destinations", city carousel, cards 170×190 | `:179-186` | 230 | header only |
| 7 | AroundYouSection: title plus "Within N km" menu, weather advisory, filter chips, place-card carousel (200×150) plus "See all on the map" | `:188-212` | 280–340 | no |
| 8 | DailyChallengeCard (GlassCard) | `:214-220` | 170 | no |
| 9 | Quick actions row: Trip Planner, Memories, (Ecosystem, flag off), Journal, Calendar | `:222-225`, `:512-557` | 70 | no |
| 10 | **Hero "Ready for your next adventure?"** with weather pill and amber **Start/Resume** | `:228-238`, `:360-437` | 160 | no (~1,300 dp down) |
| 11 | AI Explore Next (GlassCard, only if a Gemini key is set) | `:240-246` | 120+ | no |

**Verdict: too much.** There are up to 11 blocks: 2 HeroCards, 2 horizontal carousels, 2 glass cards, a tile row, and 3 weather displays (header `:285`, hero pill `:397-402`, advisory banner).
- For a new user, the first screen is a greeting, a giant question, search, and a **trip-planner advert**.
- The app's core loop is "walk to real places nearby, earn XP, keep a streak". Both its entry points sit below the fold: "Around you" is block 7 and "Start" is block 10.
- There are three competing amber/primary CTAs ("Plan a trip", "Start", "Claim XP"). The trip planner is reachable 3 ways from Home (block 5, block 9, and the "Plan" link in search).

- **Job:** "What can I do right now?" Resume what is running, else pick a nearby place and go, else plan a trip.
- **Layout today:** see the table above.
- **States:**
  - Location off: the header reads "Location off · Exploring India" and Around You shows a good two-button card (`around_you_section.dart:333-405`).
  - Loading: skeleton cards in Around You. Trips, challenge, streak and cities render `SizedBox.shrink` while loading, then pop in and shift the layout (`trip_home_card.dart:113`, `daily_challenge_card.dart:17-18`, `streak_flame_badge.dart:155-156`, `nearby_cities_section.dart:25-27`).
  - Error: an `EmptyStateCard` that shows the raw exception text (`home_screen.dart:196`).
  - Offline: a friendly message in Around You (`around_you_section.dart:308-309`).
  - Signed-out: not relevant.
- **What works:**
  - Ordering by "what am I doing now" is the right instinct (comment `:125-126`).
  - The location-off card offers both "Turn on" and "Pick a city".
  - Around You merges four older rows into one filterable row (`around_you_section.dart:53-55`).
  - The weather advisory is honest and reversible.
- **Problems:**
  - **H** — **Header overflow.**
    - Fixed widths: avatar 54 + 12 + 8 + streak about 53 + 8 + 3×46 + 2×10 = about 293 px (`:293-354`). On a 360 dp phone (320 px of content) the greeting and location column gets about 27 px. On 412 dp it gets about 79 px. "Good afternoon, Jatin" and "Near you · 28°C" truncate to "Go…".
    - Three equal-weight utility icons (Safety, Preferences, Wishlist) are settings, not Home actions.
  - **H** — **Primary action is unclear and in the wrong place.** "Start adventure" (block 10, `:228-238`) is the core action but sits last. The planner HeroCard (`trip_home_card.dart:557-602`) takes the hero slot instead.
  - **H** — **Duplicate in-progress UI:** the `_ContinueAdventureCard` "Continue" (`:142-152,500-504`) and the hero "Resume" (`:403-406,428`) are shown together.
  - **M** — The location line is not tappable (`:310-331`). Changing city is buried in "All Cities" in block 6 (`nearby_cities_section.dart:49-52`) or in the location-off card. Users expect to tap "Near you ▾".
  - **M** — The "Where to next?" headline at 38 sp (`:158-162`) plus the greeting is about 100 px of non-actionable copy above the fold.
  - **M** — Quick actions: 4 tiles of about 72 px with 12 sp labels (`:539-547`). "Trip Planner" truncates at text scale above 1.0. Memories, Journal and Calendar are archive features that belong in "You".
  - **M** — Three section-header styles on one page: `SectionHeader` 21 sp with an amber action (`trip_home_card.dart:119`), inline 20 sp with a green `TextButton` "All Cities" (`nearby_cities_section.dart:39-52`), and inline 20 sp with a `PopupMenuButton` (`around_you_section.dart:119-161`). Title case "Top Nearby Destinations" sits next to sentence case "Around you".
  - **M** — The raw error is shown to the user (`:196`). Pull-to-refresh (`:121-124`) does not refresh trips, challenge or streak.
  - **L** — Staggered `FadeSlideIn` on 9 blocks (`:130-238`) runs once at mount, before the async blocks have data. They pop in afterwards anyway.
- **Redesign recommendation (first screen):**
  1. **Compact top bar:** avatar (opens You), a tappable **location chip** "Near you ▾ / Jaipur ▾" (opens the city picker), the streak chip, and one overflow or bell. Move Safety, Preferences and Wishlist to You → Settings; Safety also goes in the `ActiveAdventureBar`.
  2. **Search field** (real field styling, 48 px).
  3. **One state-driven "Now" card,** using the only HeroCard on the page:
     - adventure running → Resume (or rely on the shell bar);
     - trip today → next stop plus "Go";
     - trip upcoming → countdown;
     - otherwise → "Start exploring" with the daily challenge folded in as a progress line ("Visit 2 places · 1/2 · +50 XP").
  4. **"Around you"** carousel with filter chips and the distance control as a chip ("15 km ▾").
- **Redesign recommendation (below the fold):**
  - "Plan a trip" as a compact `SoftCard` row (not a hero).
  - "Destinations" city carousel.
  - The AI pick shown as the first card of Around You ("Picked for you"), not a separate block.
  - Remove `_QuickActions`, the 38 sp headline and the duplicate weather pills. Weather stays once, in the location chip line or the advisory.
  - Section headers: one `SectionHeader` with a "See all" `TextButton` (48 px) everywhere.
  - Reserve space for async blocks with skeletons, so nothing jumps.

#### Home: Around You and its cards — `lib/features/home/around_you_section.dart`, `lib/features/weather/presentation/weather_advisory_banner.dart`
- **Job:** browse the nearest places by kind and open one.
- **Layout today:**
  - Title plus a "Within 15 km ▾" popup.
  - Optional amber advisory banner ("Show all" / "Hide unsuitable").
  - `ChoiceChip` row of 40 px (only the kinds that have places).
  - A 182 px carousel of `HomePlaceCard`s (photo or gradient, distance pill, subtitle "Open now · Temple · +50 XP"), ending in a 120 px "See all on the map" card.
- **States:** location off, loading skeletons, empty state with a widen-radius action, offline, and advisory-filtered. All are present and well worded (`:306-331`).
- **What works:** contextual empty actions ("Look within 50 km"); mystery places keep their secret; the advisory is reversible.
- **Problems:**
  - **M** — The distance control is a hidden `PopupMenuButton` with 12.5 sp text and a target about 24 px tall (`:130-161`).
  - **M** — Filter chips are M3 `ChoiceChip` (`:237-253`) while Preferences uses `CategoryChip`, so there are two filter-chip languages. Labels are 12.5 sp.
  - **M** — The card subtitle packs 3–4 facts into one 12.5 sp line on a 200 px card (`:447-454`, `components.dart:668`). It truncates. Open/closed status is conveyed by icon swap plus text in amber on a dark scrim.
  - **M** — The mystery gradient `#8E2DE2→#4A00E0` (`:463`) is an off-brand neon purple. The `'???'` pill (`:468`) is a gimmick.
  - **L** — "Turn on" and "Pick a city" use `VisualDensity.compact` (`:385,393`), giving targets under 48 px.
  - **L** — The advisory banner uses a raw radius of 16 and 12.5 sp (`weather_advisory_banner.dart:44,65`). It should be a shared `StatusBanner(warning)`.
- **Redesign recommendation:**
  - Card: photo, title (2 lines, 16 sp), meta row (distance, open status as a small coloured dot plus text), and an XP tag as a separate small badge. Card height grows with text scale.
  - Distance as the first chip in the filter row ("≤15 km ▾") using the same `FilterChip` component.
  - Map mystery places to the brand palette (forest plus amber glyph).
  - Advisory → `StatusBanner.warning` with a trailing text action.

#### Home: TripHomeCard — `lib/features/planner/presentation/trip_home_card.dart`
- **Job:** continue or prepare the user's trip, or start planning one.
- **Layout today:** a `SectionHeader` "Your trip / Your trip today" plus "All trips", then one of:
  - Today: label, day title, progress bar, next stop with a 72 px photo and hours, then "Start/Continue today's plan" and "View day".
  - Upcoming: label, "Goa in 5 days", dates, weather and packing pills, then "Open plan" and "Packing & budget".
  - Planning: a row card with chevron.
  - None: the planner HeroCard with an amber CTA.
- **States:** loading hides the section entirely (`:113`). There is no error branch: `.value` swallows errors.
- **What works:** smart prioritisation (`pickHomeTrip`, `:47-92`); the next stop includes opening hours; the planning card nudges the user to add dates.
- **Problems:**
  - **H** — The no-trip state is a full HeroCard advert at the most valuable position on Home (`:557-602`). The whole card is tappable *and* has an `AmberPillButton` (`:564,595`), so there are two targets for one action.
  - **M** — Trips open via an imperative `Navigator.push(MaterialPageRoute)` (`:155-161`), not a route. This hurts deep linking and back behaviour.
  - **M** — "Packing & budget" opens `day: plan.days.length` (`:491-492`), a magic index for the Essentials tab.
  - **M** — `_Label` is 11 sp caps w800 (`:176-183`). `Text(day.title, maxLines: 2)` has no overflow (`:227`). `CircleAvatar` uses raw `Color(0xFFE6F4EA)` (`:522`).
  - **L** — Today card: both the whole card and "View day" open the same thing (`:219,291`).
- **Redesign recommendation:**
  - Keep the Today and Upcoming cards. They are good "Now" card content, so promote them into Home's single hero slot.
  - Demote "no trip" to a slim row: "Plan a trip ›" with a sparkle icon.
  - Use go_router routes (`/my-trips/:id?day=`, `/my-trips/:id/essentials`).
  - Use a single primary button per card (Go / Open plan), with secondary actions as text links.

#### Home: Daily challenge and streak badge — `lib/features/challenges/presentation/daily_challenge_card.dart`, `streak_flame_badge.dart`
- **Job:** see today's goal and progress, claim XP, and know whether the streak is safe.
- **Layout today:**
  - Challenge: GlassCard (tinted amber when done) with an icon, "DAILY CHALLENGE" (12 sp w900 caps), an XP pill, a 17 sp title, a description, a 7 px progress bar, "3 / 5", and "Claimed" / a compact amber "Claim XP" / "In progress".
  - Streak: an orange flame chip with a count in the header. Tapping it opens a bottom sheet with a 64 px orange gradient flame, "N Day Streak", a status line with emoji, a freeze explainer box, the best streak, and an "Awesome" button.
- **States:** both hide on loading or error (`daily_challenge_card.dart:17-18`, `streak_flame_badge.dart:155-156`). There is no "streak lost" state.
- **What works:** claim-as-reward moment; freezes explained in plain words (`streak_flame_badge.dart:99`).
- **Problems:**
  - **M** — The streak chip is about 30 px tall (`streak_flame_badge.dart:167`). It has no Semantics or tooltip, so a screen reader hears "3". Its state is colour-only, grey vs orange (`:159-161`).
  - **M** — 13 raw colours in the streak file: orange, deepOrange, grey.shade50/200/400, blueAccent, plus the gradient `FF9800→FF5722` (`:28,73,75,81,160-176,194`). deepOrange text on a light orange tint is about 3:1.
  - **M** — The "Claim XP" button is compact with 6 px vertical padding (`daily_challenge_card.dart:146-153`), under 48 px. "3 / 5" has no unit (`:117`). There is no way to see *how* to complete the challenge.
  - **L** — Emoji (`daily_challenge_card.dart:167`, `streak_flame_badge.dart:58`). "Awesome" as a dismiss label (`:141`). The jargon "counted trip" (`:59`).
- **Redesign recommendation:**
  - Fold the challenge into the Home "Now" card as one progress line with a "Claim" button when done.
  - Streak chip: 48 px target, `Semantics(label: '3-day streak, safe today')`, and an icon shape change (filled vs outline), not colour alone. Use brand amber, not orange.
  - Sheet: use the standard `AppSheet`, "Got it" as the button, no emoji.

#### Home: Search bar and Search sheet — `lib/features/explore/presentation/widgets/explore_search_bar.dart`
- **Job:** find a city or place anywhere in India.
- **Layout today:**
  - Bar: a white box with radius 18, grey border and black shadow, a search icon, the placeholder "Search places, cities in India..." and an "All India" tag.
  - Sheet (88 % height): hand-drawn handle, autofocused field, a 2 px progress bar, then Recent (with Clear all and per-row ✕), Popular-destination `ActionChip`s, and a helper paragraph. Results are `ListTile`s with highlight, distance and a "✨ Plan" link. The no-match state offers "Search everywhere"; there is an offline notice.
- **States:** loading, offline, empty and no-match are all handled well (`:461-535`).
- **What works:** instant local results plus a debounced online search; stale-response guarding; match highlighting; recent searches.
- **Problems:**
  - **M** — The bar is a `GestureDetector` with no ripple (`:53`). It is styled unlike the theme's input (raw white plus `Colors.grey.shade200` border, black shadow, `:57-67`). The placeholder `grey.shade500` on white is about 2.7:1 (`:77`). The "All India" tag (`:83-97`, 11 sp) looks tappable but isn't.
  - **M** — The sheet has a fixed `0.88 × height` with no `viewInsets` padding (`:325`). With the keyboard up, the bottom of the results list can't scroll above the keyboard.
  - **M** — The "Plan" link is an `InkWell` with 2 px vertical padding, about 20 px tall (`:640-660`). It sits next to the row's own tap target, so mis-taps are likely.
  - **L** — Off-brand Google grey `#F1F3F4` (`:400,564`). The 22 sp helper paragraph copy (`:448-452`) is long.
- **Redesign recommendation:**
  - `AppSearchField` (read-only variant on Home, using the theme's input styling, 48–52 px, with a ripple). Drop the "All India" tag; put "India" in the placeholder.
  - Open search as a full-screen route (`/search`) with a hero-animated field. This solves keyboard insets and supports back-swipe.
  - Results: `AppListTile` with a trailing "Plan trip" `IconButton` of 48 px, or a swipe/long-press menu.

#### Home: Nearby cities and city picker — `lib/features/explore/presentation/widgets/nearby_cities_section.dart`, `city_picker_modal.dart`
- **Job:** browse destination cities, or change the city Home is centred on.
- **Layout today:**
  - Section: "Top Nearby Destinations" plus an "All Cities" `TextButton`, then a 190 px carousel of 170 px photo cards (distance pill 11 sp, name, state).
  - Picker sheet (80 %): "Select City in India" plus "Reset to GPS", a search field, and a list of `ListTile`s (44 px thumbnail, name, "STATE · CATEGORY", check or chevron).
- **States:** the section hides while loading or empty (`:25-27`). The picker shows a spinner and a plain-text empty state.
- **What works:** real photos; the picker search filters by state and category; the current city is marked.
- **Problems:**
  - **H** — **Two city lists that look alike do different things.** Tapping a carousel card opens the city page (`nearby_cities_section.dart:73`). Tapping a city in "All Cities" silently **re-centres the whole of Home** (`city_picker_modal.dart:194-197`). The label "All Cities" suggests browsing.
  - **M** — Without location, the first 8 catalogue cities are still titled "Top Nearby…" (`nearby_cities_section.dart:23,40`).
  - **M** — The `FutureBuilder` future is created in `build` (`:20-23`), so it refetches and flashes on every Home rebuild. The `Image.network` has no placeholder or fade (`:117-126`).
  - **M** — The card has radius 18 and a black shadow (`:103-110`), against the `PlaceCard`'s 26 and green shadow on the very next row. It is a `GestureDetector` with no ripple or Semantics (`:98`).
  - **L** — The picker uses "Reset to GPS" jargon (`city_picker_modal.dart:106`) and shouty `category.toUpperCase()` at 12 sp (`:178`). It has no keyboard insets (`:72`).
- **Redesign recommendation:**
  - Rename the section to "Destinations" (or "Cities near you" only when located). The action "See all" goes to a browse page (`/cities`).
  - The city picker is opened only from the Home location chip. Title: "Explore from…". First row: "📍 My location" (not "Reset to GPS"), then a recent city or two, then the searchable list.
  - Unify `CityCard` with `PlaceCard`: same radius, shadow, scrim and type.

#### Home: AI Explore Next — `lib/features/home/ai_recommendation_card.dart`
- **Job:** get a single AI-picked place suggestion.
- **Layout today:** emerald-tinted GlassCard with an icon, the title "AI Explore Next" and a refresh button, then an "Ask AI for a recommendation" button, then a paragraph of text plus "▶ Go to {place}".
- **States:** loading skeleton (good); error shows the raw `$_error` in red (`:131-135`); hidden when no key is set (`:76-78`).
- **Problems:**
  - **M** — The raw exception is shown to the user (`:133`).
  - **M** — The title copy "AI Explore Next" (`:110`) is awkward.
  - **M** — The "Go to …" label with a play icon (`:147-151`) only opens a sheet; it doesn't navigate.
  - **M** — The answer is an unbounded paragraph (`:137-144`).
  - **L** — Its margin (vertical 16) differs from its neighbours. It sits last on Home, after the "Start" hero.
- **Redesign recommendation:** merge it into Around You as a "Picked for you" first card: photo, the place name, a one-line reason (truncate the AI text to about 120 chars, with "More" for the rest), and tap → place sheet. Fall back silently.

---

#### Preferences — `/preferences` (Home header ⚙, Profile) — `lib/features/preferences/presentation/preferences_screen.dart`
- **Job:** tell Tabi what I like, and set battery and reminder options.
- **Layout today:**
  - AppBar "Exploration Preferences" (24 sp) with a stadium "Save" `FilledButton`.
  - Staggered `FadeSlideIn` cards:
    - Interests: 13 `CategoryChip`s.
    - Duration: 7 chips.
    - Difficulty: 5 chips.
    - Social Preference: 5 chips.
    - Battery saving: a switch.
    - Reminders & Notifications: 3 switches.
- **States:** skeleton while loading; the error shows the raw `$error` (`:52`); there is no unsaved-changes state.
- **What works:** each section explains what it affects (`:63-65,78,87-88,96`); switches explain the timing ("7 PM", "Sunday 11 AM"); the snackbar explains a notification refusal.
- **Problems:**
  - **H** — **Two save models on one page.** Chips need "Save" (`:26-40`); switches save instantly (`:175-176,235-236`).
    - Chip changes update the in-memory provider at once, so they *look* applied (`preferences_service.dart:17-36`).
    - If you leave without Save, they are lost on restart. There is no warning on back.
  - **M** — The title at 24 sp plus the Save button in the app bar (`:22-41`) truncates on 360 dp phones.
  - **M** — The "Duration" label (`:77`) actually sets the Around You radius ("How far 'Around you' looks"). Difficulty "Beginner…Expert" (`user_preferences.dart:27-33`) sets the *planner pace*. Labels don't match effects.
  - **M** — The interest wall: 13 chips at 15 sp w700, 22 px horizontal padding, each with its own shadow (`components.dart:403-422`), make a very busy block. The single-choice sections look identical to multi-select and deselect on re-tap (`:143`), which is hidden behaviour and lacks radio semantics.
  - **M** — The screen mixes taste preferences with app settings (battery, notifications). There is no place for account, privacy, units, about or sign-out. "Battery saving" has no section heading (`:155-179`).
  - **L** — The notification-refused snackbar has no "Open settings" action (`:189-196`). The staggered entrance animation on a settings page (`:60-114`) is gratuitous.
- **Redesign recommendation:**
  - Split it into **You → Settings** (grouped `SettingsGroup` and `SettingsTile`: Notifications, Battery & GPS, Safety, Account, About) and **"Your interests"**, which is also used in onboarding.
  - Autosave everything with a subtle "Saved" toast. Remove the Save button.
  - Interests: compact `FilterChip` (14 sp, w600, no shadow, check icon when selected).
  - Single choice: a `SegmentedButton` or a radio list with labels that say the effect: "How far to look nearby: 5 / 10 / 15 / 25 / 50 km", "Trip pace: Relaxed / Balanced / Packed", "Usually travelling: Solo / Friends / Family / Group".
  - Title: "Preferences" (or "Your interests"), standard AppBar size.

#### Safety and SOS — `/safety` (Home header shield only) — `lib/features/safety/presentation/safety_screen.dart`, `sos_button.dart`
- **Job:** in an emergency, alert my contacts with my location or call help, fast.
- **Layout today:**
  - AppBar "Safety".
  - A centred 132 px red SOS hold-button (ring fills over 2 s) with the caption "Hold 2 s".
  - A helper sentence.
  - "Emergency contacts" `SectionHeader` with an amber "Add", then contact cards (tap = edit, trash = delete) or an empty card.
  - "Helplines in India": 9 SoftCards, each with a tonal "📞 112" button.
  - SOS opens the SMS app, or falls back to a sheet with Call 112, Share and Add contacts.
- **States:** loading uses a `LinearProgressIndicator` (`:48-49`). The load **error is treated as "no contacts"** (`:20`). Sending shows a spinner in the button. With no contacts, the SOS falls back to a helpful sheet.
- **What works:** hold-to-send with a progress ring and haptics (`sos_button.dart:36-41,68-72`); a sensible fallback sheet with 112; contacts are stored locally, and the screen says so; the Semantics label explains the hold (`:61-66`).
- **Problems:**
  - **H** — **Reachability.** SOS is only reachable via a 46 px Home header icon (`home_screen.dart:338-342`) → `/safety` → a 2 s hold. It is not shown on the tracking screen or Map (the only use is `safety_screen.dart:28`). For a walking app, safety must be one tap away during an adventure.
  - **H** — "Call 112" is not a primary action on the page. It is the first row of the helplines list (`:97-118`), below the contacts.
  - **M** — A plain tap on SOS gives no feedback (only long-press is handled, `sos_button.dart:67-76`). Panicked users tapping repeatedly see nothing. There should be a "Keep holding…" hint on tap.
  - **M** — Deleting a contact is instant, with no confirm or undo (`safety_screen.dart:86-92`). The edit form is an `AlertDialog` (`:130-133,179`) instead of a sheet, and there is no "pick from phone contacts".
  - **M** — Raw red colours with no danger token (`sos_button.dart:91,92,101,104,203`). The "Hold 2 s" caption is 12 sp white70 on red.shade700, about 3.4:1 (`:125-131`).
  - **L** — 9 helplines as separate shadowed cards make a long, heavy list. The tonal button uses seed colours (`:111`). The contact row nests a `ListTile` in a tappable `SoftCard` (`:64-93`), giving a double ripple.
- **Redesign recommendation:**
  - Top block: the SOS hold-button plus a **"Call 112"** primary danger button side by side, with copy that says exactly what SOS does ("Texts your location to Mum and 1 other").
  - Contacts as an `AppListTile` group, with "Add from contacts" as the primary option and manual entry as secondary. Swipe or overflow to delete, with an undo snackbar.
  - Helplines as one grouped list of dense tiles, each with a trailing call `IconButton` (48 px).
  - Add a `danger` colour token.
  - Expose SOS in the shell `ActiveAdventureBar` and on the tracking screen. Keep the `/safety` entry under You → Settings → Safety, not in the Home header.

#### Wishlist and WishlistButton — `/wishlist` (Home header bookmark) — `lib/features/wishlist/presentation/wishlist_screen.dart`, `wishlist_button.dart`
- **Job:** see the places I saved and go to one; save or unsave from a place sheet.
- **Layout today:**
  - AppBar "Wishlist".
  - `SectionHeader` "Places".
  - SoftCard rows: a 52 px gradient tile with a category icon, the title, "Temple · Tap to start", and an amber filled-bookmark button that removes the place.
  - The button: a stadium `OutlinedButton` "Save to wishlist" / "Saved to wishlist".
- **States:**
  - Skeleton while loading.
  - Error shows the raw `$error` plus "Try again" (`:54-63`).
  - Empty state has no action (`:68-77`).
  - Pull to refresh.
- **What works:** saved order is preserved; mystery names are kept hidden; it reuses the place sheet.
- **Problems:**
  - **M** — Removal is instant, with no undo (`wishlist_screen.dart:98-105,182-187`). The amber icon on white is about 2:1, and the only signal of the remove action is the tooltip.
  - **M** — Rows show a category gradient with a stock icon instead of the photos Home already loads (`:141-153`). The list looks like placeholder content.
  - **M** — The empty state has no CTA such as "Explore places nearby" (`:71-75`). "· Tap to start" (`:95-96`) is instruction-as-copy. A single section header "Places" (`:88`) is redundant.
  - **L** — `toggleWishlist` has no error handling and no confirmation feedback (`wishlist_button.dart:42-49`). The label-only state change ("Saved to wishlist") makes a wide button; inside the place sheet it competes with the primary "Start" action.
  - **L** — There are no distance, sort or "show on map" options. The only entry point is the Home header icon.
- **Redesign recommendation:**
  - Rename to **"Saved"**. Put it under You (or as a filter on Map).
  - Rows: `AppListTile` with a 56 px photo thumbnail, name, "Temple · 3.2 km", and a trailing overflow menu (Remove, Show on map). Removing shows an undo snackbar.
  - Empty state with an "Explore nearby" CTA.
  - `WishlistButton` → icon toggle (bookmark outline/filled, 48 px) in the place-sheet header, with a "Saved · View" snackbar.

---

### Cross-screen patterns in this group

1. **Raw exception text in UI.** Seen at `home_screen.dart:196`, `preferences_screen.dart:52`, `wishlist_screen.dart:57`, `ai_recommendation_card.dart:133` and `login_screen.dart:71`. Introduce `friendlyError(Object e) → (title, message, retry?)` and an `ErrorState` widget.
2. **Settings scattered across the Home header.** Safety, Preferences and Wishlist live there (`home_screen.dart:338-354`), with no unified Settings or Account screen. Introduce a **You → Settings** hub built from `SettingsGroup` and `SettingsTile`.
3. **Each screen draws its own primary button.** Make the theme button shape `StadiumBorder`, and add `AppButton.primary/secondary/tertiary/danger` with min height 48 and a loading state. Remove the per-call `styleFrom` overrides.
4. **Inline section headers and pills.** Use one `SectionHeader` (with a `TextButton` action, 48 px) and one `Tag` / `Badge` (variants: neutral, onDark, reward, warning). Replaces `MetaPill`, `_Label`, `_DarkPill`, the XP pill and the "All India" tag.
5. **Banners.** Introduce `StatusBanner(kind: info|warning|error|offline, action)` for the weather advisory, the login error, the search offline notice and the Home fetch failure.
6. **Bottom sheets with hand-made handles and no keyboard insets.** Introduce `AppSheet` (handle, title row with close, `viewInsets`-aware, max height) for search, city picker, streak, SOS fallback and contact edit (replacing the dialog).
7. **List rows.** `ListTile`-in-`SoftCard` (safety), custom Rows (wishlist) and bare `ListTile`s (search, picker) all coexist. Introduce `AppListTile` (leading 40–56 thumbnail or icon, title, subtitle, trailing, optional grouped card container).
8. **Carousels.** Two horizontal sections with different card types, heights and header styles. Introduce `CarouselSection(header, itemExtent, skeleton, seeAll)` plus a unified `MediaCard` (PlaceCard and CityCard).
9. **Async blocks render nothing while loading,** so the layout jumps. Every async block gets a skeleton with fixed height.
10. **Imperative navigation.** `Navigator.push(MaterialPageRoute)` in `trip_home_card.dart:155-161` and 16 times across features, combined with zoom transitions on iOS. Move to go_router routes and the platform-native transition.
11. **Destructive actions with no undo:** contacts and wishlist. Standard: snackbar with "Undo".
12. **Accessibility.** Targets under 48 px (`RoundIconButton` 46, streak chip about 30, SectionHeader action about 30, "Plan" link about 20, compact buttons). Colour-only state (streak). Duplicate Semantics. Add a lint-like checklist plus a `Tappable` helper that enforces 48 px and merges semantics.
13. **Emoji and gamey copy:** "Awesome", 🎉, 🔥, "???", "Explorer". Adopt a calm copy voice and keep the gamification visual (badges), not exclamatory.
14. **Introduce `ActiveAdventureBar` in the shell.** It solves Home duplication, cross-tab resume and SOS reachability at once.

### Quick wins

1. **Restore iOS back-swipe.** Use `CupertinoPageTransitionsBuilder` for `TargetPlatform.iOS` (`lib/core/theme/app_theme.dart:130`).
2. **Make "Skip" stop prompting.** It should only complete onboarding, not request location (`lib/features/onboarding/presentation/onboarding_screen.dart:87` → split `_finishOnboarding` at `:47-54`).
3. **Remove developer copy.** Delete "See PENDING_TASKS.md" from the user-facing message (`lib/features/auth/presentation/login_screen.dart:257-258`). Add an `AppBar` with close or back to Login (`:266`).
4. **Login form basics.** Add a password visibility toggle, `autofillHints` and `textInputAction` (`login_screen.dart:319-343`), and a generic `catch` in `_submit` (`:70-74`).
5. **Fix the Home header overflow.** Move Preferences and Wishlist out of the header, keeping one overflow menu (`lib/features/home/home_screen.dart:343-354`), and make the location line tappable to open the city picker (`:310-331`).
6. **Remove the duplicate Resume.** Hide the hero's "Resume" while `_ContinueAdventureCard` is visible (`home_screen.dart:403-406,428`). Move `_HeroSection` above `NearbyCitiesSection` (`:228-238` → after `:172`).
7. **Replace raw error strings with friendly copy:** `home_screen.dart:196`, `preferences_screen.dart:52`, `wishlist_screen.dart:57`, `ai_recommendation_card.dart:133`.
8. **One save model in Preferences.** Call `notifier.save()` inside the toggle and set callbacks, and drop the Save button (`lib/features/preferences/presentation/preferences_screen.dart:23-42`, `preferences_service.dart:17-36`).
9. **Touch targets and button shape.**
   - `RoundIconButton` default size 46 → 48 (`lib/core/theme/components.dart:311`).
   - `SectionHeader` action padding to give a 48 px min height (`:473-474`).
   - Theme `buttonShape` → `StadiumBorder` (`app_theme.dart:116-118`), which deletes about 10 overrides.
10. **Copy and contrast fixes.**
    - Remove the emoji (`daily_challenge_card.dart:167`, `streak_flame_badge.dart:58`) and change "Awesome" to "Got it" (`streak_flame_badge.dart:141`).
    - Change the search placeholder from `Colors.grey.shade500` to `AppTheme.inkMuted` (`explore_search_bar.dart:77`).
    - Rename "Top Nearby Destinations" to "Destinations" when there is no location (`nearby_cities_section.dart:40`).


---

## UI audit B: discovery screens (City detail, Place sheet, Map tab, place tools)

All paths relative to `/home/cts/wrk/time-tracker-t/lib/features/`. `lib/features/tracking/presentation/navigation_view.dart` is not in this group and is not auditable (empty).

---

#### City detail — `/city/:cityId` (go_router, pushed from Explore/search) — `explore/presentation/city_detail_screen.dart`
- **Job:** decide what to do in a city: browse its places, then open one (or plan a trip).
- **Layout today:** SliverAppBar, 240 px, pinned, with network hero photo, black-circle back button, black-circle "Explore on Map" icon and white FlexibleSpace title (:142-225). Then two MetaPills (state, CATEGORY in caps) (:232-238), the blurb (:240), a row with a full-width ElevatedButton "Plan a Trip to {city}" and a tonal shield icon for safety tips (:251-289). Then **What to eat** (horizontal dish cards), **Community tours** (horizontal cards, signed-in only), the **Offline map** card, the "Places to Explore (n)" title, category FilterChips, a weather advisory banner, and finally the place list (SoftCard rows: 72 px thumb, name, 2-line description, category pill, "+XP") (:291-365).
- **States:** first load shows a bare centred `CircularProgressIndicator` on the background with no app bar and no back button (:102-104). The second phase (places) shows another spinner (:322-330). Error shows plain `Text` and an `ElevatedButton` "Go back" (:106-123), with no retry. Empty shows an ad-hoc icon and text, not `EmptyStateCard` (:331-355). If the hero image fails, it falls back to a sage box with a city icon (:199-208). The offline state is not communicated. Signed out, the tours section vanishes silently.
- **What works:** the collapsing photo header. The weather-aware filtering with "show all" toggle. Place rows open the shared place sheet.
- **Problems:**
  - **H** `MetaPill` defaults to white text on `white @16%` (`core/theme/components.dart:200,215`). City pills (:234,236) sit on the near-white page and are effectively invisible. The category pill in every place card (:461) sits inside a white SoftCard, white on white.
  - **H** The pinned SliverAppBar sets no `backgroundColor`, and the theme's app bar is transparent (`app_theme.dart:140`). Collapsed, the white title (:185-191) floats over scrolling content with nothing behind it.
  - **H** The primary content (places) sits below three optional modules: dishes, tours and offline (:291-297). On a phone the list starts roughly two screens down.
  - **M** Competing CTAs: an Elevated "Plan a Trip" (AI sparkle icon, its own radius 16, :254-264), a tonal shield icon whose only label is a tooltip (:283-287), and a map icon in the header (:161-182). Each place card also carries XP. Nothing says "start here".
  - **M** Section titles use three styles: inline 18 sp w800 here (:298-305), in dishes (`food/.../signature_dishes_section.dart:66-73`) and in tours (`tours/.../city_tours_section.dart:31-38`). None use `SectionHeader` (21 sp). The offline card has no title at all.
  - **M** Category chips are a hard-coded list of 6 (:373-381), missing trek, waterfall, mountain, camping and food. Chips can lead to an empty result. The empty copy says "for this category" even when the weather filter is what hid the places.
  - **M** Custom black-alpha circle buttons (:146-157, :162-173) differ from `RoundIconButton` (white) used everywhere else.
  - **L** Place cards never pass `distanceKm` to `showPlaceSheet` (:414), so the sheet's distance pill never shows from here. Text runs at 12.5 and 12 sp (:453, :474) and 11 sp (:507). Network images have no loading placeholder (:423).
- **Redesign recommendation:**
  - Order: hero, then a facts row (state, best season, weather chip), then a 2-line blurb with "More", then a **sticky segmented tab bar: Places | Food | Tours | Offline**. Places is the default tab, so the list is above the fold.
  - One primary CTA: a bottom-docked "Plan a trip" bar. Move Safety into a labelled list row ("Safety & etiquette") inside an "Essentials" block next to Offline map.
  - Give the pinned header a solid `surface` background with a dark title on collapse. Use `RoundIconButton` (white) for back and map.
  - Fix `MetaPill` to take an explicit tone (`neutral/brand/accent/onImage`) with no white-on-transparent default.
  - Place rows: introduce `PlaceListTile` (thumb, name, category and distance meta, optional saved state). Drop XP from list rows.
  - Generate category chips from the categories actually present, with counts ("Heritage 12"). Use `EmptyStateCard` with a "Clear filters" action.
  - Use a skeleton list on load, keeping the app bar and back button visible. On error, show `EmptyStateCard` with Retry.

##### Embedded: Signature dishes / Community tours / Offline pack
- `signature_dishes_section.dart`: fixed `height: 128` (:81) with `Expanded` note and a `when` line (:131-150) overflows at large text scale. Card radius 18 with an amber border (:105-108) is a one-off. `DietMark` raw colours `0xFF1B8A3A`/`0xFFB3261E` (:38-39) are justified (Indian standard) but should be tokens. It has `Semantics`, which is good. Cards aren't tappable: no detail and no "find near me" link, so this is a read-only dead end (**M**). A natural action would be to open the Map food layer.
- `city_tours_section.dart`: hidden entirely when signed out (:20-23), so users never learn tours exist (**M**). It should show a teaser with "Sign in to see community tours". Opens with an imperative `Navigator.push(MaterialPageRoute)` (:64-66) rather than a route (deep-linking and back behaviour differ). Fixed `height: 112` with a 2-line title, a `Spacer` and two 12.5 sp lines (:41, :83-105) overflows with text scaling. Cards show no rating, though ratings exist. The border uses the primary colour (:73) while dish cards use amber (:108), two ad-hoc card styles side by side.
- `offline/presentation/offline_pack_card.dart`: no title (body only), unstyled default `Text` (:94-97, :117-120, :132-137). "tiles" is developer jargon (:96, :136). The error is raw `Colors.redAccent` (:157). It mixes TextButton "Stop"/"Delete" with FilledButton "Download" (:104,122,139). That makes it the third filled button on the page (**M** hierarchy). Delete has no confirmation (:76-79). Recommend: an `AppListTile` titled "Offline map", subtitle "About 42 MB · works without signal", trailing tonal "Download", and progress shown as a percentage.

---

#### Place sheet — `showPlaceSheet()` modal bottom sheet (from City detail, Home, Wishlist, search) — `locations/presentation/place_sheet.dart`
- **Job:** understand a place and start a trip to it.
- **Layout today (top to bottom):** a 210 px photo gallery (blurred with a lock pill if it's a mystery) (:152-198). A 24 sp title (:200-208). A Wrap of up to **5 pills**: category, distance + walk time, +XP, "Mystery Solved", difficulty (:210-249). A purple "Mystery Location Challenge" GlassCard (:250-296). **TripPlanCard**: "Plan your trip" with subtitle "Journey: getting there by any transport", By car / On foot tiles, and an emerald trek-rule explainer box (:298-302, :385-529). Then the description (:304-311). The **Start** FilledButton (:313-329). A centred Wrap of **3 outlined pills**: "Save to wishlist", "AR guide", "What's this?" (:331-368). A footnote (:370-375).
- **Action count:** 1 filled CTA, 3 outlined buttons, a tappable photo (opens the viewer), and swipeable photos. Plus 5 pills and 2 explainer cards competing for attention. That is 4 equal-weight buttons below about 700 px of content.
- **States:** journey loading shows two skeleton tiles (:434-441). No route shows a "Straight line" tile (:442-450). Photos loading shows a "Finding photos…" pill (`place_photo_gallery.dart:127-134`). Location off is only reported by a snackbar *after* tapping Start (:75-77). An adventure already in progress gives a snackbar plus a redirect to `/tracking` (:61-67), which is a surprise navigation.
- **What works:** one-tap Start with real car and walking estimates. The mystery blur concept. The swipeable photos with credit.
- **Problems:**
  - **H** The primary CTA is below the fold. Start comes after the gallery, title, pills, mystery card, TripPlanCard (roughly 250 px) and description (:313). It isn't sticky, so on a 640 dp phone users must scroll to act.
  - **H** Logistics come before content. TripPlanCard (:298) precedes the description (:304), so the user reads transport and trek rules before learning what the place is.
  - **H** Rules jargon in core UI. "Journey: getting there by any transport" (:430). "Trek starts within N m of X. Only your time on foot from there counts as trek, for stats and achievements." (:510-514). "Tracks your route and guides you there step by step." (:372). These are three explanatory texts on one sheet.
  - **M** Secondary actions are equal-weight outlined pills in a centred Wrap (:331-368). "Save to wishlist" plus "AR guide" exceeds 320 dp, so on a 360 dp phone they wrap to 2 ragged rows. "AR guide" shows even when the place is hundreds of km away. "What's this?" (Lens) is unrelated to the place unless you're standing there. Lens is also gated by `arSupported` (:354) though it only needs a camera.
  - **M** Raw colours: `Colors.deepPurple` (:220,240,253,260,265) and black overlays (:166,176). The mystery palette is not a token.
  - **M** Title Case copy: "Photo Blurred · Walk Here to Unmask" (:185), "Hunt This Mystery" (:319), "Mystery Location Challenge" (:275). Text sizes of 12.5 sp appear 6 times (:189,287,373,431,569,588).
  - **M** Two category colour systems disagree. `place_style.dart:8-36` gradients vs `domain/location.dart:86-115` `Colors.*` (e.g. hiddenGem is pink vs a purple gradient, food is red vs a teal gradient, photography is purple vs an orange gradient). `shortLabel` maps food to "Café" (`place_style.dart:45`), which is misleading.
  - **L** Nested cards: an emerald gradient box inside a SoftCard (:477-524), and a GlassCard on a sheet (:252). There are 4 different radii (24/18/16/stadium).
- **Redesign recommendation:**
  - Use a `DraggableScrollableSheet` with a peek state of photo, title and one meta line ("Heritage · 2.4 km · 30 min walk"), plus a **sticky bottom action bar**. Primary: "Start trip" (mystery: "Start the hunt"). Secondary: a bookmark icon button with a label in Semantics.
  - Order: photos, title, meta line, description (3 lines plus More), "Getting there" (car/walk tiles), then the community block (explorers, tips).
  - Move AR guide and Lens into a "Tools" row of small labelled icon buttons ("Point me there", "Identify"). Show AR only when the distance is under about 2 km.
  - Delete the trek explainer and footnote. Put a single "How trips are counted" info icon next to "Getting there", which opens a help sheet.
  - Limit pills to 2 (category, and difficulty if any). Show XP as a subtle "+40 XP on arrival" line by the CTA, not an amber pill.
  - Merge the two category colour maps into one `CategoryStyle` token set (icon, colour, gradient, label) in the theme.
  - Make this the **only** place sheet. The Map's marker sheet should call it (see below).

##### Helpers: `place_photo_gallery.dart`, `place_style.dart`
- Gallery: the credit is 11.5 sp white over a 60% gradient (:74-79). There are no page dots, only a "1 / n" pill. The fallback "Finding photos…" `MetaPill` uses the default white-on-16%-white over arbitrary photos (:131-134), a contrast risk. The broken-image icon is `Colors.white70` (:158). The photo viewer is an imperative `MaterialPageRoute` with a hard black AppBar (:170-176, :203-211). It has no hero transition or swipe-down-to-dismiss, so it feels abrupt (**L**). Photos have no semantics label.
- `MountainPainter` artwork as placeholder is OK, but the place's gradient differs from its marker colour (see above).

---

#### Location tips (community block) — embedded in Map marker sheet — `locations/presentation/location_tips_section.dart`
- **Job:** read and add short tips from other explorers.
- **Layout:** an "N explorers" row with a TextButton "Add Tip" (:130-148), then up to 5 tip rows (tinted pills "Name: text" with a delete icon or overflow menu) (:149-156, :282-344).
- **States:** Firebase off shows nothing (:90). Signed out shows a muted text "Sign in (Social tab) to see and share tips…" with **no button**, a dead end (:92-100). It has a skeleton (:120-124) and an error state with Retry (:107-118), both good. With no tips, only "0 explorers · Add Tip" shows, with no invitation copy.
- **Problems:** **M** Adding a tip opens an `AlertDialog` over a bottom sheet (:162-165, :346-391). An inline composer or a nested sheet would be easier. **M** Deleting your own tip happens instantly with no confirm or undo (:193-205, :323-328). **M** Block uses a primary `FilledButton` for a destructive action (:262-265). **L** "Add Tip" and "Share a Tip" are Title Case (:145, :365). The tip row's `IconButton` sits in 4 px vertical padding (:302). The name and text run together in one `Text.rich` line (:310-321) with no avatar or date. Tips are hidden from the shared place sheet entirely (only the Map sheet embeds them), so most entry points never show community content (**M**).
- **Redesign:** create a `TipTile` with avatar, name and relative date, the text, and trailing overflow (Report/Block, or Delete with undo snackbar). Show the empty state as "Be the first to leave a tip" with an inline field. Signed out, show a "Sign in to see tips" button that routes to `/login`. Embed it in the unified place sheet.

---

#### Map tab — `/map` (shell branch 2) — `map/map_screen.dart`
- **Job:** see where interesting places are around me (and what I've found), tap one, go.
- **Layout today:** an AppBar titled "Map", "My Map" or "Social Map" (:490-494) with **4 round icon actions** (:495-583):
  1. `auto_awesome`: "Discover Nearby Places with AI" (:513-519), which swaps to a spinner while generating.
  2. `mic_none_rounded`: "Leave an audio capsule here" (:522-527).
  3. `restaurant(_outlined)` with an amber dot: food layer toggle (:531-537).
  4. Mode menu trigger, whose icon *changes with the mode* (`visibility_off`, `visibility`, `person_pin_circle`, `group`) (:541-581). Its popup items are Exploring / Full map / My places / Social map (:62-86).
  
  The body has the FlutterMap with OSM raster tiles (:594). In My places mode it shows route polylines in emerald, and in Social mode friends' paths in amber (:595-634). Place markers (:635-655), purple capsule markers (:656-688) and orange food markers (:689-720) follow. Overlays: a top-left **mode pill** repeating the mode label (:743-781), a "Search food here" tonal button at bottom 110 when food is on (:724-742), an "N visited" pill bottom-left (:782-794), and a 54 px my-location button bottom-right (:795-804).
- **Marker vocabulary (no legend anywhere):**
  - Visited: emerald disc with an amber tick (:818-855).
  - Discovered: a bare category icon in Material colour, no background (:857-862).
  - Wishlisted (My places mode only): an amber bookmark (:864-865).
  - Undiscovered: a "?" at 40% opacity (:867-870).
  - Capsule: a purple `0xFF6A4BC4` headphones disc (:671).
  - Food: an orange `0xFFE8743B` disc (:703).
  - You: an avatar in a rank frame (`person_marker.dart`).
- **States:** loading shows a full-page shimmer with a "Finding your location..." pill (:425-447), which is fine. **Permission denied / no fix:** it silently falls back to `ServiceArea.center` (:166-167). Fog then treats that as "you" and there's no banner. My-location does nothing when the fix is null (:411-418). Repository errors in `_init` (:165) are unhandled, so the page stays on the shimmer forever. Social mode signed out or with no friends shows an empty map with no explanation (:98-100, :616-634). Food empty or error goes to a snackbar (:387-398). AI not configured shows the developer message "AI is not configured. Add GEMINI_API_KEY." to end users (:292). Failure shows a raw exception, `'Failed to generate places: $e'` (:337).
- **What works:** the person marker with avatar is personal and on-brand. The "Search this area" pattern for food. Visited places are visually distinct. Tooltips exist on all app-bar icons.
- **Problems:**
  - **H** The app bar mixes four unrelated jobs as identical white circles: an AI content generator, a content-creation tool (record audio), a layer toggle, and a view switcher. Their meaning is only discoverable by long-press tooltip. The sparkle and mic icons don't say "find places" or "leave a voice note". The mode trigger's icon changes shape per mode, and **the default "Exploring" mode uses an eye-crossed-out icon** (:78), which reads as "hidden/disabled".
  - **H** The current mode is shown three times: title (:490), floating pill (:743-781) and menu icon (:579). That's redundant chrome, and mode names ("Exploring" vs "Full map") don't explain the fog-of-war idea. "Full map" is described in code as an escape hatch (:49-51) but users get no explanation.
  - **H** There is no legend for 7 marker styles. Meaning relies on colour and icon alone (purple and orange discs, "?" opacity). Discovered markers are bare 30 px icons with no halo (:858-862), low-contrast on busy OSM tiles.
  - **H** Developer and raw-error copy reaches users (:292, :337, and capsule copy in `capsule_sheet.dart:146`).
  - **M** Touch targets: app-bar buttons are 42 px (:515,524,533; `_MapCircle` :999-1000). Place markers are 40 px and capsule/food markers 34 px (:641-642, :663-664, :695-696). There is no clustering, so dense areas produce overlapping, untappable markers.
  - **M** Permission-denied and offline get no UI (see States). The user believes they are at the service-area centre.
  - **M** Raw colours: `0xFF6A4BC4`, `0xFFE8743B`, `Colors.white` ×8, and an inline shadow and radius 24 on the mode pill (:752-763) duplicate `_MapCircle` and `RoundIconButton` styles. `_MapCircle` re-implements `RoundIconButton` (:991-1017).
  - **M** The default OSM raster style (:594, `osm_tiles.dart:11`) is colourful and busy. It clashes with the restrained green brand and makes the map feel unbranded and unpolished. A MapTiler key already exists for offline packs (`osm_tiles.dart:39-41`).
  - **L** Emoji in the capsule snackbar "🎧 Audio capsule here" (:262) with a 10 s duration (:260). The 'Finding your location...' pill uses three dots, not an ellipsis (:438). The AI-discover success says "Discovered N new places!" (:330) but they appear as "?" markers under fog, which is confusing.
- **Redesign recommendation:**
  - App bar becomes the title "Map" only, plus a single **"Layers" button** (labelled icon `layers_outlined`). It opens a sheet with a view `SegmentedButton`: "Nearby (fog)" / "Everything" / "Mine" / "Friends", each with a one-line description. It also holds overlay toggles (Food, Audio notes, My routes), with the legend at the bottom of the same sheet.
  - Move "Leave a voice note" into a bottom-right **FAB stack**: primary FAB "Add" (voice note / tip), and the secondary my-location button. Move "Find more places (AI)" into an empty-area prompt or a chip that appears when few places are visible ("Few places here · Suggest more").
  - Replace the floating mode pill with a filter-chip row under the app bar ("Nearby · Food · Friends"). Show state once.
  - Introduce `MapPin` (a 44 px tap area, white halo, category-coloured fill, state badges for visited/saved/locked) and a **cluster** marker. Use one token palette for category colours and drop the bare icons.
  - Add a `StatusBanner` for "Location off: showing {city}. Turn on" and for "Offline: cached map". On `_init` failure show `EmptyStateCard` with Retry.
  - Apply a muted custom tile style (MapTiler "streets-light" or similar) tinted toward the cream and sage palette.
  - Make tapping a marker open the unified place sheet in **peek** mode (map stays visible), not a full modal.

##### Map marker sheet (`_showLocationSheet`, `map_screen.dart:873-986`)
- **H** This is a second, divergent copy of the place sheet. It has a 180 px gallery vs 210 (:894), a 20 sp title vs 24 (:910), and a tinted category pill vs a solid one (:933-937). It has no TripPlanCard, no distance, no AR or Lens. It does include `LocationTipsSection` (:980), which the real sheet lacks. The CTA is "Start" or "Guide me there" (:968), while the real sheet says "Start" or "Hunt This Mystery". The same place therefore looks and behaves differently depending on the entry point.
- **M** Undiscovered places show "Undiscovered location" and "Get closer to reveal this location." (:881, :947-950) but still offer "Save to wishlist" (:976) for a nameless place, and "Guide me there", which spoils the fog mechanic.
- **M** "Start" alone is ambiguous: start what? Use "Start trip".
- **Recommendation:** delete this function and call `showPlaceSheet(place, distanceKm, mode: undiscovered/mystery)`. Undiscovered variant: a silhouette image, "Unknown place · 1.2 km", one CTA "Head that way", and no wishlist.

---

#### Food spot sheet — tap orange marker on Map — `food/presentation/food_spot_sheet.dart`
- **Job:** decide whether to eat here.
- **Layout:** DietMark and name at 20 sp (:39-56), "kind · cuisine" (:58-61), raw OSM hours (:62-68), a 12 sp disclaimer (:70-73), and, only if a trip is today, the FilledButton "Add as snack stop · Day N" (:74-105).
- **Problems:** **H** Dead end. With no trip today the sheet has **no action at all**: no directions, no "Start trip", no "Open in Maps". **M** Hours show raw OSM syntax (`Mo-Fr 09:00-18:00`) (:65), not "Open now · closes 18:00". **L** Ad-hoc text sizes 20/13/12 (:49,66,72). There is no photo or distance.
- **Redesign:** reuse the place sheet skeleton (`PlaceSheetScaffold`): title, meta (diet, cuisine, distance), an "Open now" status chip, and primary "Directions" (start trip). Make "Add to today's plan" secondary.

#### Audio capsule sheet & leave-capsule flow — Map marker / snackbar "Listen" / mic app-bar action — `memories/presentation/capsule_sheet.dart`
- **Layout:** headphones icon and caption at 19 sp with no colour token (:92-106), "Left here by X", a FilledButton Listen/Pause, and a TextButton "Report this capsule".
- **Problems:** **M** No playback progress or duration and no loading state between tap and audio (:57-59). **M** The leave flow stacks a recorder sheet and then an `AlertDialog` (:149-154). Visibility **defaults to "Everyone"** (:182), a privacy-hostile default. **M** Gating messages are snackbars: "Sign in (Social tab) to leave capsules." gives no sign-in action (:144). "Capsules are not set up yet: no memories server address." is developer copy (:146). The mic button stays visible even though it cannot work (`map_screen.dart:522-527`). **L** "Capsule" is jargon. Users would understand "voice note".
- **Redesign:** a single "Leave a voice note" sheet with recorder, caption and visibility (default Friends) and one "Post" CTA. Hide the entry point when the feature is unavailable. The player gets a progress bar and duration, and Report moves into an overflow menu.

#### Person marker / OSM tiles — `map/person_marker.dart`, `map/osm_tiles.dart`
- Good: `Semantics` labels (`person_marker.dart:44-46, 117-119`) and the avatar in a rank frame with a pointer.
- **L** StartPin text is 11 sp (:146). The emerald glow (:53-58) is another one-off shadow.
- **L** The attribution is plain text on 75% white (`osm_tiles.dart:43`). It's fine, but should be styled small and muted to match.
- **M** Tile style: see the Map tab.

---

#### AR wayfinder — `showArWayfinder()` imperative push from place sheet "AR guide" — `ar/presentation/ar_wayfinder_screen.dart`
- **Job:** point the camera and see which way the place is.
- **Layout:** full-screen camera preview, a floating name/distance label with an amber 56 px pin at screen-x of the bearing (:147-153, :195-226), a bottom rotating amber arrow and hint pill (:154-165, :228-276), a compass-disturbed hint (:166-175), and a top-left `IconButton.filled` close (:176-185).
- **States:** "Starting camera…" or "Camera not available" as plain white70 text (:141-146), with **no permission-recovery action** (**M**). No GPS means "Finding your location…" forever, with no timeout or explanation (:246-247) (**M**). There is a phone-flat hint, which is good.
- **Problems:** **H** It auto-closes after 90 s without a tap (:23, :78-80) with no warning. The user walking with the phone up gets kicked out mid-navigation. **M** The close tooltip says "Back to the map" (:180) but the view is opened from the place sheet (City, Home, Wishlist). **L** "Turn right 37°" uses degree jargon (:255-257). "? m" appears when distance is unknown (:253). The label width is fixed at 120 (:151) with 3-line truncation. Hint pills are raw black at 60% (:289).
- **Redesign:** add a top bar with the place name and distance, and a close button. Give the hint copy the steps "Turn left", "Slightly right", "Straight ahead". Before the 90 s auto-close, show "Still navigating? Tap to stay", or pause the camera instead of closing. On camera or location denial, show a full-screen `EmptyStateCard` with an "Open settings" button.

#### Sightseer Lens — `showLens()` imperative push from place sheet "What's this?" — `lens/presentation/lens_screen.dart`
- **Job:** photograph something and learn what it is.
- **Layout:** AppBar "Sightseer Lens" (:99), an `EmptyStateCard` intro or the 240 px photo (:103-116), a FilledButton "Take a photo" / "Try another" (:118-122), a spinner (:124), red error text (:125-126), the result (22 sp name, style · era, unsure warning, summary, "Look for" `SectionHeader` and ListTiles with search icons), an Outlined "Listen" button, and a 12 sp AI disclaimer (:127-177).
- **What works:** this is one of the cleaner screens. It uses `EmptyStateCard`, `SectionHeader` and `AppSpacing.page`, has a single clear CTA, and has an honest "unsure" flag.
- **Problems:** **M** The naming mismatch: the entry is "What's this?", the title is "Sightseer Lens", and the icon is `center_focus_strong`. **M** `pickImage` isn't in try/catch (:48-52), so a camera-permission denial surfaces nothing. **M** The spinner has no "Identifying…" label, and results land below the button, often off-screen with no auto-scroll. **L** The error uses `Colors.redAccent` (:126). The details' search icon (:162) is a wrong metaphor for "look for". It is gated by `arSupported` at the entry point even though it only needs a camera (`place_sheet.dart:354`).
- **Redesign:** retitle it "Identify" with subtitle "near {place}". The photo goes at the top, and the result is presented as a card under it with a shimmer "Identifying…" state. "Listen" becomes an icon button in the result header, and the details become a bullet list. Add permission and error handling via `StatusBanner`.

#### Tour detail — imperative push from City tours card — `tours/presentation/tour_detail_screen.dart`
- **Job:** judge a community tour and adopt it.
- **Layout:** AppBar with the tour title and a delete icon if it's yours (:31-41). A long meta line "By X · City · N stops · N km stop to stop" (:45-50). A text-glyph rating "★ 4.3 (n ratings)" (:51-61). The description. A 200 px map with dotted line and numbered markers (:67-118). The stops as `ListTile` with default `CircleAvatar` numbers (:120-128). The FilledButton "Plan this tour" (:130-134), Outlined "Rate this tour" (:135-142), and Reviews (:143-154).
- **States:** ratings loading or error are invisible (it treats them as none) (:25-27). There is no empty-reviews prompt. A tour with 1 stop or identical points gives degenerate `CameraFit.bounds` (:73-76).
- **Problems:** **M** The primary CTA sits below the full stop list (:130), not sticky. **M** Stop numbers in the list use theme-default `CircleAvatar` colours (:123) while the map markers are forest (:100-101), so the two don't visually link. **M** Stars are text glyphs (:54, :151), with no star widget or semantics. **L** Delete (destructive) is confirmed with a FilledButton in forest, not an error colour (:218-221). The title truncates in the AppBar. "km stop to stop" is awkward copy (:48). It uses an imperative `MaterialPageRoute` to the itinerary (:166-170).
- **Redesign:** a hero map (taller, 260) with a title and creator chip, and a stats row (stops · km · rating) as `StatTile`s. Use a numbered `StopTile` matching the map markers. Add a sticky "Plan this tour" bar, with Rate as a secondary text button in the reviews header. Add a reviews empty state. Give it a go_router route `/tour/:id`.

#### Publish tour flow — called from itinerary day — `tours/presentation/publish_tour.dart`
- **Job:** share a completed day as a tour.
- **Flow:** checks, then a snackbar on failure, then an `AlertDialog` with title and description (:58-65, :156-202), then a snackbar on success.
- **Problems:** **M** Eligibility failure is a transient snackbar with jargon: "Reach at least N stops of Day X on a trip (with the live photo) to publish it. K so far." (:49-52). The user can't see *which* stops count. **M** Signed out, the snackbar says "Sign in (Social tab)" **and** pushes `/login` at the same time (:34-37), which is contradictory guidance. **L** The dialog crams privacy copy and two fields into an AlertDialog (:163-166). The success snackbar is the only confirmation, with no "View tour" action (:100).
- **Redesign:** use a "Publish tour" sheet with a checklist of the day's stops (✓ verified / ○ not yet reached). The CTA is disabled with a reason until the minimum is met. Add title and description fields and a privacy note. After success, show a snackbar with a "View" action that opens the tour route.

---

### Cross-screen patterns in this group
1. **The same object gets three different sheets.** The place sheet (`place_sheet.dart`), map marker sheet (`map_screen.dart:873`) and food sheet (`food_spot_sheet.dart`) have different title sizes, CTAs, sections and actions. Introduce `PlaceSheetScaffold` (gallery slot, title, `MetaRow`, body slots, **sticky `SheetActionBar`**) and route all through it.
2. **No sticky primary action.** The main CTA sits at the end of the scroll in the place sheet, tour detail and the Lens result. Add `SheetActionBar` / `BottomCtaBar`.
3. **Button roles are inconsistent.** Primary CTAs use FilledButton (place sheet, tour), ElevatedButton (city "Plan a Trip"), FilledButton.tonal (food search) and FilledButton (offline Download) on the same screen. Secondary actions use OutlinedButton pills or TextButton at random. Define `PrimaryButton`, `SecondaryButton`, `TertiaryButton` and `DestructiveButton` (the last is currently FilledButton forest in 3 dialogs).
4. **Section headers are inline 18 sp ×4**, and `SectionHeader` (21 sp) is used only in Lens and Tour detail. Use one `SectionHeader` with an optional subtitle and action.
5. **Horizontal card carousels have fixed heights** (128, 112) and break with text scaling. Use a `CarouselCard` with intrinsic height and a min/max.
6. **Category style lives in two places that disagree** (`place_style.dart` gradients vs `location.dart:86` `Colors.*`). Create one `CategoryStyle` token map in the theme, used by markers, pills, placeholders and chips.
7. **`MetaPill` has an unsafe default** (white on white 16%), which is invisible on light surfaces. Give it explicit tones (`MetaPill.neutral/brand/accent/onImage`).
8. **Gating and errors are snackbars with developer copy** ("Add GEMINI_API_KEY", "no memories server address", `$e`, "Sign in (Social tab)"). Add `StatusBanner` and `GateCard` (signed out / feature off / permission denied, each with a real action button). Hide unavailable entry points.
9. **Imperative `Navigator.push(MaterialPageRoute)`** is used for tour detail, photo viewer, AR, Lens and itinerary (`city_tours_section.dart:64`, `place_photo_gallery.dart:170`, `ar_wayfinder_screen.dart:31`, `lens_screen.dart:16`, `tour_detail_screen.dart:166`). There are no shared transitions and no deep links. Move them to go_router routes with a shared page transition.
10. **Dialogs are used where sheets or inline editing fit better:** add tip, report tip, block, rate tour, publish tour, capsule details. Use `FormSheet`.
11. **Game-rule copy leaks into utility UI:** trek/journey explainer, XP pills on every row, "Hunt This Mystery", "Unmask". Keep XP to one subtle line near the CTA and move rules to a help sheet.
12. **Map markers need a system:** `MapPin` (44 px hit area, halo, state badge), `ClusterPin`, and a `MapLegend` in the layers sheet.
13. Sub-12 and odd text sizes are common (11, 11.5, 12, 12.5). Use textTheme roles (`labelSmall` ≥ 12, `bodySmall` 13).

### Quick wins
1. Give `MetaPill` usages on light surfaces explicit colours: `city_detail_screen.dart:234,236,461`. The pills are currently invisible.
2. Set `backgroundColor`/`surfaceTintColor` on the pinned SliverAppBar and switch the title to dark when collapsed: `city_detail_screen.dart:142-145`.
3. Replace user-facing developer errors with friendly copy and hide the action when unavailable: `map_screen.dart:292`, `map_screen.dart:337`, `capsule_sheet.dart:146`.
4. Change the "Exploring" mode icon from `visibility_off` to `explore` or `blur_on`, and drop the redundant mode pill: `map_screen.dart:78`, `map_screen.dart:743-781`.
5. Move the Start button above TripPlanCard, or wrap it in a sticky bottom bar: `place_sheet.dart:298-329`.
6. Remove the trek explainer and footnote from the place sheet: `place_sheet.dart:429-432`, `place_sheet.dart:477-524`, `place_sheet.dart:369-375`.
7. Replace the map marker sheet with `showPlaceSheet` so tips, distance and plan appear consistently: `map_screen.dart:644`, `map_screen.dart:873-986`.
8. Add a "Directions" (start trip) CTA to the food sheet so it is not a dead end: `food_spot_sheet.dart:74`.
9. Raise map app-bar buttons to 48 px and markers to a 44–48 px hit area: `map_screen.dart:515,524,533,641,663,695`.
10. Default capsule visibility to Friends, and warn before the AR 90 s auto-close: `capsule_sheet.dart:182`, `ar_wayfinder_screen.dart:78-80`.


---

## UI audit C: trip planning, live trips, trip art

Scope read in full: `lib/features/planner/presentation/` (trip_planner_screen, itinerary_detail_screen, my_trips_screen, trip_essentials_view, stop_actions, stop_hours, rebalance_sheet, trip_share), `lib/features/tracking/presentation/` (tracking_screen, start_adventure_view, live_trip_card, journey_trek_breakdown, trip_not_counted_checklist, trip_share_sheet), `lib/features/heatmap/presentation/` (heatmap_screen, poster_screen).

**Can't be audited:** `lib/features/tracking/presentation/navigation_view.dart` is 1 line right now. It matters a lot. `tracking_screen.dart:112-132` sends **every trip that has a destination** to `_NavigationView`, and every planner "Go" button (`stop_actions.dart:29-43`, with `autostart=1`) creates one of those trips. So the live screen that planner users actually see can't be audited. Everything below under "Live trip" covers only the free-exploration screen (no destination). `_StepRow` and `_formatMeters` (`tracking_screen.dart:863-946`) look like they belong to the navigation view and weren't reviewed as rendered UI.

Scope totals: about 106 raw `Colors.*`, 13 hex `Color(0x…)` literals and 110 inline `fontSize:` across these 15 files. The only `Semantics` is the Start button (`start_adventure_view.dart:270`).

---

#### AI Trip Planner form — `/trip-planner` (go_router, `?destination=&cityId=`) — `lib/features/planner/presentation/trip_planner_screen.dart`
- **Job:** pick a destination and get an AI day-by-day itinerary.
- **Layout today:** AppBar ("AI Trip Planner", back button, shield icon for Safety, TextButton "My Trips"). One long ListView: gradient hero intro card ("India Itinerary Generator" plus a marketing line), then nine labelled sections: Destination (text field and a tonal city-picker button) → Trip Duration (7 chips: 1,2,3,4,5,7,10) → "When Are You Going? (Optional)" (date button and helper text) → "Who's Going?" (4 chips with long descriptions) → Pacing (3) → Budget (3) → "Interests & Focus" (8 filter chips) → "Traveling From (Optional)" (text field) → "Itinerary Language" (English/हिंदी). Then an error box, then a 54 px "Generate Itinerary" button at the very bottom.
- **States:** Loading is only a spinner inside the Generate button and the label "Crafting Your India Itinerary..." for up to **3 minutes** (`:166-168`). There's no full-screen progress, no cancel, and the form stays editable. Error is a red box above the button (`:610-624`). An empty destination gives a snackbar. There's no offline pre-check and no signed-out note (plans save locally, which is fine).
- **What works:** Sensible defaults pre-filled from preferences (`:75-92`), so **only one field is required**. The city-picker grounding (`cityIdForDestination`) is good. The date range preview in the button is helpful.
- **Problems:**
  - **H** Value is buried. Only the destination is required, yet Generate sits below nine sections and the hero card. That's about 2.5 screens of scrolling on a 6" phone before the primary action shows (`:233-279` hero, `:629-662` button). "How many fields before value": 1 required, 10 inputs shown.
  - **H** Generation can take up to 3 min with only an inline button spinner at the bottom of the scrolled form (`:633-648`). There's no staged progress ("Finding landmarks… Mapping routes…"), no cancel, and the inputs stay live, so it's unclear whether a mid-flight edit applies.
  - **M** Pace and Budget chips show only the label (`:460`, `:499`). The enum descriptions ("1-2 highlights a day…", `planner_input.dart:17-30`) are never shown, while Companion chips do show theirs as long chip text ("Friends · Excitement, nightlife & fun", `:427`, 12.5 sp). Three choice groups, three treatments.
  - **M** The same section label style is copied inline 9× (16 sp w800, `:283-290, 331-338, 366-373, 412-419, 442-449, 481-488, 520-527, 559-566, 583-590`). It doesn't use `SectionHeader`. Labels mix Title Case and "(Optional)" suffixes.
  - **M** App bar mixes an icon button and a TextButton.icon (`:216-226`). "Safety" is unrelated to planning and competes with My Trips.
  - **M** Generate is a custom `ElevatedButton` styled forest with radius 16 (`:654-660`), not a themed Filled/AmberPill button. The error box uses raw `Colors.red.shade50/200/800` (`:615-621`).
  - **M** After success the itinerary is pushed with `Navigator.push(MaterialPageRoute)` (`:179-183`), so Back returns to the filled form. Tapping Generate again creates a duplicate saved trip.
  - **L** The destination clear (×) button only appears on rebuild. The TextField has no `onChanged`/listener (`:296-314`). Duration has no 6, 8 or 9 days (`:343`). Two names for one feature ("AI Trip Planner" vs "India Itinerary Generator", `:205`, `:259`). The hero card has a heavy shadow and gradient (`:237-249`) for pure marketing copy.
- **Redesign recommendation:**
  - Step 1 on one screen: a large destination search field (city picker inline as suggestions, not a separate button), a days stepper or segmented control, optional dates, and a sticky primary **"Plan my trip"** button always visible at the bottom.
  - Move Companion / Pace / Budget / Interests / From / Language into a collapsed "Tailor it" section (or a second optional step) showing the pre-filled values as a one-line summary ("Friends · Balanced · Moderate · Heritage, Street Food").
  - Use one `ChoiceGroup` component for single-select options, showing label plus a one-line description under the selected option only.
  - Make generation a dedicated full-screen progress state: destination hero image, 3–4 staged messages, Cancel. Replace the form route with the result (`context.go`/`pushReplacement`) so Back goes to My Trips.
  - Drop the marketing hero card. Put "My Trips" as a single app-bar icon with a tooltip and move Safety to the itinerary's Essentials.
  - Show errors with a shared `StatusBanner` (error variant) and a Retry action.

---

#### Itinerary detail — pushed imperatively (planner `:179`, My Trips `my_trips_screen.dart:175`); no route — `itinerary_detail_screen.dart` (+ `stop_hours.dart`, `stop_actions.dart`)
- **Job:** follow today's plan: see the day's stops on a map and go to the next one.
- **Layout today:** AppBar (destination title, Share popup menu with text / image / "Publish this day as a tour", an amber bookmark/cloud icon that only shows a snackbar). A white 80% strip of day ChoiceChips plus a final "Essentials" chip (`:409-447`). The scrolling body: Day title and theme next to two outlined icon buttons, clock = "Adjust my day" and refresh = "Regenerate" (`:461-513`). Then a 190 px map with numbered markers and a road polyline (`:517-619`), a red "closed on Mondays" banner (`:623-656`), an amber day-tip card (`:659-691`), "Planned Stops (n)" with "x of n done" (`:695-716`), and one SoftCard per stop: a 150 px photo gallery, a row with number badge + TIME SLOT pill + "60 min" + up/down/× icons, the name, the `StopHours` row (expandable week table with Open/Closed/Approx chips), the description, an amber tip, and a row of "+50 XP · Go" plus "Mark done" (`:781-1011`). A leg row ("12 min walk") sits between cards (`:752-780`). Then "Recommended Food & Cafes" in a white bordered box (`:1017-1066`). Pinned at the bottom is a `bottomSheet` with "Go to stop N: Name" (`:1074-1120`).
- **States:** No-stops day shows centred grey text (`:720-729`). Hours loading says "Checking opening hours…". Offline shows dotted straight lines (`:551-561`). A day with no stops centres the map on **Delhi** (`:302-304`). Regenerating shows a spinner in the icon button only. A shared trip live-updates silently (`:285-299`), with no "Edited by X" indicator.
- **What works:** The sticky "Go to stop N" CTA plus a snackbar "Next: … Go" chain (`:266-278`) is the right core loop. Next / done / pending marker colours on the map. Honest hours with a source label ("Approx." vs OSM). Undo on Adjust day.
- **Problems:**
  - **H** Density. Each stop card stacks photo (150) + meta row + name + hours + description + tip + actions, roughly 380–420 px, so a 4-stop day is about 1,700 px plus map and banners. Five type sizes appear in one card (10.5/12/12.5/13/16 sp). The descriptions are full AI paragraphs with no truncation (`:932-939`).
  - **H** Touch targets. Move up, Move down and Remove are `IconButton`s with `padding: zero, constraints: BoxConstraints()`, so the hit area is about 18 px, packed 4 px apart (`:868-909`). Remove has no confirm and **no Undo** (`:204-215`), unlike Adjust (`:126-131`).
  - **H** Too many competing actions per screen: Share menu, a fake bookmark button, Adjust, Regenerate, per-stop Go, per-stop Mark done, reorder ×2, remove, sticky Go. Two "Go" affordances for the same stop. The XP amount is fused into a navigation label ("+50 XP · Go", `:976`).
  - **M** The bookmark/cloud icon (`:385-402`) is a status indicator styled as an action, in amber `#F5A623` on a light bar (≈2:1 contrast).
  - **M** Icon meaning: clock icon = "Adjust my day" (`:491`) is unguessable. Regenerate is a destructive whole-day action shown with the same weight, and it uses an AlertDialog (`:135-153`).
  - **M** "Essentials" is appended as a fake day chip (`:417`, `:431`). On a 7–10 day trip it's off-screen at the end of a horizontal scroll, and it swaps the whole body type.
  - **M** The map is fixed at 190 px inside a scrolling ListView with full gestures enabled (`:520`, `:536-540`), so dragging over it pans the map instead of scrolling. There's no expand-to-fullscreen.
  - **M** The `bottomSheet` container has no SafeArea (`:1076-1120`), so the button sits on the gesture bar. The list's 80 px bottom padding is a magic number (`:458`).
  - **M** Inconsistent surfaces. The closed banner uses Google hex colours `0xFFFCE8E6/0xFFD93025` (`:628, :636`, also `stop_hours.dart:112, 119, 192, 225`). The tip uses an amber tint card. Food uses a white box with a `Colors.grey.shade200` border (`:1030-1034`). Stops use SoftCard. Section headers are inline 16 sp (`:697-704, :1019-1026`), not `SectionHeader`. Raw `Colors.grey`, `Colors.black26` on markers (`:578, :589`).
  - **M** Text under 12 sp: the TIME SLOT pill is 10.5 sp uppercase (`:849-855`), the hours chips 10.5 sp (`stop_hours.dart:263`) and the hours footnote 11 sp (`stop_hours.dart:240`).
  - **L** The stop hours row packs dayLabel + hours + up to 2 chips + chevron into one ellipsised line (`stop_hours.dart:131-166`), so the hours text gets truncated first on small phones. Completed stops use `Opacity(0.7)` over the whole card (`:783-784`), which lowers contrast on everything.
- **Redesign recommendation:**
  - Structure: a compact header (dates, day selector as a segmented "Day 1 · Day 2 …" with dates), then a **collapsible map** (about 35% of the height, tap to expand fullscreen, `scrollGesturesEnabled` off inline), then a **timeline list** of compact stop rows (time slot, name, 1-line description, hours status dot, leg time between rows). Tap a row to open a stop detail sheet with photos, full description, tip, hours week, Mark done and Remove.
  - Single primary action: the sticky "Start · Stop 2: Dashashwamedh Ghat" with a separate small XP badge. Remove the per-row Go.
  - Move Essentials out of the day chips into a top-level segmented control "Plan | Essentials" or a header button.
  - Day tools (Adjust, Regenerate, Reorder) go in one "Edit day" overflow / edit mode with drag handles (`ReorderableListView`) and 48 px targets. Delete with Undo snackbar everywhere.
  - Replace the fake bookmark with a quiet `SyncStatusChip` ("Saved · Backed up") under the title. Share stays one icon that opens a share *sheet* (Text / Image / Publish as tour), not a popup menu.
  - Unify banners (closed, tip, shared-edit) into `StatusBanner` variants (warning / info / tip) using theme tokens.
  - Food & cafes becomes a horizontal card rail, or rows in the same timeline at their time slots.

---

#### My Trips — `/my-trips` — `my_trips_screen.dart`
- **Job:** reopen a saved itinerary, or start a new one.
- **Layout today:** AppBar "My Trips & Itineraries" with a custom back button. A list of SoftCards, each with a "3 DAYS" pill + "FRIENDS" amber pill + optional group icon + a grey delete/leave IconButton, then title (18 sp), the line "📍 Varanasi · 12 planned stops · Balanced pace", and a 2-line overview. Extended FAB "New Trip". Pull-to-refresh.
- **States:** Loading is a centred spinner. Error is centred text that **prints the raw exception** (`'Could not load trips: $err'`, `:83`). Empty: an 80 px icon circle, "No Saved Trips Yet", copy, and an ElevatedButton "Plan Your First Trip" (`:88-147`), while the FAB still shows too (two identical CTAs). Signed-out has no hint that trips are only on this phone.
- **What works:** Correct leave-vs-delete wording for shared trips (`:21-31`). Pull-to-refresh even when empty (`:149-160`).
- **Problems:**
  - **M** Cards show no dates, no progress (stops done) and no image, so you can't tell an upcoming trip from a past one. The order isn't communicated and there's no "Upcoming / Past" grouping. Pills are 11 sp uppercase (`:196-221`).
  - **M** A destructive delete icon sits on every card, top-right (`:237-249`). Swipe-to-delete or an overflow would be calmer. The confirm button uses raw `Colors.red` (`:40`).
  - **M** Emoji in UI copy (`'📍 …'`, `:263`).
  - **M** Opens the itinerary with `Navigator.push` (`:175-179`), so a trip has no URL or deep link (it can't be opened from a notification or a shared link).
  - **L** The FAB and empty-state CTA duplicate each other (`:128-143`, `:293-301`). The title "My Trips & Itineraries" is redundant.
- **Redesign recommendation:**
  - A `TripCard` with a cover photo (first stop's photo), destination as title, date range or "No dates yet", a progress bar "5 of 12 stops", and avatars for shared members.
  - Sections: "Happening now" (a highlighted card with "Continue Day 2"), "Upcoming", "Past / undated".
  - Delete/leave moves to an overflow or swipe action with Undo.
  - Route `/my-trips/:id` for the itinerary. Title "My trips". One CTA: the FAB, hidden on empty, where the empty state carries the CTA.
  - Error: a friendly `EmptyStateCard` with Retry, no raw exception.

---

#### Trip Essentials tab — inside itinerary (last chip) — `trip_essentials_view.dart`
- **Job:** prepare for the trip: dates and weather, who's coming, budget, packing, bookings.
- **Layout today:** Five stacked SoftCards with a shared `_CardTitle` (icon + 16 sp title + trailing TextButton): Dates & weather (date range, season note, horizontal 84×104 forecast tiles), Travelling together (member chips or explanatory text, "Share/Edit" opens a friend-picker bottom sheet), Budget estimate (travellers −/+ stepper, line items, total, per-person, disclaimer), Packing checklist (progress bar + ExpansionTiles of dense checkboxes), Book stays & travel (ListTiles that open external sites).
- **States:** Forecast loading is a 2 px LinearProgressIndicator. Error and out-of-range get muted text ("opens about 16 days before"). Members loading or error is handled. Signed-out shows text only (`:335-339`). Friend picker covers loading, error and empty ("Add your travel buddy from the Social tab first", a dead end with no link, `:444-447`).
- **What works:** Good, honest content and copy. The shared `_CardTitle` keeps the cards consistent with each other. Packing progress gives a sense of completion.
- **Problems:**
  - **M** Two notions of "people". The traveller count is edited in the Budget card (`:509-538`) and members in Travelling together (`:287-397`). They don't sync and the user can't tell which matters.
  - **M** Fixed-size forecast tiles (`SizedBox(height: 104)`, `width: 84`, `:228, :236`) hold 4 lines, so they overflow at large text scale. Rain text is 10.5 sp (`:268`). Day label 11.5 sp (`:248`).
  - **M** ExpansionTiles nested inside a card with a transparent-divider Theme hack (`:644-647`). The dense `CheckboxListTile` rows (`:666-673`) are under 48 px.
  - **L** The friend-picker empty state is a dead end (`:444-447`). The friend-picker title is an inline 18 sp (`:423`). The booking subtitle is 12 sp (`:733`).
  - **L** Every card is the same weight. The most actionable item (set dates, since it unlocks weather and packing) has no visual priority.
- **Redesign recommendation:**
  - Promote this to its own top-level segment ("Essentials") with a summary row at the top: dates · weather · budget · packing %.
  - When dates are missing, show a single prominent "Add dates" card first, since it unlocks forecast and packing.
  - Merge traveller count into "Travelling together" (members + an "extra people not on Tabi" stepper) and have Budget read from it.
  - Forecast: an auto-height `ForecastStrip` component, 12 sp minimum.
  - Packing: full-width 48 px checklist rows grouped under plain sub-headers (no ExpansionTile inside a card). Friend-picker empty state links to the Social tab.

---

#### Adjust my day sheet — clock icon on itinerary — `rebalance_sheet.dart`
- **Job:** re-plan the rest of today because of late / tired / closed / rain.
- **Layout today:** Modal sheet with title "Adjust Day N" (20 sp inline), subtitle, RadioListTiles of reasons with descriptions, a "Which place is closed?" checkbox list (conditional), then a preview: "New plan: 3 stops, done by about 6:30 PM", kept stops with CircleAvatar numbers, dropped stops struck through with a red icon and explanation. Then an "Apply" FilledButton.
- **States:** Apply is hidden until a valid choice is made (good progressive disclosure). "Nothing more fits today." is handled.
- **What works:** A preview before applying, and Undo after (itinerary `:126-131`). It explains why each stop was dropped.
- **Problems:**
  - **M** The GPS fix is awaited **before** the sheet opens (`:22-24`). Tapping the clock gives no feedback for up to several seconds.
  - **L** Raw `Colors.redAccent` (`:159`). Default-themed `CircleAvatar` numbers (`:149`) don't match the itinerary's forest number badges (`itinerary_detail_screen.dart:805-834`). The Apply button isn't sticky, so it can be below the fold with many stops.
- **Redesign recommendation:** Open the sheet immediately and resolve location inside it with a small "Using your location…" line. Show reasons as large selectable cards (icon + label) in a 2×2 grid. Reuse the itinerary's `StopNumberBadge` in the preview. Use a sticky "Apply new plan" footer. Keep Undo.

---

#### Share itinerary (text / image) — share menu on itinerary — `trip_share.dart`
- **Job:** send the plan to travel mates.
- **Layout today:** Text is the native share sheet with an emoji-formatted plain-text plan. Image pushes a full page "Share as image" (`:63-67`) showing a cream card (gradient header with title, "📍 dest · days · companion", "📅 dates", then per-day time slot + place rows and "🍽️ food") and an extended FAB "Share image".
- **What works:** Real PNG export via RepaintBoundary (`:86-104`). Keeps "Planned with Tabi" branding.
- **Problems:**
  - **M** Emoji are rendered into the image (`:186, :191, :246`), so they look different on every platform and cheap in a branded asset.
  - **M** The card's width follows the device, so the exported image size and line wraps vary by phone. A 10-day plan becomes a very tall image (no limit or pagination).
  - **L** Another page pushed via `Navigator.push`. The FAB overlaps the card bottom (padding hack, `:121`). The time-slot column is fixed at 78 px (`:221-222`).
- **Redesign recommendation:** Use one shared `ShareCardSheet` pattern (also used by trip summary and poster): a bottom sheet with a fixed-size (1080×1350) preview, format toggle (Image / Text), and a primary "Share" button. Replace emoji with Material icons. For long trips show "Day 1–3" with "+N more days".

---

#### Start adventure — `/tracking` without `autostart` — `start_adventure_view.dart`
- **Job:** name the trip, understand how it counts, and press Start.
- **Layout today:** AppBar "New adventure". HeroCard: "Ready to explore" glass chip + weather chip, "NAME YOUR ADVENTURE" label (11.5 sp), an inline 24 sp editable title with underline, an optional "Heading to X · +N XP", a 128 px amber pulsing START button (205 px with rings), and "Tap to start tracking". Then a SoftCard "How your trip counts" (a 2–4 step vertical timeline: Journey / Trek / Proof photo / Finish), "What's tracked" (2×2 grid: Live route, Steps, Memories, Screen off), and a lock icon + privacy note.
- **States:** Starting shows a spinner in the button and "Starting…". Errors give a snackbar. **Location-permission denied isn't handled visually here** (it only lands in the catch-all snackbar "Could not start", `:56-62`). Offline isn't shown.
- **What works:** One unmistakable primary action. The pulse **respects reduced motion** (`:252-260`), and Semantics is on the button (`:270-273`). The timeline is the clearest XP explanation in the app, and its numbers come from `TripGuard`/`TripSplit` constants (`:435, :463-465`).
- **Problems:**
  - **H** "What's tracked → Live route · On the map" (`:593`) promises a map, but the free-exploration live screen has **no map** (see next section).
  - **H** Users starting from the planner (`autostart=1`, `stop_actions.dart:40`) skip this view entirely (`tracking_screen.dart:93-100`), so the people most likely to earn place XP never see how it counts.
  - **M** The "+100 XP completion bonus" is hardcoded copy (`:465`), but the bonus is clamped by the daily cap (`tracking_service.dart:633`). The "Journey / Trek" jargon is introduced here with no plain-language alternative.
  - **M** Raw gradient `Color(0xFFFFD166)` (`:311`), heavy amber glow shadow (`:317-323`), glass chips on the hero gradient, and two pulsing rings: it reads game-like rather than premium. The start button is a `GestureDetector` (`:300-302`), so it has no focus or keyboard activation on web.
  - **L** The title field is editable but looks like a heading (underline at 25% white, `:182-186`), so it's easy to miss. The `highlight` flag depends on the string `'Trek'` (`:490`). The privacy note is 12.5 sp muted at the bottom, and the live-location sharing choice isn't here (it's mid-trip).
- **Redesign recommendation:** Keep the single big Start, made calmer (solid amber, no rings, or one subtle ring). Put the title as a tappable "Trip name ✎" row under it. Show "How it counts" as 3 compact rows (Get there any way · Walk 200 m+ for 2 min · Photo at the place) with a "Details" link to the rules sheet. Move the live-location sharing toggle and a permission pre-check here ("Location: Allowed ✓" / "Allow location" button). Use `FilledButton`/`InkWell` semantics so it's keyboard-reachable. Show a short version of this explainer as a one-time interstitial for autostart trips.

---

#### Live trip (free exploration) — `/tracking` with an active session and no destination — `tracking_screen.dart` (+ `live_trip_card.dart`, `journey_trek_breakdown.dart`)
- **Job:** at a glance while walking: am I being counted, how far and how long, and stop when done.
- **Layout today:** AppBar (session title + "Add a memory" camera icon). A scroll area containing stacked banners: xpNotice (orange), arrival-proof card, off-route (orange), severe weather (red text on red tint) (`:161-208`). Then the **LiveTripCard** HeroCard with a phase stepper (Journey → Trek → Back as tiny 15 px icon pills, label only on the current one) + "+N XP" badge, a phase message (18 sp: "Trek starts in 350 m" + progress bar + 12.5 sp explanation), and the `JourneyTrekBreakdown`: two tiles (JOURNEY / TREK, 26 sp distance, time, steps, 11.5 sp hint), a time-share bar + "x% of your moving time was trek" (11.5 sp), and chips "Total trip: 12 min" and "Trek difficulty: Easy". Then a row of memory pills, a "Share live location with friends" SwitchListTile card, a "Checkpoints" SectionHeader (21 sp), and checkpoint cards or an EmptyStateCard. Pinned at the bottom: **Discard | Pause | Finish** (three equal-width buttons).
- **States:** Paused is only the Pause/Resume label swap; the card isn't dimmed and no "Paused" status shows. GPS lost / weak accuracy isn't surfaced. Permission revoked mid-trip isn't shown. Steps are shown only once the sensor reports (good). Auto-start loading is a lone 150 px shimmer with no text (`:713-714`).
- **What works:** The pinned controls are separate from the scroll. The phase message with distance to trek start is the right idea. The same breakdown widget is reused live, in the summary and in the journal, so the numbers agree.
- **Problems (glanceability):**
  - **H** No single hero metric. Elapsed time, the thing walkers glance for, is a 12.5 sp chip ("Total trip:", `journey_trek_breakdown.dart:97-103`) below two competing 26 sp distances. The counting status ("am I trekking?") lives in a 15 px icon pill whose label only shows for the current step (`live_trip_card.dart:171-186`).
  - **H** **Discard has no confirmation** and sits leftmost, the same size as Finish, in red (`tracking_screen.dart:346-348, :827-839`). One mis-tap while walking wipes the trip.
  - **H** No map on this screen (`:134-365` has no FlutterMap), despite the start screen's "Live route · On the map" promise.
  - **H** Free exploration always shows a "Checkpoints" header plus an EmptyStateCard "No checkpoints for this adventure". Checkpoints come only from a destination (`:89-91`), and destination trips go to the navigation view (`:112`), so this block is effectively always empty (`:223-236`).
  - **M** Up to four stacked banners above the card (`:161-208`) push the live stats below the fold. Orange and red are raw `Colors.orange/red` (`:163, :180, :194, :198`). The weather banner uses red text on a red tint.
  - **M** The arrival flow is a modal chain: auto AlertDialog (`:369-411`) + duplicate inline proof card (`:173-177`) → camera → "You made it!" AlertDialog (`:442-499`) → summary AlertDialog (`:501-571`) → share sheet. That's four modal surfaces in a row while the user is standing at a landmark.
  - **M** Live-location sharing (a privacy decision) is a mid-scroll switch (`:574-610`), dense, with a 2-line subtitle.
  - **M** Small text on the dark hero: 11.5 sp hints at white 70–82% (`journey_trek_breakdown.dart:294, :361`), and 12.5 sp at white 75% (`live_trip_card.dart:247-251`). Phase steps signal done / later state by white alpha only (`live_trip_card.dart:138-147`), so meaning is colour-only. The XP badge shows "+0 XP" at start (`live_trip_card.dart:213`).
  - **M** Memory pills are non-interactive and all read "Photo", "Photo", "Photo" (`:631-648`).
  - **L** The body has no SafeArea bottom (`:154`), so it relies on `AppSpacing.page` 24 px. The `_TileStyle` matrix defines four bespoke gradient/glass styles with a raw shadow (`journey_trek_breakdown.dart:152-214`). The challenging/hard colours are hex (`:417-418`).
- **Redesign recommendation:**
  - Top half is a **live map** with the route so far and your position (reuse the heatmap's polyline styling). A compact **status pill** overlays it: "● Counting your trek" (green) / "Getting there — not counted yet" (neutral) / "Paused" (amber) / "GPS weak" (red), in text and colour.
  - Bottom sheet "LiveStatsPanel": one hero number (elapsed time, 40+ sp, tabular figures), then two secondary stats (trek distance, steps) at 22–24 sp, then XP earned. Journey vs trek detail stays in an expandable section, not the default view.
  - Controls: a large Pause/Resume (72 px circle) and a "Finish" slide-to-confirm or long-press. Move **Discard into Finish's flow** ("Finish" → summary with "Discard trip" as a text link and confirm).
  - Banners: at most one at a time, via a `StatusBanner` with priority (proof photo > GPS/mock flag > weather > off-route).
  - Arrival: one non-blocking bottom sheet "You're at X — take a photo for +50 XP" with Camera / Later. On success, a celebratory inline toast with an XP count-up, not a dialog.
  - Remove the Checkpoints section for free exploration. Memories become a thumbnail strip with a "+" tile. Move the live-sharing toggle to the start screen, with a small "Sharing live" chip here.

---

#### Trip summary dialog & "Trip not counted" checklist — after Finish — `tracking_screen.dart:501-571`, `trip_not_counted_checklist.dart`
- **Job:** celebrate a counted trip, or explain why it didn't count, then share.
- **Layout today:** An AlertDialog titled "Adventure Complete" / "Trip not counted". If unverified, an orange checklist card (✓/✗ rows: ≥200 m, ≥3 min, authentic GPS, started far enough, live photo) + an underlined "How XP works →" link that opens a rules sheet (5 rules + "Got it"). Otherwise the amber xpNotice text. Then the full JourneyTrekBreakdown (light variant), then "XP earned: N" as a plain bold line. Actions: "Share Card" (Outlined) and "Done" (Filled).
- **What works:** Explaining failure with a checklist is the right pattern. "How XP works" is reachable.
- **Problems:**
  - **H** **The XP rules shown contradict the code.** The modal says "Minimum 200 m & **3 minutes**" (`trip_not_counted_checklist.dart:57-58`), the checklist tests `trekSeconds >= 180` (`:146`, label `:188`), but `TripGuard.minCompletionSeconds = 120` (`trip_guard.dart:93`). The start screen correctly says 2 minutes (`start_adventure_view.dart:463-464`). The modal says start "**150 m**" away (`:64`) vs `minStartDistanceMeters = 100` (`trip_guard.dart:82`). It says a daily cap of "**500 XP**" (`:76`) vs `dailyTripXpCap = 1500` (`tracking_service.dart:157`). Users get told they failed a rule they met.
  - **H** Checklist rows come from substring-matching the notice text (`:144-149`). `'confirmation photo'` appears nowhere else in `lib/`, so the "Live photo taken at destination" row can never show (`:199-200`). The checks break whenever copy changes.
  - **M** The reward moment is a stock AlertDialog that crams two IntrinsicHeight tiles + bar + chips into dialog width (`tracking_screen.dart:537-540`). XP, the headline, is the last and plainest line (`:542-548`). There's no confetti or animation.
  - **M** Raw `Colors.orange`, `Colors.red.shade600/800` (`trip_not_counted_checklist.dart:155-157, 245, 255`). The underlined link text is 12.5 sp with a small hit area (`:204-230`). Rules copy is long paragraphs (`:52, :70`).
- **Redesign recommendation:** A full-screen **TripSummaryScreen** (route) with a map of the route, a big XP count-up, three `StatTile`s (time, trek distance, steps), then the journey/trek detail collapsed. Primary "Share", secondary "Done", with "Discard" as a tertiary link. For not-counted trips, the hero becomes "Didn't count this time" with the checklist built from **structured `XpDenial` values** (not string matching) and thresholds read from `TripGuard`/`TripSplit`/`TrackingService` constants. Rewrite the rules sheet to pull every number from those constants, and reuse it from the start screen.

---

#### Trip share sheet — "Share Card" in summary — `trip_share_sheet.dart`
- **Job:** post the finished trip.
- **Layout today:** A transparent modal sheet with a white container: "Share Adventure" header + close icon (no tooltip, `:88-91`), a dark gradient TripShareCard (TABI logo, date, title, "Adventure Completed", stat row Trek/Duration/Steps/XP, tagline), then "Copy Share Text" FilledButton and the tip "Take a screenshot of the card above…".
- **Problems:**
  - **H** No image export. It tells the user to screenshot (`:115-119`), while the itinerary share (`trip_share.dart:86-104`) and poster (`poster_screen.dart:39-55`) already export PNGs through the native share sheet. The only action copies emoji text plus hashtags to the clipboard (`:26-53`), with no native share.
  - **M** Dead dark-mode branch with a hex colour (`:58-62`, the app has no dark theme). The card gradient is hex `0xFF1E3A2F/0xFF0F1E19` (`:147`), not tokens. The tagline is 11 sp at 45% white (`:264-269`), so contrast fails. Stat labels are 11 sp (`:314`).
  - **L** "Adventure Completed" / "Real-World Exploration · Discover Hidden Gems" is generic marketing copy. There's no route shape on the card, which would make it personal.
- **Redesign recommendation:** Merge into the shared `ShareCardSheet`. The card shows the route line-art (reuse `_RoutesPainter` from the poster), title, date, three stats and the Tabi wordmark at a fixed 4:5 size. Primary action "Share image" (native sheet), secondary "Copy text".

---

#### Exploration heatmap — `/heatmap` — `heatmap_screen.dart`
- **Job:** see everywhere you've walked, then make a poster.
- **Layout today:** AppBar "My exploration map". A full-bleed dark-tinted OSM map fitted to all routes, with glowing amber polylines. A bottom overlay with a black 60% pill "N trips · X km on foot" and an amber FilledButton "Create poster".
- **States:** Loading is a spinner. Error shows an EmptyStateCard **without Retry** (`:27-36`). Empty shows an EmptyStateCard "No routes yet" **without a CTA** to start a trip (`:38-50`).
- **What works:** Strong, distinctive visual. One clear primary action. Minimal chrome.
- **Problems:**
  - **M** Empty and error are dead ends (`:30-34, :42-48`). Add "Start a trip" / "Try again".
  - **L** The poster is opened with `Navigator.push` (`:118-122`). `Positioned(bottom: 40)` + `SafeArea` double-offsets the overlay (`:81-85`). The amber CTA is a hand-styled `FilledButton` (`:109-117`) rather than `AmberPillButton`. Hex glow `0xFFFFB347` (`:12`). The light app bar over a dark map is a visual seam. There's no filter (city / time range) and no tap-on-route to open that trip.
- **Redesign recommendation:** Use a transparent/dark app bar over the map for an immersive look. Put stats in a bottom card using `StatTile`s (Trips · km · cities). Primary `AmberPillButton` "Create poster". Empty state with a "Start an adventure" CTA. Later: tap a route to open its journal entry.

---

#### Route poster — pushed from heatmap — `poster_screen.dart`
- **Job:** pick a palette and share a route-art poster.
- **Layout today:** AppBar "Your poster". Palette ChoiceChips (colour-dot avatars), the 4:5 poster (routes painted as line-art, NAME, "EXPLORED ON FOOT", KM / TRIPS / CITIES stats, TABI), and an extended FAB "Share poster".
- **What works:** A real 4× PNG export (`:18, :42`). Clean typographic poster. A palette picker with live preview.
- **Problems:**
  - **M** The poster is fixed at `width = 360`, `height = width*5/4` (`:129, :148-149`) inside 16 px list padding. On a 360 dp phone the available width is 328, so it's squeezed to 328×450 and **the exported aspect isn't 4:5**.
  - **L** Poster text at 9–10 sp (`:172, :213`) is fine in print but unreadable in the on-screen preview. The name comes from the display name or "Explorer" with no way to edit it. The FAB overlaps the poster's bottom (`:74` 100 px padding hack). The palette chips `Wrap` has no `runSpacing` (`:76-78`).
- **Redesign recommendation:** Render the poster at a fixed logical size inside a `FittedBox` (preview scales, export stays 1440×1800). Put palette swatches as a horizontal row of 48 px colour circles under the preview. Add an editable name line. Use a sticky bottom bar with "Share" (primary) and "Save to photos" (secondary).

---

### Cross-screen patterns in this group
- **XP rules have no single source of truth.** Numbers appear as hardcoded copy in `trip_not_counted_checklist.dart:57-76, 145-149, 183-200` and `start_adventure_view.dart:465`, and they disagree with `TripGuard`/`TrackingService`. Introduce `XpRules` (all thresholds) and a `XpRulesSheet` + `XpRuleRow` used by the start screen, live status, summary and profile.
- **Imperative navigation everywhere:** itinerary (`trip_planner_screen.dart:179`, `my_trips_screen.dart:175`), image share (`trip_share.dart:64`), poster (`heatmap_screen.dart:118`), camera (`tracking_screen.dart:416`). Add routes `/my-trips/:id`, `/my-trips/:id/essentials`, `/tracking/summary/:id`, `/heatmap/poster` so back behaviour and deep links are predictable.
- **Three share implementations:** itinerary image (PNG), poster (PNG), trip card (screenshot + clipboard). Build one `ShareCardSheet` (fixed-size `RepaintBoundary` preview + Share image / Copy text).
- **Ad-hoc banners:** closed-stop, day tip, xpNotice, off-route, weather, not-counted all hand-roll tinted containers with raw or hex colours. Create a `StatusBanner(kind: info|tip|warning|error|success)` with token colours and an optional action.
- **Dialogs for flow steps:** regenerate, arrival prompt, arrival success, trip summary, delete trip are all AlertDialogs. Use sheets or inline confirm + Undo. Reserve dialogs for truly destructive confirmation (delete shared trip, discard trip).
- **Section headers re-styled inline** (16 sp w800 ×9 in the planner, ×2 in the itinerary, 17 sp in start view, 16 sp `_CardTitle`), while `SectionHeader` (21 sp) is used once on the live screen. Define two levels: `SectionHeader` (page) and `CardHeader` (in-card, icon + title + trailing action).
- **Micro-text below 12 sp** in pills and chips (10.5–11.5 sp): itinerary time slot, hours chips, forecast, My Trips pills, breakdown hints, share card labels. Set a 12 sp floor and a `AppPill`/`MetaPill` size scale.
- **Tiny touch targets:** `constraints: BoxConstraints()` icon buttons (itinerary reorder/remove), dense checkbox tiles, underlined text links. Enforce 48 px via a shared `AppIconButton` that always has a tooltip.
- **Two different "stop number" badges** (map marker 32 px, card badge 26 px, rebalance CircleAvatar). Create one `StopNumberBadge(state: next|pending|done)`.
- **Emoji in rendered UI** (`my_trips_screen.dart:263`, `trip_share.dart:186, 191, 246`). Replace with icons. Emoji are acceptable only in copied plain text.
- Suggested new components: `ChoiceGroup` (single-select with description), `TripCard`, `StopTimelineRow`, `DaySelector`, `SyncStatusChip`, `LiveStatusPill`, `LiveStatsPanel` (hero metric + 2 secondaries), `HoldToConfirmButton`, `TripSummaryScreen`, `ForecastStrip`.

### Quick wins
1. Make every number in the "How XP works" sheet and checklist read from `TripGuard.minCompletionSeconds` (2 min), `TripGuard.minStartDistanceMeters` (100 m) and `TrackingService.dailyTripXpCap` (1500). Fix `trekSeconds >= 180`. Files: `trip_not_counted_checklist.dart:57-58, 64, 76, 146, 188`.
2. Add a confirm (or Undo snackbar) to **Discard** and move it out of the primary button row: `tracking_screen.dart:346-348, 827-839`.
3. Hide the "Checkpoints" header and empty state when there are no checkpoints: `tracking_screen.dart:222-236`.
4. Make the elapsed time the largest number on the live card (move "Total trip" out of the 12.5 sp chip): `journey_trek_breakdown.dart:97-103`, `live_trip_card.dart:47-66`.
5. Give the itinerary's reorder and remove icons 48 px hit areas and add Undo to remove: `itinerary_detail_screen.dart:868-909, 212-214`.
6. Make the planner's Generate button sticky (`bottomNavigationBar`) so it's visible from the first screen: `trip_planner_screen.dart:629-662`.
7. Replace the push to the itinerary after generation with `pushReplacement` so Back doesn't return to the form and allow a duplicate generation: `trip_planner_screen.dart:179-183`.
8. Wrap the itinerary's sticky "Go to stop" bar in `SafeArea`: `itinerary_detail_screen.dart:1076`.
9. Turn the amber bookmark/cloud *button* into a non-interactive status chip: `itinerary_detail_screen.dart:385-402`.
10. Add "Start a trip" and "Try again" actions to the heatmap empty and error states, and stop printing raw exceptions in My Trips: `heatmap_screen.dart:30-48`, `my_trips_screen.dart:81-86`.


---

## UI audit D: Passport tab, gamification, journal, memories

Scope read in full: profile_screen, achievements_screen, rank_frame, rank_rewards_card, passport_book_screen, passport_stamps_card, stamp_view, journal_screen, calendar_screen, adventure_detail_screen, memories_gallery_screen, camera_screen, media_review, memory_capture, memory_viewer, memory_widgets, voice_recorder_widget, community_memories_screen. Supporting reads: `profile/domain/explorer_level.dart`, `profile/domain/rank_style.dart`, `locations/data/location_repository.dart:156-191`, `locations/data/location_seed.dart`, `core/theme/components.dart` (StatTile, AppAvatar, MetaPill), `core/theme/app_theme.dart` (AppBar/FAB theme). `capsule_sheet.dart` is in the memories folder but was not in my scope, so I did not audit it.

Paths below are relative to `lib/features/` unless they start with `lib/`.

---

### The gamification model, as the user sees it (read this first)

On one screen (Passport tab) the user meets **seven separate progress systems**, and none of them says how it relates to the others:

| # | System | Where it shows | Unit |
|---|---|---|---|
| 1 | Level number | Hero "Level 11 · Explorer" `profile/profile_screen.dart:361` | `xp/100 + 1` (`profile/domain/explorer_level.dart:39-41`) |
| 2 | Level progress bar | Hero amber bar, "64 XP to Level 12" `profile_screen.dart:386-407` | fills every 100 XP |
| 3 | Rank title / tier | Same hero line, plus Rank rewards on Achievements | 7 tiers at 0/1k/2.5k/6k/12k/25k/50k XP (`profile/domain/rank_style.dart:30-78`) |
| 4 | Total XP | Hero "X XP" (`:378`) **and** the 4th StatTile "Total XP" (`:447`) | XP |
| 5 | Achievement stars | `_AchievementsCard` "n / N stars" + "XP waiting" (`:500-524`) | bronze/silver/gold stars, which are claimed for bonus XP |
| 6 | Passport stamps | `PassportStampsCard` "n cities stamped" | cities |
| 7 | Regional exploration | Every neighbourhood, city, district, region and country as a % bar (`:217-233`) | places discovered / total |

Not shown here: the **streak** (only on Home, `home/home_screen.dart:336` `StreakFlameBadge`) and the **heatmap** (a plain link row, `:137-164`).

Coherence bugs that surface in the UI:
- **The level number and the tier title come from different scales.** The tier table says Explorer = level 5 (`explorer_level.dart:14`), but `levelNumberForXp` gives level 11 at 1,000 XP (`:39-41`). So the hero reads "Level 11 · Explorer", and "Level 20 · Pathfinder" appears at about 1,900 XP while Pathfinder needs 6,000 XP. A user cannot form a mental model from that.
- **XP appears 3 times above the fold** (hero total, hero "to next level", StatTile "Total XP") and a 4th time as "XP waiting". On Adventure detail it appears 3 times (see that section).
- The **bar fills every 100 XP**, so it is meaningless at higher totals: a 25k-XP user still sees a bar that resets every 100 XP. The bar that matters (progress to the next rank, which unlocks a frame) lives only in text on another screen (`profile/rank_rewards_card.dart:31-34`).
- **Rank rewards** (cosmetic frames and trail colours) are hidden on the Achievements screen (`achievements_screen.dart:112`), although they belong to rank, not to achievements.

**Recommended model for the redesign:** one primary meter (Rank: a named tier, with a bar to the next tier and a preview of its reward). Show XP only as the currency that feeds it. Drop the per-100 "level number", or rename it "Lv" and derive it from the tier table so the two never disagree. Show Achievements, Stamps and Regions as three equal **collections** ("Collections: 12/45 stars · 3 stamps · 18% of Chandigarh"). Bring the streak in as a small chip in the hero. One hero, one meter, one "collections" row.

---

#### Passport (profile) — tab `/passport` — `profile/profile_screen.dart`
- **Job:** see "how far have I come", then jump into a collection (achievements, stamps, map) or a past trip.
- **Layout today:** 36 sp inline title "Passport" with 2 RoundIconButtons (Journal, Preferences) → HeroCard (RankFrame avatar, name, "Level N · Title", "X XP" / "Y XP to Level N+1", amber bar) → 4 StatTiles (Adventures, Trekked, Steps, Total XP) → SectionHeader "Achievements" → Achievements SoftCard (with a fake "Claim" pill) → Stamps SoftCard → "My exploration map & poster" SoftCard → SectionHeader "Regional Exploration" → one SoftCard per neighbourhood, city, district, region and country → SectionHeader "Recent Adventures" → SoftCard rows.
- **States:** loading uses a skeleton, but it shows 3 stat tiles where the real screen has 4 (`:625-633`). The error state shows the raw exception `'$error'` (`:102`, `:205`). The regional empty state is gated on `cities.isEmpty` (`:208`), which only happens when the DB has no locations at all. A new user therefore sees about 24 cards at "0.0% explored" instead of the empty state. There is no signed-out state; the page renders the same.
- **What works:** the RankFrame ring is a nice, non-numeric status signal. FadeSlideIn staggering is subtle. Pull to refresh works.
- **Problems**
  - **H** Seven progress systems compete on one scroll, and XP is repeated (see the model section above). `:361`, `:378`, `:386`, `:447`, `:513`.
  - **H** Regional Exploration dumps every group, including undiscovered ones (`location_repository.dart:170-190`), with **no level labels**. With the seed data, "Chandigarh" appears 3 times with identical numbers (city, district, region; `location_seed.dart`), then "India". The block holds 14 neighbourhood cards (amber bars) before the cities (emerald bars), and the colour meaning is unexplained (`:219-232`, `:598`). Roughly 24 cards push Recent Adventures far below the fold.
  - **H** Level number and tier disagree ("Level 11 · Explorer"; `explorer_level.dart:14` vs `:39`).
  - **M** The "Claim" pill (`:528-543`) looks like a button but is a Container; tapping anywhere navigates. That is fine, but it should look like a badge, or claiming should happen inline.
  - **M** 4 StatTiles in a row: on a 360 dp phone each tile has about 44 dp of content, so `FittedBox` shrinks values like "12.4 km" to about 14 sp while "3" stays at 24 sp. The tiles look uneven (`:423-449`, `lib/core/theme/components.dart:705-715`). "Trekked" and "Steps" overlap in meaning.
  - **M** Memories (gallery) is not reachable from this tab; it is only on Home quick links (`home/home_screen.dart:519`). The Journal hides behind an unlabeled book icon (`:80-84`), and Preferences (a settings item) sits next to it in the header (`:86-90`).
  - **M** Recent adventure rows open with an imperative `Navigator.push(MaterialPageRoute)` (`:258-263`) although `/journal/:id` exists (`lib/core/router/app_router.dart:261-270`). The calendar uses the route (`journal/presentation/calendar_screen.dart:703`), so the screen stack and deep links behave inconsistently. Every row shows the same generic green `Icons.forest` tile (`:267-279`), which looks like a placeholder.
  - **M** Copy: "km trek" and "Trekked" are jargon (`:297`, `:435`). The relative date never switches to an absolute date (`:317-323`: "143 days ago").
  - **L** 13 inline `fontSize`s, the title at 36 sp is inline (`:70-78`) instead of a theme text style, and the RegionRow text is 12 sp (`:605`).
  - **L** No reduced-motion handling for FadeSlideIn or the 900 ms bar tween (`:110-127`, `:398-401`).
- **Redesign recommendation**
  - Header: "Passport" in the theme `headlineLarge` style, with a single overflow/settings button. Move Preferences to a Settings entry.
  - Hero = identity + **one rank meter**: avatar in RankFrame, name, rank title, "1,240 / 2,500 XP to Adventurer", and the next reward's frame shown as a small preview. Add a streak chip in the hero corner. Remove the per-100 level number or fix it to the tier table.
  - Replace the 4 StatTiles with 3 lifetime stats in one compact row (Trips · Distance · Places). Drop "Total XP", which the hero already shows.
  - Add a "Collections" section: a horizontal 3-card row (Achievements stars with a claim badge, Stamps with the latest stamp thumbnail, Map/poster), using one `CollectionTile` component.
  - "Exploration" section: show only the user's current city as a single `ProgressRow` with a "See all regions" link to a dedicated screen with grouped headers (Neighbourhoods, Cities, …) that hides 0% groups by default.
  - Recent trips: 3 rows using a shared `TripListTile` (map thumbnail, title, date, distance), then "Open journal →". Use `context.push('/journal/$id')`.
  - Add a "Memories" entry (latest 4 thumbnails) so the tab is the single home for "my stuff".

#### Achievements — `/achievements` — `profile/achievements_screen.dart`
- **Job:** see which achievements are close, and claim earned stars for XP.
- **Layout today:** AppBar "Achievements" → HeroCard (trophy icon, "n / N stars", "X XP ready to claim") → **RankRewardsCard** (7 style rows) → one SoftCard per achievement (gradient icon disc, title, next-target description, 3 stars, progress bar, "x/y" label, "Next: +N XP", optional amber "Claim +N XP" button) → claim opens an AlertDialog with elastic stars, an amber "+XP" pill, "Level up!" text and an "Awesome!" button.
- **States:** shimmer loading. The error state shows the raw `'$error'` (`:48`). There is no empty state (an empty list would show "0 / 0 stars"). A claim failure shows the raw exception in a SnackBar (`:156`).
- **What works:** claimable items sort first (`:59-62`). The per-card progress bar, the bronze/silver/gold star metaphor and the claim loading state are all clear. The reward dialog is a good moment of delight.
- **Problems**
  - **H** RankRewardsCard sits **between** the summary and the achievement list (`:112`). That puts about 7 × 56 dp of cosmetic-frame rows above the first achievement, so the claim CTA is below the fold on most phones. It belongs to Rank (Passport hero), not here.
  - **M** Three button styles in one flow: an amber `FilledButton` override for Claim (`:275-298`) instead of `AmberPillButton`, the default forest `FilledButton` "Awesome!" (`:391-397`), and a plain Container pill on Passport. Colours are hardcoded: `_bronze`, `_silver`, `_gold` (`:11-13`), `Colors.grey.shade400/500` for locked icons and stars (`:183`, `:223`).
  - **M** Colour-only meaning: earned and unearned stars differ by colour plus filled/outline (acceptable), but the icon disc is grey vs green with no label (`:182-184`). The stars have no Semantics ("2 of 3 stars").
  - **M** A dialog is used for the reward (`:150-153`). "Awesome!" copy is juvenile, and the elasticOut tween ignores reduced motion (`:322-327`).
  - **L** The 12.5 sp labels (`:254`, `:264`) and the 13 sp description in muted ink on a SoftCard are borderline. The "Next: +N XP" and progress labels compete on one line.
- **Redesign recommendation**
  - Summary header (not a HeroCard): "18 of 45 stars", plus a sticky "Claim all (+350 XP)" AmberPillButton when anything is claimable.
  - Group into "Ready to claim", "In progress" and "Completed" sections. Completed rows collapse to a compact one-line `AchievementTile`.
  - The card shows icon, title, a "Walk 25 km" target, a single bar and a stars cluster. Move the reward amount into the claim button only.
  - Move Rank rewards to a "Rank & styles" sheet opened from the Passport hero.
  - Replace the AlertDialog with a bottom-sheet or overlay celebration (stars animate into the XP total) that respects `MediaQuery.disableAnimations`. Copy: "Nice work". Button: "Continue".

#### Rank rewards card + RankFrame — inside Achievements; frame on the Passport hero — `profile/rank_rewards_card.dart`, `profile/rank_frame.dart`
- **Job:** pick which unlocked frame and trail colour to wear, and see what the next rank unlocks.
- **Layout today:** SoftCard titled "Rank rewards", a sentence about XP to the next style, then 7 InkWell rows (framed sample avatar, title, trail swatch 22×6, "Frame + trail colour" or "N XP (M to go)", check or lock icon).
- **States:** returns `SizedBox.shrink()` while loading or on error (`:18`), so the card silently disappears. Equipping gives SnackBar feedback.
- **What works:** previewing each frame on an avatar is the right idea; the tap-to-equip interaction is simple.
- **Problems**
  - **M** The sample avatar is hardcoded `'E'` (`rank_rewards_card.dart:86`) instead of the user's initial, so it doesn't feel like "you".
  - **M** Locked rows use `Opacity(0.5)` (`:78-79`), which halves the contrast of the very text that tells the user what to do ("N XP to go"). The 12 sp caption (`:112`) has no explicit colour.
  - **M** The trail swatch is a 22×6 px bar (`:99-106`) and the meaning of "trail colour" is never explained. That is jargon.
  - **L** RankFrame stacks 4 rings: sweep-gradient ring, white ring (`rank_frame.dart:22-35`), AppAvatar's own white border and drop shadow (`lib/core/theme/components.dart:80-90`). It looks busy and template-like. Some tier gradients are rainbow-like (`rank_style.dart:59-63`).
  - **L** Text styles have no colour or token (`:25-27`, `:95`); it is the only card in scope that relies on defaults.
- **Redesign recommendation:** a "Rank & styles" sheet with a horizontal carousel of large framed avatars (the user's own initial or photo) and a map-line preview for the trail. Locked items show a lock badge at full contrast with "Unlocks at 2,500 XP". Simplify RankFrame to one 3 dp ring plus the avatar, with no extra white ring or shadow.

#### Passport stamps card (entry) — on Passport — `passport/presentation/passport_stamps_card.dart`
- **Job:** jump to the stamp book; see the count and the latest city.
- **Problems:** **L** It is the same 52 px-disc + title + subtitle + chevron SoftCard pattern that `_AchievementsCard` and the heatmap row (`profile/profile_screen.dart:137-164`) hand-build separately, with three different icon treatments (amber disc, green disc, bare icon). **L** "Latest" relies on list order (`:21`). **L** Shows "Loading…" text instead of a skeleton (`:18`).
- **Redesign recommendation:** fold it into a `CollectionTile` that shows the latest real `StampView` at 56 dp as its thumbnail. The stamp is the most premium asset in the app, so show it rather than a generic icon.

#### Passport book — `/passport-stamps` — `passport/presentation/passport_book_screen.dart` (+ `stamp_view.dart`)
- **Job:** admire collected city stamps; open one and share it.
- **Layout today:** AppBar "Passport stamps" → "N cities stamped" muted text → parchment container (#F6EEDC) with a 2-column grid of 140 px tilted StampViews → tap pushes `_StampDetailScreen` (parchment card with a 220 px stamp, city/state, date, serial, "Tabi Explorer Passport", then "N places reached" with plain ListTiles, and an extended FAB "Share stamp").
- **States:** a bare `CircularProgressIndicator` while loading (`:33`), unlike the shimmer used elsewhere. The error state has **no retry** (`:34-43`). The empty state copy ("with the live photo", `:52`) is fine but has no CTA. Share failure goes to a SnackBar.
- **What works:** `StampView` (category ink colours, stable tilt, dotted ring, good Semantics label `stamp_view.dart:54-58`) is the most distinctive, premium element in the app; keep it. Rendering the share image through RepaintBoundary is good.
- **Problems**
  - **M** The grid is a fixed `crossAxisCount: 2` (`:79`) with a 140 px stamp (`:92`). On tablet or web the cells are huge and the stamps float; on 320 dp the stamps get clamped. Use `maxCrossAxisExtent`.
  - **M** The detail opens with an imperative `MaterialPageRoute` to a private widget (`:86-89`), so it has no route and no deep link for sharing.
  - **M** The "places reached" list is unstyled default `ListTile`s (`:204-209`), unlike the SoftCard rows everywhere else. The FAB overlaps the last tile on short lists.
  - **L** Stamp micro-text is 7 / 8 / 8.5 sp before FittedBox scaling (`stamp_view.dart:80`, `:103`, `:110`), so it renders at about 6.5 px at size 140. That is acceptable as artwork, because Semantics carries the content, but don't rely on it for information. The parchment colour is a file-local constant (`:19`) rather than a theme token.
  - **L** The book has no structure: no grouping by state or year, and no "next stamp" teaser.
- **Redesign recommendation:** a "passport page" layout. Group the stamps by state with a small header. Use a responsive grid (`maxCrossAxisExtent: 170`). Add a summary strip at the top ("3 cities · 2 states · since Mar 2026"). Make the detail a real route `/passport-stamps/:cityId` with a Hero transition of the stamp. Move Share to a top-bar action plus a primary button under the card, and list the places with the shared `PlaceListTile`. Add a press-in "stamp" animation the first time a new stamp is viewed (respecting reduced motion).

#### Adventure Journal (list) — `/journal` (Passport header icon) — `journal/presentation/journal_screen.dart`
- **Job:** browse past trips and open one.
- **Layout today:** AppBar "Adventure Journal" + a calendar IconButton → a flat list of SoftCard rows (status-coloured icon tile, title, "date • x km trek • +N XP", chevron).
- **States:** shimmer loading. The error state shows the raw `'$error'` (`:62`). The empty state duplicates itself ("No adventures yet" / "No adventures recorded yet.", `:76-77`) and has **no CTA** to start a trip.
- **What works:** pull to refresh, staggered entry capped at 5 items (`:92`), and a clean row anatomy.
- **Problems**
  - **M** Status is conveyed by icon colour alone, and the icons (check, play, pause, cancel, `help_outline`) are ambiguous. "Unverified" shows a question mark with no text (`:162-189`). Users can't tell "not counted" trips apart; the calendar sheet does show a "Not counted" pill (`calendar_screen.dart:654-673`).
  - **M** No grouping by month or week and no thumbnails or route previews, so after 20 trips it is an undifferentiated list. The limit is hard-coded at 100 with no pagination (`:16`).
  - **M** Uses an imperative push (`:97-102`) instead of `/journal/:id`. The row widget is a copy of Passport's recent-adventure row (`profile/profile_screen.dart:254-311`).
  - **L** Mixed date formats: "Today / 3 days ago / 12/5/2026" (`:191-198`). Day/month ordering is ambiguous for India (d/m) vs US readers. "km trek" is jargon.
- **Redesign recommendation:** merge Journal and Calendar into one "Journal" screen with a List | Calendar segmented control in the app bar. The list is grouped by month with sticky headers. Each `TripListTile` gets a 56 dp static route thumbnail or the cover memory photo, the title, "Sat 12 Apr · 4.2 km · 1 h 10 m", and a text status chip ("Not counted", "In progress") only when it isn't a normal completed trip. Hide XP from rows. The empty state gets a "Start a trip" button.

#### Calendar — `/calendar` (from Journal and Memories app bars) — `journal/presentation/calendar_screen.dart`
- **Job:** find what happened on a given day: trips and memories.
- **Layout today:** AppBar "Calendar" (+ "Today" TextButton when away from the current month) → month header (prev/next RoundIconButtons, month name 24 sp, year) → HeroCard summary (Trips, Trekked, Memories, Active days) → SoftCard with weekday initials, a 7-column grid of day cells (photo cover if any, emerald tint for trip days, amber border for today, up to 3 emerald dots plus 1 amber dot) and a legend → hint text "Tap a day…". Tapping a day opens a DraggableScrollableSheet: weekday, date, trip cards (title, time range, JourneyTrekBreakdown, XP pill, "Trip details") and a memories grid.
- **States:** the loading spinner sits inside the card. The **error state is missing**: `daysAsync.value ?? {}` (`:73`) silently shows an empty month when loading fails. Empty day → EmptyStateCard in the sheet. Future days are dimmed and disabled.
- **What works:** this is the best-crafted screen in the group. Photo-covered day cells are delightful. Semantics labels per day (`:343-353`) are good. Swipe between months, future months are blocked, and the legend is present.
- **Problems**
  - **H** No error UI (`:73`, `:111-128`).
  - **M** The 6 px dots are the only trip/memory signal on photo days (the emerald tint is hidden under the photo, `:363-389`). It is colour-only for sighted users, and the dots' white borders are 0.8 px (`:446`).
  - **M** The HeroCard summary labels are 11.5 sp at 78 % white (`:229-231`). "Trekked" is jargon. The hero competes with the month header for the top of the screen.
  - **M** "Trip details" is a `TextButton` inside a `FittedBox(scaleDown)` (`:698-707`), so it can shrink below 48 dp. Its pop-then-push (`:702-703`) is a back-navigation surprise: Back returns to the calendar with the sheet closed.
  - **L** The weekend letters are amber (`:268`), which adds meaningless colour. The "Not counted" pill uses raw `Colors.orange` (`:661`). The next-month button is dimmed with `Opacity` (`:191-197`) instead of the disabled style. Month and day names are hardcoded English arrays (`:17-24`) instead of `intl`.
  - **L** The "Tap a day…" hint (`:135-140`) is a crutch; the cells should look tappable.
- **Redesign recommendation:** keep the grid and photo cells. Move the month summary under the grid as a plain stats row (no HeroCard). Show the month and year in the app bar title with chevrons beside it. Replace the dots with a small count badge ("2") plus a camera glyph for memory days. Add error and retry states. In the day sheet, make "Open trip" a full-width tonal button. Make the Journal list and Calendar one screen (see above).

#### Adventure detail — `/journal/:id` (also pushed imperatively) — `journal/presentation/adventure_detail_screen.dart`
- **Job:** relive one trip: route, stats, checkpoints, memories; possibly share it.
- **Layout today:** AppBar "Adventure Journal" → HeroCard (title, date, amber "+N XP" MetaPill) → SoftCard JourneyTrekBreakdown → full-width StatTile "XP earned" → a "Route Map" SectionHeader with a FilledButton "Replay Route" → a 220 px non-interactive FlutterMap (white 3 px border, shadow) → "Checkpoints" SoftCard rows (check icon, name, "+N XP") → "Memories" header → MemoriesGrid or an EmptyStateCard.
- **States:** skeleton loading. The error state shows the raw `'$error'` (`:95`). A not-found state exists. Memories empty state is present.
- **What works:** the replay animation with the person marker is a lovely idea. The map auto-fits to the route bounds.
- **Problems**
  - **H** The default map is wrong before a replay. The full route is drawn at **30 % alpha** (`:402`), the finish flag appears only after the replay finishes (`:414`), and the map can't be panned or zoomed (`:391-393`). The trip's main visual looks faded and unfinished.
  - **H** XP is shown 3 times (hero pill `:143-148`, a full-width StatTile `:268`, per checkpoint `:198-204`), while distance and time live in a generic breakdown. The page reads as an XP receipt, not a travel memory.
  - **M** The AppBar title is the generic "Adventure Journal" (`:64`) while the real title sits in the hero. There are no actions: no share, delete or rename, and no "Add memory" for this trip, even though `showAddMemorySheet(adventureId:)` exists (`memories/presentation/memory_capture.dart:25-28`).
  - **M** Raw colours on the map: finish flag `Colors.red` (`:421`), reached checkpoints `Colors.green` (`:437`), and the route in emerald rather than the user's equipped rank trail colour (the Rank rewards card promises "trail colour", `profile/rank_rewards_card.dart:110`).
  - **M** The "Replay Route" FilledButton sits in a section header (`:354-365`) and is the most prominent button on the page. That is the wrong primary action.
  - **L** A `Row` with a single `Expanded` around the Memories header (`:210-219`) is vestigial. Months are a hardcoded English array (`:238-251`). The `setState` per animation tick rebuilds the whole map (`:298-300`).
- **Redesign recommendation:** a full-bleed route map header (about 40 % of the screen, interactive, full-opacity route in the user's trail colour, start/finish markers always visible) that collapses into the app bar (SliverAppBar) with the trip title. A play/replay FAB-mini sits on the map. Below it: one stats strip (distance · moving time · places · XP as a single chip). Checkpoints become a vertical timeline. Memories show as a horizontal filmstrip with "Add". App bar actions: Share (generate a poster), plus overflow (Rename, Delete).

#### Memories gallery — `/memories` (Home quick link) — `memories/presentation/memories_gallery_screen.dart` + `memory_widgets.dart`
- **Job:** browse my photos, videos and voice notes; add a new one.
- **Layout today:** AppBar "Memories" with 3 IconButtons (calendar, community, add) → one ListView containing a 3-column grid of photo/video tiles (2 px white border plus shadow, video = green gradient with a play icon, shared = 14 px cloud badge), then **all** voice notes as SoftCard rows below the whole grid.
- **States:** shimmer grid loading. The error state shows the raw `'$error'` (`:68`). The empty state ("Capture a photo or voice note…!") has **no Add button** (`:81-86`) even though adding is the main action.
- **What works:** a single grid for photos and videos, and the shared badge concept. The viewer's `onChanged` refresh is wired.
- **Problems**
  - **H** The primary action (Add) is the 3rd unlabeled icon in the app bar (`:36-43`), with equal weight to Calendar and Community.
  - **H** `Image.file` with no `cacheWidth` (`memory_widgets.dart:91-94`) decodes up to 200 (`:12`) full-resolution photos for 110 dp tiles, which causes jank and memory pressure. The calendar already does this right (`journal/presentation/calendar_screen.dart:378`). There is no fade-in or error builder, so a missing file shows a broken image.
  - **H** Video tiles have **no thumbnail**, just a green gradient and a play icon (`memory_widgets.dart:73-89`). A gallery of videos looks like placeholders.
  - **M** Voice notes are rendered after the entire photo grid (`memory_widgets.dart:122-125`), so with many photos they are effectively hidden. Each one is titled "Voice note" with only "12s", no date or trip (`:185-200`). Their play `IconButton.filled` has no tooltip (`:172-179`).
  - **M** No date grouping ("April 2026", "Trip to Sukhna Lake"), no filters (Photos / Videos / Voice / Shared), no multi-select or delete.
  - **M** The white border plus drop shadow on every tile (`memory_widgets.dart:56-67`) looks like a template; premium galleries use edge-to-edge tiles with 2 dp gutters.
  - **L** The tile tap is a `GestureDetector` (`:47-55`), so it has no Semantics button role or label. The shared badge has no label.
- **Redesign recommendation:** an app bar with Calendar and Community as icons (or a "Mine | Community" segmented tab), and Add as an extended FAB "Add memory". A filter chip row (All · Photos · Videos · Voice). Group the grid by month with sticky headers, using a `SliverGrid` with 2 dp gutters, square tiles, `cacheWidth`, fade-in, and video thumbnails (via `video_thumbnail`) with a duration badge. Voice notes become grid tiles with a waveform glyph and duration. Long-press for multi-select (share or delete). Add a Hero transition into the viewer.

#### Memory viewer (own) — pushed from grids — `memories/presentation/memory_viewer.dart` (`MemoryViewerScreen`, `MemoryMedia`, `_SharePanel`)
- **Job:** look at a memory full screen; optionally share it to friends or the public.
- **Layout today:** black Scaffold, black AppBar titled "Photo" or "Video" → media (`InteractiveViewer` for photos; for videos a VideoPlayer with a tap-to-play overlay and a thin `VideoProgressIndicator`) → an always-visible cream panel (#F7FBF5 hardcoded) with a privacy status line, a Friends/Public SegmentedButton, a description, a Caption TextField, and Share/Update plus a red "Stop sharing" OutlinedButton.
- **States:** variants for Firebase-not-ready and signed-out. Upload progress appears as a bar with a percentage. Errors go to a raw `'$e'` SnackBar (`:216`). Video load errors say "Check your connection" even for **local files** (`:95`, `:164`). A local `Image.file` has no errorBuilder (`:79`).
- **What works:** pinch zoom, scrubbable video, a clear private/shared status line, and the upload progress.
- **Problems (premium-media lens)**
  - **H** Not immersive. The share form permanently occupies roughly 35–45 % of the screen (`:267-276`, panel `:458-466`); the TextField pulls the keyboard over the photo. There is no tap-to-hide chrome and no swipe to dismiss.
  - **H** It is a single item with no swipe between memories (`memory_widgets.dart:49-53` pushes one memory). There is no Hero from the grid, so the transition is the abrupt default page route.
  - **H** Missing basic media actions: **delete**, share via the OS share sheet (save or send to WhatsApp), view the trip or place, and info (date, location). The title is "Photo"/"Video" (`:257-260`), not the date or place.
  - **M** The share name is derived from the email prefix (`:212`, `user.email?.split('@').first`), which can leak or uglify identity. Use the display name.
  - **M** Video controls are minimal: no elapsed/total time, no mute, a 4 px scrub bar that is hard to grab (`:138-146`), and no autoplay.
  - **M** Mixed button styles: `FilledButton.icon` (Share), an `OutlinedButton` with raw `Colors.red` (`:438-449`), and a `FilledButton` "Sign in" (`:324-328`). The caption isn't shown over the media for an already-shared memory except inside the TextField.
  - **L** 20 `Colors.*` uses in the file; the panel colour is a hex literal instead of `AppTheme.cream` (`:462`).
- **Redesign recommendation:** a true full-screen viewer. A `PageView` across the current list, with Hero from the grid, swipe-down to dismiss, and tap to toggle chrome. A top bar with a gradient scrim showing date, place and a link to the trip. A bottom action bar with 4 labelled icons: Share (OS), Post (opens the visibility + caption **sheet**), Info, Delete. A shared badge chip over the media. Video: center play, a bottom scrubber with times, mute, and autoplay on open.

#### Shared memory viewer — from Community — same file, `SharedMemoryViewerScreen` (`:471-561`)
- **Problems:** **M** The title is the author's display name only, with no avatar or profile link (`:483-486`). **M** There is no report or hide action on **public** user-generated media, which is a trust and safety gap and expected in any feed. **L** The MetaPill uses its default translucent white, which is fine on black, but the date format is a hardcoded array (`:544-560`). **L** Same immersion issues as above.
- **Redesign recommendation:** reuse the full-screen viewer shell. The top bar shows avatar, name and time. Bottom: caption (expandable) and visibility chip. Overflow: Report, Hide user.

#### Community memories — `/community-memories` — `memories/presentation/community_memories_screen.dart`
- **Job:** see what friends or everyone shared.
- **Layout today:** AppBar → full-width Friends/Everyone SegmentedButton → a responsive 2-up grid (`maxCrossAxisExtent: 260`, ratio 0.82) of tiles with a bottom gradient, author name and a 2-line caption.
- **States:** signed-out / no-Firebase EmptyStateCard (with sign-in when possible), shimmer loading, error with retry (raw `'$error'`, `:117`), and separate empty copy per tab.
- **What works:** a responsive grid (the only one in scope that is), and a caption scrim that is readable on any photo.
- **Problems:** **H** Video tiles have no thumbnail (green gradient, `:193-209`). **M** No author avatar, timestamp or place on tiles. **M** "Sign In" casing (`:44`) vs "Sign in" (`memory_viewer.dart:327`). **M** The tile's white border plus shadow is the same template look as the gallery (`:176-187`). **L** The empty-state copy points to "your Memories" with no link (`:135`). **L** A `GestureDetector` tile has no Semantics.
- **Redesign recommendation:** a feed-like 2-column staggered grid with avatar, name and relative time on the scrim. Put the segmented control in the app bar bottom. Add a "Share one of yours" CTA in the empty state that opens the gallery picker. Pair it with the viewer above.

#### Add memory sheet — from the gallery "+" — `memories/presentation/memory_capture.dart`
- **Job:** choose how to add: photo, gallery photos, record video, gallery video, voice.
- **Layout today:** a bottom sheet with the title "Add a memory" and 5 `ListTile`s, each with a tinted circle icon, title and subtitle. A busy spinner replaces the list while saving.
- **Problems:** **H** Inconsistent capture UIs. "Take a photo" opens the custom `CameraScreen` (`:54-58`); "Record a video" opens the **system** camera via ImagePicker (`:81-84`). Photo review is `PhotoReviewScreen` (in camera_screen) while video and gallery review use `MediaReviewScreen`, so there are two review screens for one job. **M** 5 vertical list rows for what is a 2×2 + 1 choice; the two camera options should be one "Camera" entry with a Photo/Video mode switch. **L** The error SnackBar shows the raw `'$e'` (`:185`). **L** There is no success feedback after saving ("Saved to Memories").
- **Redesign recommendation:** a compact sheet with 3 large tiles: **Camera** (photo/video in one custom camera), **Gallery** (photos and videos, multi-pick), **Voice note**. Then always show the same `MediaReviewScreen`, and finish with a SnackBar "2 memories added · View".

#### Camera — pushed from Add memory, and from tracking with `proofMode` (`tracking/presentation/tracking_screen.dart:418-420`) — `memories/presentation/camera_screen.dart`
- **Job:** take a photo quickly; in proof mode, take a live photo at the place to verify the visit.
- **Layout today:** a **theme AppBar** (transparent with deep-green title over the green AppBackground, `lib/core/theme/app_theme.dart:136-148`) "Capture Memory" with a grid toggle (tooltip "AI Photo Assistant") and a gallery icon → the preview below the app bar (cropped to cover) → an optional rule-of-thirds overlay with an amber-dot banner → a camera-switch FAB (bottom right) → a `FloatingActionButton.large` shutter (bottom centre) → `PhotoReviewScreen` (black, Retake / Use photo).
- **States:** loading is a bare spinner Scaffold with **no app bar and no back button** (`:208-210`). Device error is plain centred text in a Scaffold (`:200-205`). Permission denied is text with **no "Open settings" or retry** (`:236-246`). Saving shows a spinner inside the shutter. A debug overlay appears in debug builds only.
- **What works:** the preview crops correctly (`CoverPreview`, `previewBoxRatio`). A sensible back/front flip. Retake deletes the temp file. In proof mode the gallery is hidden and the capture time and place are taken at shutter time.
- **Problems (premium-media lens)**
  - **H** It is not a camera UI. The green, light-themed app bar sits on top of the viewfinder, the preview isn't full-bleed, and the green gradient shows during loading. Every pro camera uses black, edge-to-edge chrome.
  - **H** The shutter is a default M3 **large FAB** (rounded square, forest fill, `Icons.camera_alt`, `:334-341`), not a round shutter. There is no capture flash or animation, no haptic, and no last-shot thumbnail.
  - **H** Proof mode gives **no explanation**. Nothing tells the user that this photo verifies the visit, needs the live camera or records location; only the gallery icon disappears (`:225-230`). Failing the check later will feel arbitrary.
  - **M** The "AI Photo Assistant" tooltip (`:218`) is misleading: it is a static rule-of-thirds grid. The `Icons.grid_on` turns raw `Colors.amber` when active (`:217`). The banner is `Positioned(top: 16)` with no left/right, so it hugs the left edge instead of centring (`:291-293`).
  - **M** Missing basics: flash, tap to focus, pinch or 0.5×/1×/2× zoom, and a photo/video mode (video goes to the system camera, see Add memory).
  - **M** The switch-camera FAB (`:315-329`) is a second FAB style in the same row and isn't vertically aligned with the shutter (bottom 52 vs the shutter's 32 + 96/2).
  - **L** 14 `Colors.*` uses. The error copy concatenates a raw exception (`:62`).
- **Redesign recommendation:** a black, full-bleed `CameraShell`. Top bar (on a scrim): close X, flash, grid toggle labelled "Grid". The viewfinder fills the screen with tap-to-focus and pinch zoom plus zoom chips. A bottom bar has 3 equal slots: last-thumbnail / gallery (hidden in proof mode), a round 76 dp white-ring shutter (press scale, white flash overlay, haptic), and flip. A PHOTO | VIDEO mode switcher above the shutter. In proof mode, a persistent pill reads "Verification photo · location on" with an info sheet. Loading and error states keep the black shell with a close button, and permission denied gets an "Open settings" button. Then `MediaReviewScreen` (shared).

#### Photo/media review — `memories/presentation/media_review.dart` (+ duplicate `PhotoReviewScreen` in `memories/presentation/camera_screen.dart:353-426`)
- **Job:** keep or retake what was just captured or picked.
- **What works:** a black full-screen preview, a swipeable multi-photo PageView with a counter in the title and remove-this-photo, and clear Retake / Use buttons at 52 dp. These are the most "pro" screens in scope.
- **Problems:** **M** Two implementations of the same screen (`camera_screen.dart:353` vs `media_review.dart:30`) that will drift. **L** The `FilledButton` on black uses the forest fill (`media_review.dart:144-151`), which has low contrast against black; use white or amber for the primary action on dark. **L** There are no page dots or thumbnail strip for multi-photo, only "(2/5)" in the title (`:74-79`). **L** No light editing (rotate/crop) and no caption entry at this point, which is the natural moment to add one.
- **Redesign recommendation:** keep one `MediaReviewScreen`, with a thumbnail strip for multi-select, an optional caption field, and a "Use" primary in white on the dark UI.

#### Voice recorder sheet — from Add memory — `memories/presentation/voice_recorder_widget.dart`
- **Job:** record a short voice note, preview it, then save it.
- **Layout today:** a bottom sheet with title "Voice Memory" / "Recording..." / "Preview", a 40 sp timer (red while recording), a large FAB mic → red stop FAB, then a Wrap of 4 controls (filled play IconButton, Record again, Discard, Save).
- **States:** mic permission denied shows a SnackBar **behind the modal sheet** (`:76-82`), likely invisible, with no settings link. There is no error handling around `_recorder.start` or stop (`:92`, `:107`). A save failure just stops the spinner (no catch, `:165-182`).
- **Problems:** **M** No live level meter or waveform; a static timer is the only feedback, so it doesn't feel like it's "listening". **M** The preview has 4 actions with 3 button styles (IconButton.filled, two Outlined, Filled; `:242-273`). The Wrap reflows unpredictably on small phones, and "Record again" and "Discard" are redundant with the sheet's swipe-to-dismiss. **M** No maximum length or warning, while video is capped at 1 minute (`memory_capture.dart:20`). **L** Raw `Colors.red` (`:217`, `:229`). "Recording..." uses three dots instead of an ellipsis. "Voice Memory" here vs "Voice note" in the list (`memory_capture.dart:218`, `memory_widgets.dart:186`). The play button has no tooltip.
- **Redesign recommendation:** a sheet with a live waveform, a red pulsing dot plus timer, and one round record/stop button. After stopping, show a playback scrubber with a waveform, then "Delete" (text) and "Save note" (primary). Show permission errors inline in the sheet with "Open settings". Name it "Voice note" everywhere.

---

### Cross-screen patterns in this group

1. **Competing progress systems**: level number vs tier title, XP repeated 3–4×, stars, stamps, regions, rank styles, and the streak living elsewhere. Introduce a single `RankMeter` (tier + bar + next reward) and a `CollectionTile` row; XP becomes a currency chip, not a headline.
2. **Hand-built list rows**: "52 px icon tile + title + muted meta + chevron" is re-implemented in `profile/profile_screen.dart:254-311`, `:477-548`, `:137-164`, `journal/presentation/journal_screen.dart:93-152`, `passport/presentation/passport_stamps_card.dart:23-70`, and `memories/presentation/memory_capture.dart:244-267`, with different radii and icon treatments. Introduce `AppListTile` (leading slot, title, subtitle, trailing) and `TripListTile`.
3. **Raw exceptions shown to users**: `'$error'` / `'$e'` in `profile/profile_screen.dart:102,205`, `profile/achievements_screen.dart:48,156`, `journal/presentation/journal_screen.dart:62`, `journal/presentation/adventure_detail_screen.dart:95`, `memories/presentation/memories_gallery_screen.dart:68`, `memories/presentation/community_memories_screen.dart:117`, `memories/presentation/memory_viewer.dart:216`, `memories/presentation/memory_capture.dart:185`, `memories/presentation/camera_screen.dart:62,134,156`. Introduce `ErrorStateView(onRetry)` with friendly copy and log the detail.
4. **Imperative navigation**: `Navigator.push(MaterialPageRoute)` to screens that have routes (adventure detail) or should have them (stamp detail, memory viewer). This means no deep links, no shareable URLs and inconsistent back behaviour. Route everything: `/journal/:id`, `/passport-stamps/:cityId`, `/memories/:id`.
5. **No dark "media shell"**: the camera uses the light theme app bar, while the viewer and review screens hand-roll black Scaffolds with 5–20 raw `Colors.*` each. Introduce `MediaShell` (black, scrimmed top/bottom bars, white controls, a primary in white or amber) and use it for the camera, review, both viewers and the voice recorder.
6. **Video without thumbnails** in all three grids (gallery, community, calendar day sheet via MemoriesGrid). Introduce `MemoryThumb` (thumbnail cache, duration badge, shared badge, Semantics label).
7. **Inconsistent buttons for the same role**: the claim CTA (amber FilledButton override), "Awesome!" (FilledButton), the Passport "Claim" pseudo-pill (Container), Share (FilledButton.icon), "Stop sharing" (Outlined red), the voice preview (4 styles), the camera (FAB.large + FAB). Standardise on Primary (`AmberPillButton` or Filled), Secondary (tonal) and Destructive (text, error colour).
8. **Hardcoded English dates**: four separate month arrays or formatters (`journal/presentation/calendar_screen.dart:17-24`, `journal/presentation/adventure_detail_screen.dart:238-251`, `memories/presentation/memory_viewer.dart:545-559`, `journal/presentation/journal_screen.dart:191-198`). Use `intl` via an `AppDate` helper (relative up to 7 days, then "12 Apr 2026").
9. **Template-like tile decoration**: white 2 px borders plus drop shadows on every image tile and map (`memories/presentation/memory_widgets.dart:56-67`, `memories/presentation/community_memories_screen.dart:176-187`, `journal/presentation/adventure_detail_screen.dart:369-380`). The premium direction is flat, edge-to-edge media with small radii.
10. **Reduced motion is ignored**: FadeSlideIn, the progress tweens, elasticOut stars and route replay never check `MediaQuery.disableAnimations` (only `tracking/presentation/start_adventure_view.dart:254` does).
11. **Jargon**: "trek", "Trekked", "km trek", "Frame + trail colour", "AI Photo Assistant", "Not counted" without an explanation. Use "Distance", "Walked", "Profile frame", "Grid", "Not verified: tap to learn why".

### Quick wins

1. Fix the level/tier mismatch: derive `levelNumber` from the `_tiers` table, or drop the number from the hero (`profile/domain/explorer_level.dart:39-41`, `profile/profile_screen.dart:361`).
2. Remove the "Total XP" StatTile (`profile/profile_screen.dart:446-448`); 3 tiles fit better on 360 dp.
3. Regional Exploration: filter out `discovered == 0` groups, label each level, and gate the empty state on "nothing discovered" (`profile/profile_screen.dart:208-233`).
4. Move `RankRewardsCard` off the Achievements list, or below it (`profile/achievements_screen.dart:112`).
5. Add `cacheWidth: 300` and an `errorBuilder` to gallery tiles (`memories/presentation/memory_widgets.dart:91-94`).
6. Draw the full route at full opacity and always show the finish flag on Adventure detail (`journal/presentation/adventure_detail_screen.dart:402`, `:414`); remove the duplicate XP StatTile (`:268`).
7. Camera: black `backgroundColor` and app bar, a round shutter, a back button on the loading Scaffold, and "Open settings" on permission error (`memories/presentation/camera_screen.dart:200-249`, `:334-341`); rename the "AI Photo Assistant" tooltip to "Grid" (`:218`).
8. Add a proof-mode banner explaining why a live photo is needed (`memories/presentation/camera_screen.dart:225`).
9. Add an error state to Calendar instead of `value ?? {}` (`journal/presentation/calendar_screen.dart:73`).
10. Add an "Add memory" action to the gallery empty state and promote Add to an extended FAB (`memories/presentation/memories_gallery_screen.dart:36-43`, `:81-86`).


---

## UI audit E: Social tab, groups, leaderboard, feed, footprint, ecosystem

Scope: `lib/features/social/presentation/*` (10 files, 4,425 lines) + `lib/features/ecosystem/presentation/*` (9 files). Every file read in full.
Raw-token counts in scope (Colors.* / inline fontSize / Color(0x…)): social_screen 13/13/0, friend_challenges_section 5/14/0, leaderboard 5/8/3, group_detail 5/7/0, group_live_map 3/2/4, ecosystem_screen 3/4/7, rewards 3/4/4. No file in social uses `Semantics`. The only `Semantics` in scope is `sample_data_banner.dart:25`.

**What the code shows about IA:** Social (`/social`, tab 3 of 4 in `StatefulShellRoute`, `app_router.dart:294-300`) is the **only place in the app to sign in, sign out or delete the account**. Nothing outside `social_screen.dart:440` calls `signOut`. `login_screen.dart:83` sends users back to `/social`. `capsule_sheet.dart:144` tells users "Sign in (Social tab)". Groups, Group Adventures, Feed and Leaderboard are top-level routes that can only be reached from four unlabeled icons in the Social header.

---

#### Social tab — `/social` (bottom-nav tab) — `lib/features/social/presentation/social_screen.dart`
- **Job:** find and manage friends. Today it also has to carry profile, privacy, live friends, challenges, moderation and account.
- **Layout today (signed in, top→bottom, one `ListView`, `:254-396`):**
  1. `_SocialHeader`: "Social" at 36 sp w800 (`:130-139`) plus **4 × `RoundIconButton` size 42**: Groups `diversity_3_outlined`, Group Adventures `groups_outlined`, Activity Feed `dynamic_feed`, Leaderboard `emoji_events_outlined` (`:258-284`).
  2. `_MyProfileCard`: HeroCard with a 56 px avatar, name, bio or "No bio yet", and an edit icon (`:827-890`). The edit icon opens the **Edit Profile AlertDialog** (`:909-1032`), which holds an avatar preview, a "Change Avatar" TextButton, and Display name and Bio fields. It is non-dismissible (`:911`) and its Save is an ElevatedButton.
  3. `_FootprintPrivacyCard`: "Who can see my map", a 3-segment Private/Friends/Public control and a 12.5 sp description (`:640-711`).
  4. `_FriendsLiveSection` (only when someone is live): "Friends Live Now" cards, not tappable (`:730-787`).
  5. `FriendChallengesSection`: always rendered. It has a custom header, a "+ Challenge" TextButton, an empty card or challenge cards, and opens the **New Challenge bottom sheet**. See its own section.
  6. "Friend Requests" (only when there are any), `_FriendRequestTile` with ✓/✕ icon buttons (`:336-367`, `:1079-1086`).
  7. "Explorers": **the first 100 profiles in the database** (`social_repository.dart:202`). Each `_ExplorerTile` has avatar, name, bio, a state button (Add Friend / Friends / Requested / "Respond above"), a map icon for friends, and a ⋮ menu (View map / Mute / Block / Report) (`:1110-1188`). The menu opens the **Block confirm dialog** (`:1198-1224`) and the **Report dialog** (`:1229-1265`).
  8. "Blocked (n)" with `_ManagedUserTile` and Unblock (`:1349-1363`). "Muted (n)" with Unmute (`:1389-1403`).
  9. "Account": email, an Outlined "Sign out" and a red TextButton "Delete account" (`:418-460`). The latter opens the **Delete Account dialog** with a password or Google re-auth (`:528-592`).
  That is **9 stacked sections and 6 overlays** (Edit profile, Block, Report, Delete account, New challenge sheet, ⋮ menu) on one tab.
- **States:**
  - Firebase off: a card that says "See PENDING_TASKS.md for setup steps" (`:206-213`). That is developer copy shown to users.
  - Signed out: the title alone with **no header actions**, plus one EmptyStateCard, "Find fellow explorers / Sign in to find and friend other explorers", with Sign In → `/login` (`:220-229`). The card never says that sign-in also unlocks groups, leaderboard and backup, and Leaderboard/Groups can't be reached from here.
  - Loading: skeleton (`:174-196`).
  - Error: raw `'$error'` text (`:294`, `:822`).
  - Live, challenges, blocked and muted all hide silently on load or error (`:723-724`, `:1342-1343`).
- **What works:** pull-to-refresh across all providers. Block and mute are complete flows with Unblock/Unmute. The Delete-account copy explains exactly what is and isn't deleted (`:535-541`). FadeSlideIn stagger on the top cards.
- **Problems:**
  - **H** IA overload. Settings (map privacy `:328`, blocked/muted `:386-390`, sign-out/delete `:391`) are interleaved with social content, and the account controls sit at the very bottom, under a list of up to 100 strangers. A user looking for "Sign out" has to scroll the whole directory.
  - **H** There is **no "My friends" list and no search**. Friends show up only as rows in "Explorers" that carry a "Friends" button (`:1282-1290`). With `limit(100)`, friends and requesters outside the first 100 profiles never appear, and a request shows as "An explorer" (`:343-347`, `:1049`).
  - **H** Tapping "Friends" **unfriends immediately with no confirmation** (`:1283-1287`), and tapping "Requested" cancels with no confirmation (`:1294-1298`). A status label doubles as a destructive button.
  - **H** Header: 4 icon-only buttons at 42 px, below 48 (`:262`). Labels are reachable only by long-pressing for the tooltip. `diversity_3` (Groups) and `groups` (Group Adventures) look nearly identical. On a 360 dp phone the four buttons and gaps take 200 dp, which leaves about 120 dp for the 36 sp title, so it can ellipsize (`:130-133`).
  - **H** Explorer row is cramped. Page pad 40 + card pad 18 + avatar 44 + gap 22 + "Add Friend" pill (~100) + map icon 48 + ⋮ 48 leaves **≈40 dp for the name** on a 360 dp phone (`:1112-1185`). "View map" appears twice, as an icon (`:1146-1154`) and in the menu (`:1177`).
  - **M** Friendships load separately from explorers (`:300`, `?? const []`), so friends briefly show "Add Friend" and can be re-requested.
  - **M** Friend-request ✓/✕ are `IconButton`s with **no tooltip**, coloured `Colors.green`/`Colors.red` only (`:1079-1086`).
  - **M** Edit-profile Save has no `catch`. On failure the spinner stops and nothing explains why (`:989-1023`). A failed avatar upload is swallowed with `debugPrint` (`:996-998`). The fallback initial is computed once and doesn't update as the name changes (`:942-946`).
  - **M** Buttons mix types: Elevated (`:984`, `:1211`, `:1243`), Filled (`:572`), Outlined (`:439`), Text (`:447`), and red is set via raw `Colors.red` (`:454`, `:562`, `:577`, `:1219`).
  - **M** "Friends Live Now" rows are dead ends. They can't be tapped to open the friend on the map (`:735`).
  - **L** Duplicated card recipe: `SoftCard(margin bottom 10, radius 22, padding 14/10)` appears 5× (`:735`, `:1050`, `:1110`, `:1425`). Inline sizes 15.5 / 12.5 / 15 / 22.
- **Redesign recommendation:**
  - Split the tab. **Social = Friends hub**: a search field ("Find explorers by name"), a Requests strip (badge count), a "Your friends (n)" list, and a "Suggested explorers" list below. Move profile, map visibility, blocked/muted, sign out and delete account to a **Profile/Settings** area (the Passport tab or `/settings`).
  - Replace the 4 header icons with a horizontal **segmented nav or labelled chips**: Friends · Groups · Meetups (rename "Group Adventures") · Leaderboard · Feed. Alternatively, make Social a page with top `TabBar`s. Labels must be visible.
  - Primary action: **"Add friends"** (search). The profile shrinks to a compact header row ("You · edit") or moves out of Social entirely.
  - Introduce `PersonTile` (avatar, name, subtitle, one trailing action plus ⋮). Its states are Add (filled), Requested (tonal, with a confirm sheet to cancel) and Friend (no button, unfriend lives in ⋮ behind a confirm). Remove the duplicate map icon.
  - Requests become `PersonTile` rows with labelled "Accept" (filled) and "Decline" (text) buttons, not coloured icons.
  - Signed out: a full-height hero with three value bullets (friends, groups, leaderboard), one "Sign in" button, and a "Browse leaderboard" secondary link.
  - Edit profile becomes a full-screen route or a bottom sheet with inline validation and error text. Delete account moves to Settings and keeps the current copy.

#### Friend Challenges section + New Challenge sheet — embedded in Social — `friend_challenges_section.dart`
- **Job:** start or answer a 1:1 distance race with a friend.
- **Layout today:** a custom header row (icon, "Friend Challenges" at 18 sp, "+ Challenge" TextButton) (`:34-65`). Below it, either an empty SoftCard ("No active challenges / Race friends to trek km…", `:66-115`) or `_ChallengeCard`s. A card shows the title "5.0 km Trek Race" and the subtitle, then Decline/Accept for an incoming challenge, or two labelled progress bars once active (`:168-302`). The sheet (`:323-447`) has the title "Challenge a Friend", the copy, a "Choose Friend" dropdown, a 3 / 5 / 10 km SegmentedButton and a full-width "Send Challenge".
- **States:** loading and error are hidden (`:20-21`). With no friends, the section and CTA still render, and the sheet only then says "Add accepted friends… first" (`:357-360`). There is no error handling on send: `_submitting` stays true if it throws (`:413-421`).
- **What works:** two-bar head-to-head progress is clear. The sheet is a bottom sheet with a drag handle, which is the right pattern. Send is disabled until a friend is picked.
- **Problems:**
  - **H** Double horizontal padding. The section adds its own `horizontal: 20` (`:35`, `:68`, `:120`) inside Social's `_pagePadding` (`social_screen.dart:313-314`), so challenge cards sit **40 dp** in from the edge, out of line with every other card.
  - **M** A custom header (`:36-64`, 18 sp plus a leading icon) is used instead of `SectionHeader` (21 sp, which already supports `actionLabel`/`onAction`, `components.dart:439-472`).
  - **M** Jargon and mixed copy: "Trek Race", "trek km", "trek meters", "walk the distance" (`:103`, `:194`, `:344`).
  - **M** The section shows even when the user has zero friends, and the CTA leads to a dead end.
  - **L** Text at 12 sp (`:210`, `:248`, `:254`, `:277`, `:283`). The "You" and friend bars use `primaryGreen` vs `forest`, which are barely distinguishable (`:265`, `:293`). Decline has no confirm.
  - **L** Landmark-race cards still parse `targetValue` as metres with a default of 5000 (`:160`). Verify that "First to reach" doesn't render km bars.
- **Redesign recommendation:** render only when the user has ≥1 friend or ≥1 challenge. Use `SectionHeader(title: 'Challenges', actionLabel: 'New')` and drop the inner padding. Make it a compact horizontal carousel of `ChallengeCard`s, with avatars on the bars and "You" in brand colour vs the friend in neutral grey. Use copy like "5 km race · ends Sun". Pick the friend from an avatar list (not a dropdown) in the sheet. Show error snackbars on send.

#### Groups — `/groups` (Social header icon) — `groups_screen.dart`
- **Job:** join or create a group.
- **Layout today:** AppBar "Groups" with a "+" icon (`:69-78`). "My Groups" (only when non-empty) above "Public Groups". Each `_GroupCard` shows an initial avatar, name with a lock for private groups, a 2-line description, "N members", and a trailing red delete icon (creator), "Leave" outlined, or "Join" filled (`:252-351`). "Create Group" is an **AlertDialog** with Name, Description and a Visibility dropdown (`:159-227`).
- **States:** the signed-out card has **no Sign-in button** (`:49-56`), which is a dead end. The Firebase-off card again references PENDING_TASKS.md (`:38-39`). Errors show `'$error'` (`:119`). The empty-state title is repeated in its message ("No public groups yet" / "No public groups yet. Create one!", `:127-128`). My Groups hides load errors (`:87`).
- **What works:** a clear Join/Leave/Delete trichotomy and the member count.
- **Problems:**
  - **H** The creator's **delete icon deletes immediately**, with no confirmation and **no tooltip** (`:317-323`).
  - **H** "Private (invite only)" (`:185`) exists, but there is **no invite flow** anywhere in scope. A private group can never gain members.
  - **M** Non-members can't open a group to preview it before joining (`onTap` only if member, `:255-259`).
  - **M** The create dialog silently ignores an empty name (`:200`). It has no loading state, no error handling, and the button is an ElevatedButton. The pill style is redefined locally (`:248-250`) and duplicates `_pillStyle` in `social_screen.dart:1312`.
  - **L** Text at 12.5 / 13 / 16.5 sp. The 14 px lock icon is the only indication that a group is private.
- **Redesign recommendation:** use a FAB or a top filled button labelled "Create group". Put a "Your groups" carousel above "Discover" with search. Every card opens a detail page, and Join lives on the detail page and the card. Move delete into the detail page's ⋮ menu behind a confirm. Make create a full-screen form with a Public/Private segmented control. Add a signed-out CTA.

#### Group detail — `/groups/:id` — `group_detail_screen.dart`
- **Job:** see who's in the group and their safety status. Get to chat.
- **Layout today:** AppBar with the name (from the query string) and a chat icon (`:62-73`). A HeroCard with "Group XP" plus a 44 sp amber number plus the MetaPill "Combined total from N members" (`:118-148`). A full-width filled "Update My Safety Status" (`:152-161`). "Safety Board" lists every member: initial avatar, name, status line "✅ Safe at 09:12" in green/orange, and "N XP" (`:166-229`). The status picker is a **SimpleDialog with emoji options** (`:244-262`).
- **States:** skeleton, error with retry (raw `$error`, `:94`), and "Group not found". Safety statuses show nothing while loading (`:111`).
- **What works:** a useful safety check-in concept, a single primary action, and a live stream of statuses.
- **Problems:**
  - **H** Contrast. `Colors.orange` text on white (`:257`, `:298`) is about 2.2:1. Meaning also rides on emoji plus colour (`:250`, `:287-289`).
  - **M** Status time is `HH:mm` with no date (`:204-205`), so "Safe at 09:12" could be days old.
  - **M** The page never shows the group's description, members count vs joined state, or Leave/Invite actions. Chat is a lone app-bar icon with no label. Hierarchy is inverted: Group XP (vanity) is the hero while safety (the job) sits below it.
  - **L** Members show initials only even when `photoUrl` exists (`:176`). Inline sizes 14.5 / 44 / 12.5 / 16.
- **Redesign recommendation:** the header shows name, description, member avatars stack, and "Open chat" (primary) plus ⋮ (Leave / Invite / Delete). Below it, a "Safety" card with two large labelled buttons, "I'm safe" and "Delayed / off route" (inline, no dialog), and a relative timestamp ("12 min ago"). Then a members list via `PersonTile` with a `StatusBadge` (icon + text + colour). Group XP becomes a small stat chip.

#### Group / adventure chat — `/groups/:id/chat`, `/group-adventures/:id/chat` — `group_chat_screen.dart`
- **Job:** message the group.
- **Layout today:** AppBar with the title. Bubbles: own messages forest/white at right, others white at left with the sender name at 12 sp, max width 300, shadowed (`:142-191`). A floating pill composer with a filled send icon button (`:198-245`).
- **States:** skeleton bubbles (nice, `:87-104`). Errors show `$error` (`:110`). The empty state is a full EmptyStateCard whose title is repeated in the message (`:119-120`). There is no signed-out guard (send silently returns, `:49`). There is no send failure handling.
- **What works:** a proper chat bubble shape and a composer that respects SafeArea.
- **Problems:**
  - **H** `jumpTo(maxScrollExtent)` runs **on every rebuild** (`:124-130`). A user reading history gets yanked to the bottom whenever any message arrives, and there is no animation.
  - **M** No timestamps, day separators or avatars. Consecutive messages from one sender repeat the name.
  - **M** `_send` awaits a profile fetch **before** clearing the field (`:51-54`). That adds visible lag and allows double-send. The TextField is single-line (no `maxLines: null` or `textCapitalization`, `:220-230`).
  - **L** Shadow on every bubble (`:159-165`) adds visual noise. Fixed `maxWidth: 300` (`:148`) looks narrow on tablets.
- **Redesign recommendation:** use a reverse `ListView` (auto-stick to bottom only when already at the bottom), grouped bubbles with avatar and time, day dividers, and an optimistic send. Use a multiline composer. Remove the bubble shadows. Show a member count in the app-bar subtitle that opens the group detail.

#### Group Adventures — `/group-adventures` (Social header icon) — `group_adventures_screen.dart`
- **Job:** find or organise a meetup trek and join it.
- **Layout today:** AppBar with "+". "My Adventures" above "Public Adventures". Each card shows the name with a lock, the full description, "date • time • Meet at X" in green at 12.5 sp, "Difficulty • n/N joined • Organized by", then a `Wrap` holding Cancel/Leave/Join plus **3 unlabeled icon buttons**: chat, live map, and a play icon for "Start Tracking" (`:313-448`). Create is an **AlertDialog with 9 fields** (`:169-288`).
- **States:** signed-out has no action (`:53-60`). Firebase-off references PENDING_TASKS.md (`:42-43`). The empty-state title is repeated (`:131-132`). My Adventures hides errors (`:91`).
- **What works:** capacity ("n/N joined", Full disables Join). Chat, map and tracking are reachable from the card.
- **Problems:**
  - **H** **Date and Time are free-text fields** (`:192-199`). There is no picker, no validation, and the values are stored as strings. A 9-field form sits in an AlertDialog on a phone.
  - **H** "Cancel Adventure" deletes **with no confirmation** (`:367-379`). It is styled identically to "Leave".
  - **M** Three icon-only actions (chat / map / play) depend on tooltips (`:413-442`). The play icon in `amberText` reads as "media". "Start Tracking" is jargon.
  - **M** No detail page. The meta line degrades to "• • Meet at " when fields are blank (`:347`). The description has no `maxLines` (`:341-344`).
  - **L** The name "Group Adventures" is easily confused with "Groups". The header icons are near-identical.
- **Redesign recommendation:** rename it **Meetups** (or "Group trips"). Use list cards with a date block (day / month), the title, place, a difficulty chip and an avatar stack plus "4/6". Tap opens a detail route with "Join" (primary), then Chat / Live map / Start trip as labelled buttons. Make create a multi-step full-screen form with Date/Time pickers and a place search. Put destructive actions behind ⋮ and a confirm.

#### Group live map ("Radar") — `/group-adventures/:id/live-map` — `group_live_map_screen.dart`
- **Job:** see where group members are and who has strayed. Ping the group.
- **Layout today:** AppBar "<name> — Radar". A red `MaterialBanner` when someone is separated (`:158-170`). A full map with 44 px markers (white disc, status-coloured ring, flag/person icon). A **fixed 112 px** horizontal strip of member cards (`:218-227`). An extended FAB "Ping group" that opens a sheet of 4 preset pings (`:107-115`, `:66-82`).
- **States:** a skeleton. A good error state with friendly copy (`:123-130`). The empty state "Nobody is live right now" explains how to appear on the map. Ping failure shows an explanatory snackbar (`:88-95`).
- **What works:** the strongest-UX screen in the group. It shows status, a stray alert and quick pings, and refreshes stale data every 30 s.
- **Problems:**
  - **H** Status is **colour-only** (ring green / amber / red / grey, `:29-34`, `:199`, `:263`). There is no legend and markers carry no text, so it fails for colour-blind users.
  - **M** Raw colours `0xFF1B8A3A`, `0xFFD32F2F`, `0xFFFDECEA`, `Colors.grey` (`:30-33`, `:159-162`). The `actions: [SizedBox.shrink()]` hack (`:169`).
  - **M** The FAB floats over the 112 px member strip and covers the right-most card. The fixed height overflows at large text scale (`:219`). 12 sp text (`:286`, `:296`).
  - **L** No recenter or "fit all" control. Names are only in a long-press Tooltip on markers (`:192`). The " — Radar" suffix lengthens an already long title.
- **Redesign recommendation:** use a full-bleed map with a draggable bottom sheet (collapsed state shows the member list with `StatusBadge` icon and text: "With group", "250 m away", "Last seen 12 min"). Put a status legend chip row on top and a "Ping" button inside the sheet header, not as a FAB. Use name labels under markers and the theme's danger/warn/success tokens.

#### Leaderboard — `/leaderboard` (Social header icon) — `leaderboard_screen.dart`
- **Job:** see my rank this week, globally or among friends.
- **Layout today:** AppBar. **Two stacked full-width SegmentedButtons**: This Week / All-Time (amber selected, `:53-78`) and Global / Friends (forest selected, `:85-107`). Then "Resets every Monday…" (12.5 sp), a podium HeroCard (top 3 with medal rings and white bars, `:258-352`), `_RankRow`s (`:370-438`), a "Showing the top N" footer, and a **pinned "you" row** when the user is off-list (`:232-239`).
- **States:** signed out shows a card with Sign In, which is good (`:33-46`). Errors show `$error` (`:141`). Friends empty state links "Find explorers" → `/social` (good, `:153-159`). The weekly empty state is handled. There is a skeleton.
- **What works:** the podium plus pinned self-row is a premium pattern. Verified shields. Level and title under the name. Pull to refresh.
- **Problems:**
  - **M** Two segmented controls in **different selected colours** (amber vs forest) for the same kind of control take two rows of chrome before any content.
  - **M** `_RankRow` hand-rolls its card (`Container` + border + shadow, `:370-388`) instead of SoftCard. Medal colours are raw (`:283-285`).
  - **L** The verified meaning is tooltip-only (`:493-495`). Avatars are initials only. 12 / 12.5 sp text. "Level N · Title" duplicates the XP concept.
- **Redesign recommendation:** use one row: a scope tab bar (Friends | Global, with Friends as the default) and a compact timeframe dropdown chip ("This week ▾"). Keep the podium but lighten it (no HeroCard gradient; avatars on a cream surface). Rank rows use `PersonTile` with a rank number. Make the self row sticky at the bottom always, highlighted. Explain XP in a "How XP works" info sheet.

#### Activity Feed — `/activity-feed` (Social header icon) — `activity_feed_screen.dart`
- **Job:** see what friends recently did.
- **Layout today:** AppBar. A list of SoftCards: avatar, "<name> completed "<title>"" at 15 sp w800, and "x km • +N XP • 2h ago" (`:83-117`).
- **States:** skeleton. Errors show `$error`. The empty title is repeated ("No activity yet" / "No activity yet. Complete…", `:70-71`). It has no CTA to add friends. There is no signed-out handling (an empty list renders the empty state, which misleads).
- **Problems:**
  - **M** Cards are not tappable. There is no way to open the person, their map or the adventure, and no reactions, so it is a read-only dead end.
  - **M** Only one event type ("completed"), with no images or route thumbnail. Every card looks identical, which feels template-like.
  - **L** Day grouping is missing. `_relativeTime` is duplicated with `social_screen.dart:794-799` and `group_live_map_screen.dart:309-314` (three different formats: "5m ago", "5 min ago", "5 h ago").
- **Redesign recommendation:** fold it into the Social hub as a "Recent from friends" section (3 items plus "See all"). On the full page, use `ActivityCard` with a route mini-map or photo, tap → friend's footprint or the adventure, and a "Cheer" reaction. Group by Today / This week. The empty state gets an "Add friends" button. Use a shared `formatRelativeTime`.

#### Friend footprint map — `/footprint/:uid?name=` (Explorer ⋮ / map icon) — `footprint_screen.dart`
- **Job:** look at a friend's routes and visited places.
- **Layout today:** AppBar "<name>'s map". A full map with emerald polylines and category markers with an amber check badge. A floating SoftCard at the bottom shows "N Routes · N Places visited" plus a visibility MetaPill (`:130-162`).
- **States:** good. It covers skeleton, error with retry (`$error`), the "keeps their map private" lock state, and "Nothing on this map yet".
- **What works:** a clean single-purpose screen. Honest privacy empty state. The visited marker matches the personal map.
- **Problems:**
  - **M** The bottom summary card (`bottom: 20`, `left/right: 16`) sits over `OsmAttribution` (`:127`), which risks hiding the required attribution.
  - **L** No legend. Place names are only in long-press tooltips (`:120-121`). There are no friend actions (challenge, message) from here. 12.5 sp labels.
- **Redesign recommendation:** keep it. Put the stats in a top overlay or a bottom sheet that clears the attribution. Make place markers tappable (show a name chip). Add a header with avatar and "Challenge" / "View profile".

#### Ecosystem / Marketplace (flag off, sample data) — `/ecosystem` + `guides`, `gear`, `events`, `accommodation`, `transport`, `creator-mode`, `rewards` — `lib/features/ecosystem/presentation/*`
- **Job:** a marketplace preview for guides, gear rental, events, stays, shuttles, creator monetisation and coin rewards. `FeatureFlags.ecosystem = false` (`feature_flags.dart:10`). The only entry point is a Home quick link (`home_screen.dart:520-521`).
- **Layout today:**
  - Hub: AppBar plus `SampleDataBanner` (amber strip, 44 px, `sample_data_banner.dart:21-53`), then a HeroCard ("Everything for your next trail") and a 2-column grid of 7 tiles, **each with its own rainbow gradient icon** (`ecosystem_screen.dart:19-61`).
  - Events, Accommodation: image cards (Unsplash) with price/date pills and a full-width "Register Now" / "Book Now".
  - Guides: a pravatar.cc photo, rating pill, $/hour, specialties, and "Book Guide".
  - Gear: a 2-col grid of image cards with **no action**.
  - Transport: a route card with fare and "Book Ticket".
  - Creator Mode: one HeroCard with an AmberPillButton.
  - Rewards: a hard-coded "1,250 Explorer Coins" hero and 4 "Redeem" rows.
  - Every CTA shows a "requires Payment setup" / "coming soon" snackbar.
- **States:** none. All data is static. Network images fall back to gradients. The sample banner is the only honest state and the **only Semantics in scope** (`sample_data_banner.dart:25-28`).
- **Problems:**
  - **H** Prices are in **`$` in an India app** (`events_screen.dart:122`, `accommodation_screen.dart:110`, `guides_screen.dart:107`, `gear_screen.dart:135`, `transport_screen.dart:105`, `rewards_screen.dart:97`). Names and places are Western or placeholder ("Sarah J.", "Sunrise Peak").
  - **H** "Explorer Coins" (`rewards_screen.dart:69`) is a third currency next to XP and passport stamps, with a fake balance (`:54`).
  - **M** Every primary button is a fake CTA that only produces a snackbar (events `:216-222`, accommodation `:198-206`, guides `:148-156`, transport `:165-171`, rewards `:188-194`, creator `:64-72`). Gear cards are wrapped in `PressableScale` but have no `onTap`, which is a dead affordance (`gear_screen.dart:62-63`).
  - **M** 7 different gradient palettes (`ecosystem_screen.dart:19-61`, `rewards_screen.dart:88-106`) plus 23 raw `Color(0x…)` values across the folder. That is off-brand and reads as busy and template-like. HeroCards carry dead bottom padding of 40–56 px (`ecosystem_screen.dart:103`, `rewards_screen.dart:23`, `creator_mode_screen.dart:23`).
  - **L** Hub tiles use `context.go` (`ecosystem_screen.dart:20-62`). This works because the routes are nested, but it differs from `push` everywhere else. External placeholder avatars from pravatar.cc (`guides_screen.dart:15-35`).
- **Redesign recommendation:** keep it hidden. Before it ships, rebuild it on the shared `PlaceCard` / `ListingCard` with ₹ formatting, one brand icon treatment (mono icons on sage circles instead of rainbow gradients), and real listing detail pages. Replace fake "Book" buttons with "Notify me" / waitlist until payments exist. Drop "Explorer Coins" or fold it into XP. Gear gets a detail page or loses `PressableScale`.

---

### Cross-screen patterns in this group
- **Discoverability via icon-only chrome.** Social's 4 header icons (42 px), the 3 card icons on Group Adventures, the chat icon on Group detail, and the ✓/✕ request icons all depend on tooltips. Introduce **`LabeledIconAction`** (icon plus a visible 12–13 sp label, min 48×48) and a **`SocialNav`** segmented row.
- **Destructive actions without confirmation**: unfriend (`social_screen.dart:1283`), cancel request (`:1294`), delete group (`groups_screen.dart:317`), cancel adventure (`group_adventures_screen.dart:367`), decline challenge (`friend_challenges_section.dart:224`). Introduce **`confirmDestructive()`** (a bottom sheet with a red primary) and move destructive actions into ⋮ menus.
- **AlertDialog as form container**: edit profile, create group, a 9-field create adventure, report, block, delete account, safety status. Introduce **`FormSheet`** (draggable bottom sheet with title, fields, a sticky primary button, and inline error) and full-screen routes for long forms. Use real pickers for date and time.
- **Person rows re-implemented 6×** (`_ExplorerTile`, `_FriendRequestTile`, `_ManagedUserTile`, Safety Board row, `_RankRow`, feed row), with sizes 15 / 15.5 / 16.5 and radius 20 / 22 / 24. Introduce **`PersonTile`** (avatar with photo fallback, title, subtitle, trailing slot, optional `StatusBadge`).
- **Status by colour/emoji only**: safety ✅/⚠️ plus green/orange, radar rings, request ✓/✕. Introduce **`StatusBadge`** (icon + text + token colour: success / warn / danger / neutral). Add `AppTheme.success/warning/danger` tokens to replace `Colors.green/orange/red` and `0xFFD32F2F`.
- **Developer and raw-error copy in UI**: "See PENDING_TASKS.md" (`social_screen.dart:211-212`, `groups_screen.dart:38-39`, `group_adventures_screen.dart:42-43`), and `'$error'` in ~9 places. Introduce an **`ErrorState`** with friendly copy, retry and an expandable "details".
- **Empty states repeat their title** ("No X yet" / "No X yet. …") in groups, adventures, chat and feed. **Signed-out cards with no action** in Groups and Group Adventures. Add a standard **`SignInPrompt`** component.
- **Section headers inconsistent**: `SectionHeader` 21 sp vs the custom 18 sp challenge header vs `SectionHeader(padding: top 24)` overrides everywhere (≈8×). Bake the spacing into the component.
- **Three relative-time formatters** with different formats. Make one `formatRelativeTime` in core.
- **Pill button styles redefined locally 3×** (`social_screen.dart:1312`, `groups_screen.dart:248-250`, `group_adventures_screen.dart:309-311`), with min height 36/38 (< 48). Move them into the theme as `filledButtonTheme` / `outlinedButtonTheme` with compact variants that keep a 48 px tap target.

### Quick wins
1. Add a confirm before unfriending or cancelling a request. Better, make "Friends" a non-button chip and put "Remove friend" in ⋮. `social_screen.dart:1282-1302`
2. Remove the double padding on Friend Challenges (drop `horizontal: 20`) and switch to `SectionHeader(actionLabel: 'New')`. `friend_challenges_section.dart:35`, `:68`, `:120`
3. Confirm dialogs and tooltips on group delete and on "Cancel Adventure". `groups_screen.dart:317-323`, `group_adventures_screen.dart:367-379`
4. Labelled Accept/Decline buttons (or at least tooltips) instead of coloured icons on friend requests. `social_screen.dart:1079-1086`
5. Raise the header buttons to 48 px and add a visible label row, or a single "More" sheet. Give Group Adventures a distinct icon (e.g. `hiking`). `social_screen.dart:259-283`
6. Replace the "See PENDING_TASKS.md" copy with user-facing text, and replace `'$error'` with a friendly message. `social_screen.dart:211`, `groups_screen.dart:38`, `group_adventures_screen.dart:42`, `social_screen.dart:294`
7. Add Sign-in buttons to the signed-out states in Groups and Group Adventures. `groups_screen.dart:51-56`, `group_adventures_screen.dart:55-60`
8. Stop the chat auto-jump on every rebuild: scroll only when already at the bottom, or use `reverse: true`. Clear the field before the profile fetch. `group_chat_screen.dart:51-54`, `:124-130`
9. Replace the free-text Date/Time fields with `showDatePicker` / `showTimePicker`. `group_adventures_screen.dart:192-199`
10. Replace safety emoji with icon + text, swap `Colors.orange` for `amberText`, and add a date to the status time. `group_detail_screen.dart:204-210`, `:249-258`, `:284-299`


---

