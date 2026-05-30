'use strict';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const MODEL = 'openai/gpt-4o-mini';

function currentDate() {
  return new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

const ICON_MAP = {
  'Loaded Language':        '🔥',
  'Fear Appeal':            '😱',
  'Vilification':           '🎭',
  'Us-vs-Them Framing':     '⚔️',
  'Absolute Language':      '🚨',
  'Missing Balance':        '📍',
  'One-Sided Framing':      '📣',
  'Misleading Stats':       '📊',
  'Sensationalism':         '💥',
  'Unverified Claim':       '❓',
  'Emotional Manipulation': '💔',
  'Scapegoating':           '🐐',
};

function buildSystem() {
  return `\
You are a professional media-bias analyst and neutral-language editor for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.
Today's date is ${currentDate()}. Do NOT treat any date on or before today as a future date.

The user will provide a text snippet (headline, social post, or article excerpt).

Your tasks:
1. Identify every bias technique used: loaded/emotional language, one-sided framing, vilification, fear appeals, absolute language, misleading stats, unverified claims presented as fact, us-vs-them framing, scapegoating, sensationalism.
2. Rewrite the text in factual, balanced, neutral language — keep all true facts, remove all manipulation.
3. List each specific change you made.

Respond with ONLY a valid JSON object. Do NOT use markdown fences. Do NOT add text outside the JSON.

{
  "bias_score": <integer 0-100; 0 = perfectly neutral, 100 = maximum bias>,
  "neutral_text": "<full neutral rewrite>",
  "changes": [
    {
      "type": "<bias pattern, e.g. 'Loaded Language', 'Fear Appeal', 'Us-vs-Them Framing', 'Absolute Language', 'Missing Balance', 'One-Sided Framing', 'Misleading Stats', 'Sensationalism', 'Unverified Claim', 'Vilification', 'Emotional Manipulation', 'Scapegoating'>",
      "original": "<exact problematic phrase from the input>",
      "rewritten": "<the neutral replacement used in your rewrite>",
      "explanation": "<one sentence explaining why this phrase is manipulative>"
    }
  ],
  "bias_types": ["<top 1-3 bias category names found>"],
  "perspectives": {
    "left":   { "label": "Progressive Take",   "text": "<~40-word reframe emphasising systemic causes, equity, or community impact — factual but through that lens>", "note": "<one phrase describing the rhetorical choice made>" },
    "center": { "label": "Neutral / Factual",  "text": "<same as neutral_text — copy it here>",                                                                     "note": "Sticks strictly to verifiable facts with no advocacy" },
    "right":  { "label": "Conservative Take",  "text": "<~40-word reframe emphasising individual responsibility, free markets, or limited government — factual but through that lens>", "note": "<one phrase describing the rhetorical choice made>" }
  }
}

Rules:
- bias_score: 0-20 = mostly neutral, 21-50 = mildly biased, 51-80 = clearly biased, 81-100 = highly manipulative
- If text is already neutral (bias_score < 15): set neutral_text = original text, changes = []
- List 1-6 specific changes; pick the most impactful ones
- neutral_text and perspective texts should be similar length to the original
- Write explanations a 14-year-old can understand
- Perspectives must be fair, factual representations — not caricatures or strawmen of either side`;
}

function buildSystemImage() {
  return `\
You are a professional media-bias analyst and neutral-language editor for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.
Today's date is ${currentDate()}. Do NOT treat any date on or before today as a future date.

The user will share an image (e.g. a screenshot of a social media post). Your tasks:
1. Perform OCR: extract ALL visible text from the image.
2. Analyze it for bias patterns and rewrite in neutral language.
3. List each specific change made.

Respond with ONLY a valid JSON object. Do NOT use markdown fences. Do NOT add text outside the JSON.

{
  "extracted_text": "<all text you extracted from the image>",
  "bias_score": <integer 0-100>,
  "neutral_text": "<full neutral rewrite of the extracted text>",
  "changes": [
    {
      "type": "<bias pattern name>",
      "original": "<exact problematic phrase>",
      "rewritten": "<neutral replacement>",
      "explanation": "<one sentence for a 14-year-old>"
    }
  ],
  "bias_types": ["<top bias categories found>"],
  "perspectives": {
    "left":   { "label": "Progressive Take",  "text": "<~40-word reframe through a progressive lens>", "note": "<one phrase on the rhetorical choice>" },
    "center": { "label": "Neutral / Factual", "text": "<same as neutral_text>",                        "note": "Sticks strictly to verifiable facts" },
    "right":  { "label": "Conservative Take", "text": "<~40-word reframe through a conservative lens>","note": "<one phrase on the rhetorical choice>" }
  }
}

Rules:
- Perspectives must be fair, factual representations — not caricatures of either side
- Write for a 14-year-old audience`;
}

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

async function callGPT(messages, maxTokens = 1400) {
  const res = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      Authorization:  `Bearer ${process.env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://credexa.app',
      'X-Title':      'Credexa',
    },
    body: JSON.stringify({ model: MODEL, messages, temperature: 0.15, max_tokens: maxTokens }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? `OpenRouter HTTP ${res.status}`);
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('Empty response from GPT');
  const clean = content.replace(/^```json?\s*/i, '').replace(/```\s*$/i, '').trim();
  return JSON.parse(clean);
}

module.exports = async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'OPENROUTER_API_KEY not configured.' });

  const { text, imageBase64, mimeType } = req.body ?? {};
  const isImage = typeof imageBase64 === 'string' && imageBase64.length > 0;

  if (!isImage && (!text || typeof text !== 'string' || text.trim().length < 5))
    return res.status(400).json({ error: 'Provide text of at least 5 characters, or imageBase64.' });
  if (isImage && imageBase64.length > 5_000_000)
    return res.status(400).json({ error: 'Image too large. Please use an image under ~3 MB.' });

  const resolvedMime = (typeof mimeType === 'string' && mimeType.startsWith('image/')) ? mimeType : 'image/jpeg';

  try {
    let result;
    if (isImage) {
      result = await callGPT([
        { role: 'system', content: buildSystemImage() },
        {
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: `data:${resolvedMime};base64,${imageBase64}` } },
            { type: 'text', text: 'Extract all text from this image, then de-bias it. Return the JSON from your system prompt.' },
          ],
        },
      ], 1600);
    } else {
      result = await callGPT([
        { role: 'system', content: buildSystem() },
        { role: 'user', content: `Text to de-bias:\n\n"${text.trim()}"` },
      ]);
    }

    // Inject icon into each change based on type
    if (Array.isArray(result.changes)) {
      result.changes = result.changes.map(c => ({
        ...c,
        icon: ICON_MAP[c.type] ?? '🔍',
      }));
    }

    return res.json(result);
  } catch (err) {
    console.error('[debias]', err.message);
    return res.status(502).json({ error: err.message });
  }
};
