import { createHmac, timingSafeEqual } from 'node:crypto';

/** How long a media link works after the feed hands it out. */
export const MEDIA_LINK_SECONDS = 6 * 3600;

const sign = (secret, fileId, expires) =>
  createHmac('sha256', secret).update(`${fileId}.${expires}`).digest('base64url');

/**
 * Photos and videos are loaded by the phone's image and video players, which
 * can't easily send a login header. So the feed gives each viewer a link that
 * works for a few hours and for that one file only.
 */
export function signedQuery(secret, fileId, nowMs = Date.now()) {
  const expires = Math.floor(nowMs / 1000) + MEDIA_LINK_SECONDS;
  return `e=${expires}&t=${sign(secret, fileId, expires)}`;
}

export function verifyMediaLink(secret, fileId, expires, token, nowMs = Date.now()) {
  const e = Number(expires);
  if (!Number.isInteger(e) || typeof token !== 'string') return false;
  if (e < Math.floor(nowMs / 1000)) return false;
  const want = Buffer.from(sign(secret, fileId, e));
  const got = Buffer.from(token);
  return want.length === got.length && timingSafeEqual(want, got);
}
