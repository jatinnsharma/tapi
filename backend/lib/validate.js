export const MAX_FILE_BYTES = 50 * 1024 * 1024;
export const MAX_MEMORIES_PER_USER = 300;
export const MAX_FRIENDS_IN_QUERY = 200;

export const VISIBILITIES = ['friends', 'public'];
export const TYPES = ['photo', 'video'];

const ID = /^[A-Za-z0-9-]{8,64}$/;
const UID = /^[A-Za-z0-9]{1,128}$/;

export const isValidId = (id) => typeof id === 'string' && ID.test(id);

export const ALLOWED_PHOTO_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
export const ALLOWED_VIDEO_CONTENT_TYPES = ['video/mp4'];

/** Content types the server accepts, by memory type. */
export function contentTypeAllowed(type, contentType) {
  const ct = String(contentType ?? '').split(';')[0].trim().toLowerCase();
  if (type === 'photo') return ALLOWED_PHOTO_CONTENT_TYPES.includes(ct);
  if (type === 'video') return ALLOWED_VIDEO_CONTENT_TYPES.includes(ct);
  return false;
}

const text = (v, max) => {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t.length === 0 ? null : t.slice(0, max);
};

const coord = (v, limit) => {
  if (v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) && Math.abs(n) <= limit ? n : null;
};

/** Reads the fields of a share request; returns { error } or { value }. */
export function parseShareFields(query) {
  const type = query.type;
  if (!TYPES.includes(type)) return { error: 'type must be photo or video' };
  if (!VISIBILITIES.includes(query.visibility)) {
    return { error: 'visibility must be friends or public' };
  }
  return {
    value: {
      type,
      visibility: query.visibility,
      displayName: text(query.displayName, 60) ?? 'Explorer',
      caption: text(query.caption, 300),
      placeName: text(query.placeName, 120),
      latitude: coord(query.lat, 90),
      longitude: coord(query.lng, 180),
      createdAt: Number.isFinite(Date.parse(query.createdAt))
        ? new Date(query.createdAt)
        : new Date(),
    },
  };
}

/** "uidA,uidB" -> ['uidA','uidB'] (valid, unique, capped). */
export function parseUidList(value) {
  if (typeof value !== 'string') return [];
  const out = new Set();
  for (const part of value.split(',')) {
    if (UID.test(part)) out.add(part);
    if (out.size >= MAX_FRIENDS_IN_QUERY) break;
  }
  return [...out];
}

/** "bytes=0-99" -> {start,end} within [0,size), or null if unusable. */
export function parseRange(header, size) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(header ?? '');
  if (!m || (m[1] === '' && m[2] === '') || size <= 0) return null;
  let start;
  let end;
  if (m[1] === '') {
    const n = Number(m[2]);
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = Number(m[1]);
    end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  }
  return start <= end && start < size ? { start, end } : null;
}
