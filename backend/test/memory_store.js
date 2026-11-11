// An in-memory stand-in for mongo_store.js, same behaviour, for fast tests.
import { Readable } from 'node:stream';

export function createMemoryStore() {
  const files = new Map();
  const memories = new Map();
  let next = 0;
  const newest = (a, b) => b.createdAt - a.createdAt;

  return {
    async saveFile(readable, { uid, contentType, maxBytes }) {
      const chunks = [];
      let length = 0;
      for await (const chunk of readable) {
        length += chunk.length;
        if (length > maxBytes) {
          const err = new Error('file too big');
          err.code = 'TOO_BIG';
          throw err;
        }
        chunks.push(chunk);
      }
      const fileId = (++next).toString(16).padStart(24, '0');
      files.set(fileId, { data: Buffer.concat(chunks), contentType, uid });
      return { fileId, length };
    },
    async statFile(fileId) {
      const f = files.get(fileId);
      return f ? { length: f.data.length, contentType: f.contentType } : null;
    },
    async openFile(fileId, range) {
      const { data } = files.get(fileId);
      return Readable.from(range ? data.subarray(range.start, range.end + 1) : data);
    },
    async deleteFile(fileId) { files.delete(fileId); },
    fileCount: () => files.size,

    getMemory: async (id) => memories.get(id) ?? null,
    countByOwner: async (uid) => [...memories.values()].filter((m) => m.uid === uid).length,
    listByOwner: async (uid) => [...memories.values()].filter((m) => m.uid === uid),
    listPublic: async (limit) =>
      [...memories.values()].filter((m) => m.visibility === 'public').sort(newest).slice(0, limit),
    listForOwners: async (uids, visibilities, limit) =>
      [...memories.values()]
        .filter((m) => uids.includes(m.uid) && visibilities.includes(m.visibility))
        .sort(newest)
        .slice(0, limit),
    upsertMemory: async (doc) => { memories.set(doc._id, { ...doc }); },
    updateMemory: async (id, patch) => {
      memories.set(id, { ...memories.get(id), ...patch });
    },
    deleteMemory: async (id) => { memories.delete(id); },
  };
}
