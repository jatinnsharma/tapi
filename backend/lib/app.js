import express from 'express';
import { signedQuery, verifyMediaLink } from './media_token.js';
import {
  MAX_FILE_BYTES, MAX_MEMORIES_PER_USER, VISIBILITIES,
  contentTypeAllowed, isValidId, parseRange, parseShareFields, parseUidList,
} from './validate.js';

/**
 * The memories API.
 *   verifyToken(idToken) -> uid (throws if not valid)
 *   store: see mongo_store.js
 *   mediaSecret: signs the short-lived media links
 *
 * Who can see what: a memory is returned in the feed only if it is public, or
 * if it is "friends" and its owner is in the user's friends list. If `getFriends`
 * is provided, friendships are verified server-side (e.g. from Firestore).
 */
export function createApp({ verifyToken, store, mediaSecret, maxFileBytes = MAX_FILE_BYTES, getFriends }) {
  const app = express();
  app.disable('x-powered-by');
  app.use((_req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    next();
  });

  const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
  const fail = (res, status, error) => res.status(status).json({ error });

  async function auth(req, res, next) {
    const header = req.get('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) return fail(res, 401, 'Sign in first.');
    try {
      req.uid = await verifyToken(token);
      next();
    } catch {
      fail(res, 401, 'Your login is not valid. Sign in again.');
    }
  }

  const present = (m) => ({
    id: m._id,
    uid: m.uid,
    displayName: m.displayName,
    type: m.type,
    visibility: m.visibility,
    createdAt: m.createdAt.toISOString(),
    caption: m.caption,
    latitude: m.latitude,
    longitude: m.longitude,
    placeName: m.placeName,
    url: `/media/${m.fileId}?${signedQuery(mediaSecret, m.fileId)}`,
  });

  app.get('/healthz', (_req, res) => res.json({ ok: true }));

  // --- Photos and videos: link-signed, supports seeking in videos ---
  app.get('/media/:fileId', wrap(async (req, res) => {
    const { fileId } = req.params;
    if (!verifyMediaLink(mediaSecret, fileId, req.query.e, req.query.t)) {
      return fail(res, 403, 'This link has expired.');
    }
    const info = await store.statFile(fileId);
    if (!info) return fail(res, 404, 'Not found.');

    res.set('Content-Type', info.contentType);
    res.set('Accept-Ranges', 'bytes');
    res.set('Cache-Control', 'private, max-age=3600');
    const range = req.get('range') ? parseRange(req.get('range'), info.length) : null;
    if (req.get('range') && !range) {
      res.set('Content-Range', `bytes */${info.length}`);
      return res.status(416).end();
    }
    if (range) {
      res.status(206);
      res.set('Content-Range', `bytes ${range.start}-${range.end}/${info.length}`);
      res.set('Content-Length', String(range.end - range.start + 1));
    } else {
      res.set('Content-Length', String(info.length));
    }
    const stream = await store.openFile(fileId, range);
    stream.on('error', () => res.destroy());
    stream.pipe(res);
  }));

  // --- Everything below needs a login ---
  app.get('/memories/feed', auth, wrap(async (req, res) => {
    const limit = 80;
    let items;
    if (req.query.scope === 'public') {
      items = await store.listPublic(limit);
    } else if (req.query.scope === 'friends') {
      let friends;
      if (getFriends) {
        const verified = await getFriends(req.uid);
        if (req.query.friends) {
          const requested = new Set(parseUidList(req.query.friends));
          friends = verified.filter((u) => requested.has(u) && u !== req.uid);
        } else {
          friends = verified.filter((u) => u !== req.uid);
        }
      } else {
        friends = parseUidList(req.query.friends).filter((u) => u !== req.uid);
      }
      items = friends.length === 0 ? [] : await store.listForOwners(friends, VISIBILITIES, limit);
    } else {
      return fail(res, 400, 'scope must be public or friends');
    }
    res.json({ memories: items.map(present) });
  }));

  // Share (or replace) a memory: the body is the file itself.
  app.put('/memories/:id', auth, wrap(async (req, res) => {
    const { id } = req.params;
    if (!isValidId(id)) return fail(res, 400, 'Bad memory id.');
    const parsed = parseShareFields(req.query);
    if (parsed.error) return fail(res, 400, parsed.error);
    const fields = parsed.value;

    const contentType = req.get('content-type') ?? '';
    if (!contentTypeAllowed(fields.type, contentType)) {
      return fail(res, 415, `That is not a ${fields.type} file.`);
    }
    const declared = Number(req.get('content-length'));
    if (Number.isFinite(declared) && declared > maxFileBytes) {
      return fail(res, 413, 'That file is over 50 MB, too big to share.');
    }

    const existing = await store.getMemory(id);
    if (existing && existing.uid !== req.uid) return fail(res, 403, 'Not yours.');
    if (!existing && (await store.countByOwner(req.uid)) >= MAX_MEMORIES_PER_USER) {
      return fail(res, 429, `You can share up to ${MAX_MEMORIES_PER_USER} memories. Delete some first.`);
    }

    let saved;
    try {
      saved = await store.saveFile(req, { uid: req.uid, contentType, maxBytes: maxFileBytes });
    } catch (e) {
      if (e?.code === 'TOO_BIG') return fail(res, 413, 'That file is over 50 MB, too big to share.');
      throw e;
    }
    if (saved.length === 0) {
      await store.deleteFile(saved.fileId);
      return fail(res, 400, 'The file was empty.');
    }

    const doc = { _id: id, uid: req.uid, fileId: saved.fileId, contentType, ...fields };
    await store.upsertMemory(doc);
    if (existing) await store.deleteFile(existing.fileId);
    res.status(existing ? 200 : 201).json(present(doc));
  }));

  // Change who can see a memory, or its caption, without uploading again.
  app.patch('/memories/:id', auth, express.json({ limit: '4kb' }), wrap(async (req, res) => {
    const { id } = req.params;
    if (!isValidId(id)) return fail(res, 400, 'Bad memory id.');
    const existing = await store.getMemory(id);
    if (!existing) return fail(res, 404, 'Not found.');
    if (existing.uid !== req.uid) return fail(res, 403, 'Not yours.');

    const patch = {};
    if (req.body?.visibility !== undefined) {
      if (!VISIBILITIES.includes(req.body.visibility)) return fail(res, 400, 'Bad visibility.');
      patch.visibility = req.body.visibility;
    }
    if (req.body?.caption !== undefined) {
      patch.caption = typeof req.body.caption === 'string'
        ? req.body.caption.trim().slice(0, 300) || null
        : null;
    }
    await store.updateMemory(id, patch);
    res.json(present({ ...existing, ...patch }));
  }));

  // Unshare everything of mine (account deletion). Registered before :id.
  app.delete('/memories', auth, wrap(async (req, res) => {
    const mine = await store.listByOwner(req.uid);
    for (const m of mine) {
      await store.deleteMemory(m._id);
      await store.deleteFile(m.fileId);
    }
    res.json({ deleted: mine.length });
  }));

  app.delete('/memories/:id', auth, wrap(async (req, res) => {
    const { id } = req.params;
    if (!isValidId(id)) return fail(res, 400, 'Bad memory id.');
    const existing = await store.getMemory(id);
    if (!existing) return res.json({ deleted: 0 }); // already gone
    if (existing.uid !== req.uid) return fail(res, 403, 'Not yours.');
    await store.deleteMemory(id);
    await store.deleteFile(existing.fileId);
    res.json({ deleted: 1 });
  }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err?.type === 'entity.parse.failed' || err?.type === 'entity.too.large') {
      return fail(res, 400, 'Bad request.');
    }
    console.error(err);
    fail(res, 500, 'Something went wrong on the server.');
  });

  return app;
}
