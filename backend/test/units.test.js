import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { signedQuery, verifyMediaLink, MEDIA_LINK_SECONDS } from '../lib/media_token.js';
import {
  parseRange, parseUidList, parseShareFields, contentTypeAllowed, isValidId,
} from '../lib/validate.js';

describe('media links', () => {
  const now = Date.UTC(2026, 9, 14);
  const parse = (q) => Object.fromEntries(new URLSearchParams(q));

  test('a fresh link works for its file only', () => {
    const { e, t } = parse(signedQuery('s', 'file1', now));
    assert.equal(verifyMediaLink('s', 'file1', e, t, now), true);
    assert.equal(verifyMediaLink('s', 'file2', e, t, now), false);
    assert.equal(verifyMediaLink('other', 'file1', e, t, now), false);
  });
  test('it expires', () => {
    const { e, t } = parse(signedQuery('s', 'file1', now));
    assert.equal(verifyMediaLink('s', 'file1', e, t, now + (MEDIA_LINK_SECONDS - 5) * 1000), true);
    assert.equal(verifyMediaLink('s', 'file1', e, t, now + (MEDIA_LINK_SECONDS + 5) * 1000), false);
  });
  test('a longer expiry cannot be forged', () => {
    const { e, t } = parse(signedQuery('s', 'file1', now));
    assert.equal(verifyMediaLink('s', 'file1', Number(e) + 99999, t, now), false);
  });
  test('junk is refused, not thrown on', () => {
    assert.equal(verifyMediaLink('s', 'f', undefined, undefined), false);
    assert.equal(verifyMediaLink('s', 'f', 'abc', 'x'), false);
    assert.equal(verifyMediaLink('s', 'f', '9999999999', 'short'), false);
  });
});

describe('validation', () => {
  test('ranges', () => {
    assert.deepEqual(parseRange('bytes=0-9', 100), { start: 0, end: 9 });
    assert.deepEqual(parseRange('bytes=90-', 100), { start: 90, end: 99 });
    assert.deepEqual(parseRange('bytes=-10', 100), { start: 90, end: 99 });
    assert.deepEqual(parseRange('bytes=50-500', 100), { start: 50, end: 99 });
    assert.equal(parseRange('bytes=100-120', 100), null);
    assert.equal(parseRange('bytes=9-2', 100), null);
    assert.equal(parseRange('items=0-1', 100), null);
    assert.equal(parseRange('bytes=-', 100), null);
  });
  test('uid lists keep valid unique ids only', () => {
    assert.deepEqual(parseUidList('a1,b2,a1,../x,,c3'), ['a1', 'b2', 'c3']);
    assert.deepEqual(parseUidList(undefined), []);
  });
  test('ids', () => {
    assert.equal(isValidId('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'), true);
    assert.equal(isValidId('../etc/passwd'), false);
    assert.equal(isValidId('short'), false);
  });
  test('content types match the memory type', () => {
    assert.equal(contentTypeAllowed('photo', 'image/jpeg'), true);
    assert.equal(contentTypeAllowed('photo', 'image/png'), true);
    assert.equal(contentTypeAllowed('photo', 'image/webp'), true);
    assert.equal(contentTypeAllowed('photo', 'image/svg+xml'), false);
    assert.equal(contentTypeAllowed('photo', 'video/mp4'), false);
    assert.equal(contentTypeAllowed('video', 'video/mp4; codecs=x'), true);
    assert.equal(contentTypeAllowed('video', 'video/webm'), false);
    assert.equal(contentTypeAllowed('video', undefined), false);
  });
  test('share fields are cleaned and bounded', () => {
    const ok = parseShareFields({
      type: 'photo', visibility: 'public', caption: '  hi  ', lat: '95', lng: '10',
      displayName: 'x'.repeat(200),
    });
    assert.equal(ok.value.caption, 'hi');
    assert.equal(ok.value.latitude, null); // out of range
    assert.equal(ok.value.longitude, 10);
    assert.equal(ok.value.displayName.length, 60);
    assert.ok(parseShareFields({ type: 'photo', visibility: 'private' }).error);
    assert.ok(parseShareFields({ type: 'gif', visibility: 'public' }).error);
  });
});
