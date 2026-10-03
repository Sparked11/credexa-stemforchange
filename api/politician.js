'use strict';

// Model-council fill for the Election Integrity page. Used only where the app
// has no sourced promises or votes for a politician. Three models answer
// independently; an item is kept only if at least MIN_AGREE models agree on it.
// Output is an AI estimate, so the app labels it as not verified.

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

const PANEL_MODELS = [
  { id: 'anthropic/claude-haiku-4.5',    name: 'Claude Haiku 4.5'       },
  { id: 'openai/gpt-4o-mini',            name: 'GPT-4o Mini'            },
  { id: 'google/gemini-3-flash-preview', name: 'Gemini 3 Flash Preview' },
];

const MIN_AGREE = 2;
const MAX_ITEMS = 5;

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function currentDate() {
  return new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

function buildMessages(name) {
  const system = `You are a non-partisan political record assistant for Credexa, a teen media-literacy app. Today's date is ${currentDate()}.
List ONLY well-established, verifiable items about the named official from your knowledge. Do not invent items. If you are not confident an item is real and accurate, leave it out. Respond ONLY with raw JSON, no markdown.`;

  const user = `Official: ${name}

Return JSON in exactly this shape:
{
  "promises": [
    {"title": "max 55 chars", "status": "completed" | "in_progress" | "unfulfilled", "description": "max 110 chars", "date": "year"}
  ],
  "votes": [
    {"bill_name": "official or common name", "bill_number": "e.g. H.R. 1319, or empty", "vote": "Yes" | "No" | "Abstain", "date": "e.g. March 2021", "summary": "max 95 chars"}
  ]
}
Up to ${MAX_ITEMS} of each, the most significant. Use empty arrays when unsure. Never invent bill numbers.`;

  return [
    { role: 'system', content: system },
    { role: 'user', content: user },
  ];
}

async function callModel(modelId, messages, apiKey) {
  const res = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      Authorization:  `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://credexa.app',
      'X-Title':      'Credexa',
    },
    body: JSON.stringify({ model: modelId, messages, temperature: 0.1, max_tokens: 1200 }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? `OpenRouter HTTP ${res.status}`);
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error(`Empty response from ${modelId}`);
  const clean = content.replace(/^```json?\s*/i, '').replace(/```\s*$/i, '').trim();
  return JSON.parse(clean);
}

// Lowercase word set, ignoring short filler words, for fuzzy title matching.
function tokens(s) {
  return new Set(
    String(s || '')
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w.length > 2),
  );
}

function similar(a, b) {
  const ta = tokens(a);
  const tb = tokens(b);
  if (ta.size === 0 || tb.size === 0) return false;
  let common = 0;
  for (const w of ta) if (tb.has(w)) common++;
  return common / Math.min(ta.size, tb.size) >= 0.6;
}

// Keeps each item only if at least MIN_AGREE distinct models produced a match.
function consensus(lists, matches, build) {
  const out = [];
  lists.forEach((items, i) => {
    for (const item of items) {
      if (out.some((o) => matches(o.item, item))) continue;
      const agreeing = new Set([i]);
      lists.forEach((other, j) => {
        if (j !== i && other.some((x) => matches(item, x))) agreeing.add(j);
      });
      if (agreeing.size >= MIN_AGREE) out.push({ item: build(item), agreed: agreeing.size });
    }
  });
  return out.slice(0, MAX_ITEMS);
}

module.exports = async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'OPENROUTER_API_KEY not configured.' });

  const name = String(req.body?.name ?? '').trim();
  if (name.length < 2 || name.length > 80) {
    return res.status(400).json({ error: 'name must be 2–80 characters.' });
  }

  const messages = buildMessages(name);
  const settled = await Promise.allSettled(
    PANEL_MODELS.map((m) => callModel(m.id, messages, apiKey)),
  );
  const answers = settled.filter((r) => r.status === 'fulfilled').map((r) => r.value);

  if (answers.length < MIN_AGREE) {
    return res.status(200).json({ promises: [], votes: [], models_responded: answers.length });
  }

  const promiseLists = answers.map((a) => (Array.isArray(a.promises) ? a.promises : []));
  const voteLists    = answers.map((a) => (Array.isArray(a.votes) ? a.votes : []));

  const promises = consensus(
    promiseLists,
    (x, y) => similar(x.title, y.title),
    (p) => ({
      title: String(p.title ?? ''),
      status: ['completed', 'in_progress', 'unfulfilled'].includes(p.status) ? p.status : 'in_progress',
      description: String(p.description ?? ''),
      date: String(p.date ?? ''),
    }),
  );

  // A vote counts only when the same bill is named and the same way by 2+ models.
  const votes = consensus(
    voteLists,
    (x, y) => similar(x.bill_name, y.bill_name) &&
      String(x.vote ?? '').toLowerCase() === String(y.vote ?? '').toLowerCase(),
    (v) => ({
      bill_name: String(v.bill_name ?? ''),
      bill_number: String(v.bill_number ?? ''),
      vote: String(v.vote ?? ''),
      date: String(v.date ?? ''),
      summary: String(v.summary ?? ''),
    }),
  );

  return res.status(200).json({
    promises: promises.map((p) => ({ ...p.item, agreed: p.agreed })),
    votes: votes.map((v) => ({ ...v.item, agreed: v.agreed })),
    models_responded: answers.length,
  });
};
