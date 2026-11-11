import { GridFSBucket, MongoClient, ObjectId } from 'mongodb';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';

const HEX24 = /^[0-9a-f]{24}$/;

/**
 * Memories in MongoDB (`memories` collection) and their files in GridFS
 * (bucket `media`). Memory ids are the app's own uuid, so sharing the same
 * memory twice replaces it instead of duplicating it.
 */
export async function connectStore(uri, dbName = 'rwe') {
  const client = new MongoClient(uri);
  await client.connect();
  const db = client.db(dbName);
  const store = createMongoStore(db);
  await store.ensureIndexes();
  store.close = () => client.close();
  return store;
}

export function createMongoStore(db) {
  const memories = db.collection('memories');
  const bucket = new GridFSBucket(db, { bucketName: 'media' });

  const newest = { createdAt: -1 };

  return {
    async ensureIndexes() {
      await memories.createIndex({ uid: 1, createdAt: -1 });
      await memories.createIndex({ visibility: 1, createdAt: -1 });
    },

    // --- files ---
    async saveFile(readable, { uid, contentType, maxBytes }) {
      let length = 0;
      const counter = new Transform({
        transform(chunk, _enc, cb) {
          length += chunk.length;
          if (length > maxBytes) {
            const err = new Error('file too big');
            err.code = 'TOO_BIG';
            return cb(err);
          }
          cb(null, chunk);
        },
      });
      const upload = bucket.openUploadStream('memory', {
        metadata: { uid, contentType },
      });
      try {
        await pipeline(readable, counter, upload);
      } catch (e) {
        await bucket.delete(upload.id).catch(() => {});
        throw e;
      }
      return { fileId: upload.id.toHexString(), length };
    },

    async statFile(fileId) {
      if (!HEX24.test(fileId)) return null;
      const file = await db
        .collection('media.files')
        .findOne({ _id: new ObjectId(fileId) });
      if (!file) return null;
      return {
        length: file.length,
        contentType: file.metadata?.contentType ?? 'application/octet-stream',
      };
    },

    /** range: { start, end } inclusive, or null for the whole file. */
    async openFile(fileId, range) {
      const opts = range ? { start: range.start, end: range.end + 1 } : {};
      return bucket.openDownloadStream(new ObjectId(fileId), opts);
    },

    async deleteFile(fileId) {
      if (!HEX24.test(fileId)) return;
      await bucket.delete(new ObjectId(fileId)).catch(() => {});
    },

    // --- records ---
    getMemory: (id) => memories.findOne({ _id: id }),
    countByOwner: (uid) => memories.countDocuments({ uid }),
    listByOwner: (uid) => memories.find({ uid }).toArray(),
    listPublic: (limit) =>
      memories.find({ visibility: 'public' }).sort(newest).limit(limit).toArray(),
    listForOwners: (uids, visibilities, limit) =>
      memories
        .find({ uid: { $in: uids }, visibility: { $in: visibilities } })
        .sort(newest)
        .limit(limit)
        .toArray(),
    async upsertMemory(doc) {
      await memories.replaceOne({ _id: doc._id }, doc, { upsert: true });
    },
    async updateMemory(id, patch) {
      await memories.updateOne({ _id: id }, { $set: patch });
    },
    async deleteMemory(id) {
      await memories.deleteOne({ _id: id });
    },
  };
}
