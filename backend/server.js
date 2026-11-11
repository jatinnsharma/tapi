import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { createApp } from './lib/app.js';
import { connectStore } from './lib/mongo_store.js';

const need = (name) => {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing environment variable ${name}. See backend/README.md.`);
    process.exit(1);
  }
  return v;
};

const mongoUri = need('MONGODB_URI');
const mediaSecret = need('MEDIA_SECRET');
const projectId = need('FIREBASE_PROJECT_ID');

// Initialize Firebase Admin for auth and firestore.
initializeApp({ projectId });
const verifyToken = async (token) => (await getAuth().verifyIdToken(token)).uid;
const getFriends = async (uid) => {
  const db = getFirestore();
  const [snapA, snapB] = await Promise.all([
    db.collection('friendships').where('uidA', '==', uid).where('status', '==', 'accepted').get(),
    db.collection('friendships').where('uidB', '==', uid).where('status', '==', 'accepted').get(),
  ]);
  const friends = new Set();
  snapA.forEach((doc) => friends.add(doc.data().uidB));
  snapB.forEach((doc) => friends.add(doc.data().uidA));
  return Array.from(friends);
};

const store = await connectStore(mongoUri, process.env.MONGODB_DB ?? 'rwe');
const app = createApp({ verifyToken, store, mediaSecret, getFriends });

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => console.log(`Memories API listening on ${port}`));
