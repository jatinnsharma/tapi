// Sightseer Lens: photo in, cleaned Gemini answer out; key stays server-side.
import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../lib/app.js';
import {
  createDailyLimiter, createGeminiVision, lensPrompt, parseLensAnswer,
} from '../lib/lens.js';
import { createMemoryStore } from './memory_store.js';

const verifyToken = async (t) => {
  if (!t.startsWith('good-')) throw new Error('bad token');
  return t.slice(5);
};
const JPEG = Buffer.from('FFD8FFE000104A4649460001', 'hex');

function start(opts) {
  const app = createApp({ verifyToken, store: createMemoryStore(), mediaSecret: 's', ...opts });
  const server = app.listen(0);
  return { server, base: `http://127.0.0.1:${server.address().port}` };
}
const ask = (base, { uid = 'alice', body = JPEG, type = 'image/jpeg', q = 'lat=25.31&lng=83.01&near=Assi%20Ghat' } = {}) =>
  fetch(`${base}/lens?${q}`, {
    method: 'POST',
    headers: { authorization: `Bearer good-${uid}`, 'content-type': type },
    body,
  });

describe('POST /lens', () => {
  let seen;
  let s;
  before(() => {
    s = start({
      askVision: async (image, mime, ctx) => {
        seen = { bytes: image.length, mime, ctx };
        return {
          name: 'Nataraja bronze', style: 'Chola', era: '11th century',
          summary: 'Shiva as the cosmic dancer.',
          details: ['a', 'b', 'c', 'd'], confidence: 'very',
        };
      },
      lensLimiter: createDailyLimiter(2),
    });
  });
  after(() => s.server.close());

  test('answers with the cleaned identification', async () => {
    const r = await ask(s.base);
    assert.equal(r.status, 200);
    const body = await r.json();
    assert.equal(body.name, 'Nataraja bronze');
    assert.deepEqual(body.details, ['a', 'b', 'c']); // Capped at 3.
    assert.equal(body.confidence, 'low'); // Unknown value -> low.
    assert.equal(seen.mime, 'image/jpeg');
    assert.equal(seen.bytes, JPEG.length);
    assert.equal(seen.ctx.near, 'Assi Ghat');
    assert.equal(seen.ctx.lat, 25.31);
  });

  test('only photos', async () => {
    assert.equal((await ask(s.base, { uid: 'bob', type: 'text/plain' })).status, 415);
  });

  test('a daily limit per person', async () => {
    assert.equal((await ask(s.base, { uid: 'carol' })).status, 200);
    assert.equal((await ask(s.base, { uid: 'carol' })).status, 200);
    assert.equal((await ask(s.base, { uid: 'carol' })).status, 429);
    assert.equal((await ask(s.base, { uid: 'dave' })).status, 200);
  });

  test('needs a login', async () => {
    const r = await fetch(`${s.base}/lens`, {
      method: 'POST', headers: { 'content-type': 'image/jpeg' }, body: JPEG,
    });
    assert.equal(r.status, 401);
  });
});

test('/lens without a Gemini key says it is not set up', async () => {
  const s = start({});
  try {
    assert.equal((await ask(s.base)).status, 503);
  } finally {
    s.server.close();
  }
});

test('/lens reports a Gemini failure or a useless answer as 502', async () => {
  for (const askVision of [async () => { throw new Error('down'); }, async () => ({ name: '' })]) {
    const s = start({ askVision });
    try {
      assert.equal((await ask(s.base)).status, 502);
    } finally {
      s.server.close();
    }
  }
});

test('the prompt carries the place and forbids invention', () => {
  const p = lensPrompt({ lat: 25.31, lng: 83.01, near: 'Assi Ghat' });
  assert.match(p, /near Assi Ghat/);
  assert.match(p, /25\.31000/);
  assert.match(p, /Never invent/);
  assert.match(lensPrompt({ lat: NaN, lng: NaN, near: null }), /taken in India/);
});

test('answers are cleaned; unusable ones are null', () => {
  assert.equal(parseLensAnswer(null), null);
  assert.equal(parseLensAnswer({ name: 'x' }), null);
  const a = parseLensAnswer({ name: ' Temple ', summary: 'Old.', details: [' a ', 7, ''], confidence: 'high' });
  assert.deepEqual(a, { name: 'Temple', style: null, era: null, summary: 'Old.', details: ['a'], confidence: 'high' });
});

test('Gemini is asked with the key in a header, never the URL', async () => {
  let call;
  const vision = createGeminiVision({
    apiKey: 'secret-key',
    model: 'test-model',
    fetchImpl: async (url, init) => {
      call = { url, init };
      return {
        ok: true,
        json: async () => ({
          candidates: [{ content: { parts: [{ text: '{"name":"Ghat","summary":"s","details":[],"confidence":"low"}' }] } }],
        }),
      };
    },
  });
  const raw = await vision(JPEG, 'image/jpeg', { lat: 1, lng: 2, near: null });
  assert.equal(raw.name, 'Ghat');
  assert.ok(!call.url.includes('secret-key'));
  assert.equal(call.init.headers['x-goog-api-key'], 'secret-key');
  assert.match(call.url, /models\/test-model:generateContent$/);
  const body = JSON.parse(call.init.body);
  assert.equal(body.contents[0].parts[1].inline_data.mime_type, 'image/jpeg');
  assert.equal(body.generationConfig.responseMimeType, 'application/json');
});
