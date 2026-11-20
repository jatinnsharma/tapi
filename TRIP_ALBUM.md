# Trip album and photo sharing

Two ways to get trip photos to everyone. Both start from a trip's itinerary: tap the **Trip album** icon (photo library) in the top bar.

## 1. Share trip photos (works now, no setup)

In the album, tap **Share** (top right):

- Pick photos. Ones you haven't sent yet are picked to start with, and the sheet says "12 new since you last shared".
- Edit the message (for example "Varanasi · 12 photos").
- **Remove location from photos** is on by default: the app sends clean copies without GPS or camera details.
- **Share** opens the phone's share sheet. Choose WhatsApp, Telegram, email or anything else; that app does the sending.

Nothing goes through our servers, and nothing is shared unless you tap Share. The app can't pick a specific group for you, and it can't tell whether the photos arrived.

## 2. Shared trip album on Google Drive

Every trip member sees everyone's photos in the app, each with who took it, when, and, if the uploader chose, where.

### How it works

1. **Add photos:** take one with the camera, or choose from Memories. **Show where they were taken** is off by default.
2. **On the phone:** the original stays in the app folder. A queue in the local database (table `album_uploads`) tracks each photo, and it survives restarts and offline use.
3. **Upload,** when online, signed in, the trip is backed up, and Drive is connected:
   - **Copies:** a 2048 px viewing copy and a 400 px thumbnail, re-encoded as JPEG **with no EXIF** (no GPS inside the files).
   - **Folder:** both go into a `Tabi · <trip>` folder in **the uploader's own Google Drive**.
   - **Link sharing:** both are set to "anyone with the link can view".
   - **Album record:** a record is written to Firestore at `trip_plans/{tripId}/photos/{photoId}`. It holds the uploader, the time, the Drive file IDs, and the location only when the uploader chose to include it.
4. **Viewing:** members load photos straight from Drive using the file ID and the app's Drive API key. Files never pass through our backend.

### Status labels on your photos

| Label | Meaning |
|---|---|
| On this phone | Not uploading: signed out, the trip isn't backed up, or Drive isn't set up in this build |
| Waiting | In the queue: offline, Drive not connected, or a retry is due soon. The reason shows in the photo viewer |
| Uploading | Being uploaded now |
| Shared | In the album, visible to all members |
| Failed | Stopped retrying on its own (the file is gone, or 8 failures in a row). Tap **Retry** in the viewer |

Retries wait 30 s, 1 min, 2 min and so on, up to 1 hour. Drive's "busy" and offline errors keep retrying without limit.

Duplicates can't happen:
- Each photo has a fixed ID, used for the Firestore record.
- Drive file IDs are saved right after each upload, so a retry never uploads the same file again.
- The same memory added twice to the same trip is stored once.

Uploads run when the app starts, when it comes back to the foreground, after adding photos, and every 45 s while the album is open. They don't run while the app is closed.

### Privacy

- **The links are the protection.** Photos are "anyone with the link", and the links (long random Drive IDs) are stored only in the trip's album, which only trip members can read (see `firestore.rules`). Anyone a member forwards a link to could open that photo.
- **Removing a photo:** **Remove** deletes the album record and your Drive copies. The original stays in your Memories.
- **Leaving a trip** doesn't remove photos you added. Remove them first if you want them gone.
- **The app sees only its own files.** It uses the `drive.file` permission: it can only see files it created, never the rest of anyone's Drive.

### Setup (one-time, by you)

1. **Google Cloud console** (the project behind your Firebase app):
   - **APIs & Services → Library:** enable the **Google Drive API**.
   - **OAuth consent screen → Data access:** add the scope `.../auth/drive.file`. It's a non-sensitive scope, so it needs no security review.
   - **Credentials → Create credentials → API key:**
     - Restrict it to the **Google Drive API**.
     - Restrict it to your **Android app**, using its package name and SHA-1 fingerprint.
     - This key only reads link-shared files.
   - **Credentials:** copy the **Web client** OAuth client ID. Firebase creates it when Google sign-in is enabled.
2. **Register the Android app** (package name and SHA-1 and SHA-256 fingerprints, for debug and release builds), the same as for Google sign-in (Feature 14).
3. **Add both values** to your `dart_defines.local.json` and your release build, without sharing them:
   ```
   --dart-define=DRIVE_API_KEY=...
   --dart-define=GOOGLE_SERVER_CLIENT_ID=....apps.googleusercontent.com
   ```
4. **Deploy the Firestore rules:** `firebase deploy --only firestore:rules`.

Without steps 3 and 4, albums still work on the phone ("On this phone"), and sharing through the share sheet works.

### Tested and not tested

- **Tested** (`test/album_test.dart`, `test/album_screen_test.dart`):
  - the copies (sizes, no location left inside)
  - every upload state, retries without duplicates, and removal
  - the mapping of Drive errors
  - the album screen's banners and labels
  - the share sheet's selection
- **Written but not run:** the Firestore rules tests (`firebase_tests/firestore_album_rules.test.mjs`). The emulator needs Java 21, and this machine has Java 17.
- **Not tested against the real Google Drive** or on a phone, because the setup above doesn't exist yet.

### Limits and later

- No background uploads while the app is closed. That would need a background-task package.
- Videos and voice notes aren't in albums yet. The album is photos only.
- Drive photos are cached on the phone only by the normal image cache.
- Storage counts against each uploader's 15 GB of free Google storage: about 600 KB per photo, so roughly 20,000+ photos per person.
