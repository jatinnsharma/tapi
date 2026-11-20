// Sightseer Lens: "what am I looking at?" for a photo, answered by Gemini.
// The Gemini key lives only on this server (GEMINI_API_KEY), never in the app.

export const LENS_MAX_BYTES = 4 * 1024 * 1024;
export const LENS_PER_DAY = 30;
export const LENS_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

const LENS_SCHEMA = {
  type: 'OBJECT',
  properties: {
    name: { type: 'STRING' },
    style: { type: 'STRING' },
    era: { type: 'STRING' },
    summary: { type: 'STRING' },
    details: { type: 'ARRAY', items: { type: 'STRING' } },
    confidence: { type: 'STRING', enum: ['high', 'medium', 'low'] },
  },
  required: ['name', 'summary', 'details', 'confidence'],
};

/** The question sent with the photo. */
export function lensPrompt({ lat, lng, near }) {
  const where = [
    Number.isFinite(lat) && Number.isFinite(lng)
      ? `The photo was taken at latitude ${lat.toFixed(5)}, longitude ${lng.toFixed(5)}`
      : 'The photo was taken in India',
    near ? `, near ${near}` : '',
    '.',
  ].join('');
  return [
    'You are an expert Indian archaeologist and cultural historian.',
    where,
    'Identify what the photo shows (a monument, building, sculpture, painting,',
    'inscription or object), its architectural or artistic style, and its era.',
    'Write a summary of two short paragraphs (under 120 words in all) on its',
    'history and meaning, and exactly 3 hidden details a visitor can look for',
    'right now. If you are not sure what it is, say so, set confidence to "low"',
    'and describe only what is visible. Never invent names or dates.',
  ].join(' ');
}

const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

/** Cleans Gemini's answer into the shape the app reads; null if unusable. */
export function parseLensAnswer(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const name = text(raw.name, 120);
  const summary = text(raw.summary, 1200);
  if (!name || !summary) return null;
  const details = Array.isArray(raw.details)
    ? raw.details.map((d) => text(d, 300)).filter(Boolean).slice(0, 3)
    : [];
  return {
    name,
    style: text(raw.style, 120) || null,
    era: text(raw.era, 120) || null,
    summary,
    details,
    confidence: ['high', 'medium', 'low'].includes(raw.confidence)
      ? raw.confidence
      : 'low',
  };
}

/**
 * Asks Gemini about [image]. Returns the parsed JSON object it answered with.
 * Throws on a network or API error.
 */
export function createGeminiVision({ apiKey, model = 'gemini-flash-latest', fetchImpl = fetch }) {
  return async (image, mimeType, context) => {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify({
        contents: [{
          parts: [
            { text: lensPrompt(context) },
            { inline_data: { mime_type: mimeType, data: image.toString('base64') } },
          ],
        }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: LENS_SCHEMA,
          maxOutputTokens: 1024,
          temperature: 0.3,
        },
      }),
      signal: AbortSignal.timeout(45000),
    });
    if (!res.ok) throw new Error(`Gemini answered ${res.status}`);
    const body = await res.json();
    const part = body?.candidates?.[0]?.content?.parts?.[0]?.text;
    return JSON.parse(part ?? 'null');
  };
}

/** At most [perDay] uses per uid in any 24 hours (kept in memory). */
export function createDailyLimiter(perDay = LENS_PER_DAY, now = () => Date.now()) {
  const uses = new Map();
  return (uid) => {
    const dayAgo = now() - 24 * 3600 * 1000;
    const recent = (uses.get(uid) ?? []).filter((t) => t > dayAgo);
    if (recent.length >= perDay) {
      uses.set(uid, recent);
      return false;
    }
    recent.push(now());
    uses.set(uid, recent);
    return true;
  };
}
