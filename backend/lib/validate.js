export const MAX_FILE_BYTES = 50 * 1024 * 1024;
export const MAX_MEMORIES_PER_USER = 300;
export const MAX_FRIENDS_IN_QUERY = 200;

export const VISIBILITIES = ['friends', 'public'];
export const TYPES = ['photo', 'video', 'voice'];

/** Audio capsules: voice notes pinned to a spot. */
export const MAX_VOICE_BYTES = 5 * 1024 * 1024;
export const MAX_CAPSULES_PER_SPOT = 2;
export const CAPSULE_SPOT_METERS = 50;
export const MAX_NEARBY_METERS = 2000;
export const REPORTS_TO_HIDE = 3;

const ID = /^[A-Za-z0-9-]{8,64}$/;
const UID = /^[A-Za-z0-9]{1,128}$/;

export const isValidId = (id) => typeof id === 'string' && ID.test(id);

export const ALLOWED_PHOTO_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
export const ALLOWED_VIDEO_CONTENT_TYPES = ['video/mp4'];
export const ALLOWED_VOICE_CONTENT_TYPES = [
  'audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac', 'audio/mpeg',
];

/** Content types the server accepts, by memory type. */
export function contentTypeAllowed(type, contentType) {
  const ct = String(contentType ?? '').split(';')[0].trim().toLowerCase();
  if (type === 'photo') return ALLOWED_PHOTO_CONTENT_TYPES.includes(ct);
  if (type === 'video') return ALLOWED_VIDEO_CONTENT_TYPES.includes(ct);
  if (type === 'voice') return ALLOWED_VOICE_CONTENT_TYPES.includes(ct);
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
  if (!TYPES.includes(type)) return { error: 'type must be photo, video or voice' };
  if (!VISIBILITIES.includes(query.visibility)) {
    return { error: 'visibility must be friends or public' };
  }
  const latitude = coord(query.lat, 90);
  const longitude = coord(query.lng, 180);
  // A capsule is a voice note left at a spot: it needs the spot.
  if (type === 'voice' && (latitude === null || longitude === null)) {
    return { error: 'An audio capsule needs a location.' };
  }
  return {
    value: {
      type,
      visibility: query.visibility,
      displayName: text(query.displayName, 60) ?? 'Explorer',
      caption: text(query.caption, 300),
      placeName: text(query.placeName, 120),
      latitude,
      longitude,
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

/** Metres between two { lat, lng } points (haversine). */
export function metersBetween(a, b) {
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}

/** GeoJSON point for MongoDB's 2dsphere index, or undefined. */
export function geoPoint(latitude, longitude) {
  return latitude === null || longitude === null
    ? undefined
    : { type: 'Point', coordinates: [longitude, latitude] };
}
