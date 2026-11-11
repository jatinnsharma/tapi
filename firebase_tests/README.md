# Firestore rules tests

Tries honest and dishonest writes against `../firestore.rules` on the local
Firestore emulator (the XP rules for `explorers/{uid}` and the server-only `verified_xp`).

Needs Node, firebase-tools and **Java 21 or newer**.

```
cd firebase_tests
npm install
npm test
```

Run it after any change to `firestore.rules`.

The emulator config is `../firebase.emulator.json` (newer firebase-tools refuses a rules file outside the config's folder).
