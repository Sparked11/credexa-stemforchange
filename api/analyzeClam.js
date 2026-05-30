'use strict';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

const PANEL_MODELS = [
  { id: 'anthropic/claude-haiku-4.5',     name: 'Claude Haiku 4.5'        },
  { id: 'openai/gpt-4o-mini',             name: 'GPT-4o Mini'             },
  { id: 'google/gemini-3-flash-preview',  name: 'Gemini 3 Flash Preview'  },
];

const SYNTHESIS_MODEL = 'openai/gpt-4o-mini';

function currentDateLine() {
  return `Today's date is ${new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}. Do NOT treat any date on or before today as a "future" date.`;
}

function buildPerModelSystem() {
  return `\
You are a professional fact-checker for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.
${currentDateLine()}

Analyze the claim the user provides and respond with ONLY a valid JSON object matching this exact schema.
Do NOT wrap it in markdown code fences. Do NOT add any text outside the JSON.

{
  "credibility_score": <integer 0-100, where 0 = completely false, 100 = completely true>,
  "verdict": <"LIKELY_TRUE" | "UNCERTAIN" | "LIKELY_FALSE" | "SATIRE">,
  "confidence": <"HIGH" | "MEDIUM" | "LOW">,
  "reasoning": "<2-3 sentences in plain language explaining your verdict>",
  "flags": [
    {
      "type": <"EMOTIONAL_LANGUAGE" | "NO_SOURCE" | "KNOWN_PATTERN" | "MISLEADING_STATS" | "OUTDATED" | "SATIRE">,
      "quote": "<short verbatim excerpt from the claim that triggered this flag>",
      "explanation": "<one sentence why this is a red flag>"
    }
  ]
}`;
}

function buildPerModelSystemImage() {
  return `\
You are a professional fact-checker for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.
${currentDateLine()}

The user will share an image (e.g. a screenshot of a social media post). Your tasks:
1. Perform OCR: extract ALL visible text from the image.
2. Fact-check that extracted text as a claim.
3. Respond with ONLY a valid JSON object matching this exact schema.
Do NOT wrap it in markdown code fences. Do NOT add any text outside the JSON.

{
  "extracted_text": "<all text you extracted from the image via OCR>",
  "credibility_score": <integer 0-100, where 0 = completely false, 100 = completely true>,
  "verdict": <"LIKELY_TRUE" | "UNCERTAIN" | "LIKELY_FALSE" | "SATIRE">,
  "confidence": <"HIGH" | "MEDIUM" | "LOW">,
  "reasoning": "<2-3 sentences in plain language explaining your verdict>",
  "flags": [
    {
      "type": <"EMOTIONAL_LANGUAGE" | "NO_SOURCE" | "KNOWN_PATTERN" | "MISLEADING_STATS" | "OUTDATED" | "SATIRE">,
      "quote": "<short verbatim excerpt from the extracted text that triggered this flag>",
      "explanation": "<one sentence why this is a red flag>"
    }
  ]
}`;
}

function buildSynthesisSystem() {
  return `\
You are synthesizing fact-check results from a 3-model AI council for Credexa, a teen media-literacy platform.
${currentDateLine()}

Given the original claim and JSON results from 3 models, produce ONLY a valid JSON object.
Do NOT wrap it in markdown code fences. Do NOT add any text outside the JSON.

{
  "final_score": <integer 0-100 — weighted consensus score>,
  "final_verdict": <"LIKELY_TRUE" | "UNCERTAIN" | "LIKELY_FALSE" | "SATIRE">,
  "agreements": ["<string>"],
  "conflicts": ["<string>"],
  "flags": [{ "type": "<string>", "quote": "<string>", "explanation": "<string>" }],
  "summary": "<2-3 plain-English sentences a 14-year-old can understand>"
}

Rules:
- agreements: 1-3 specific points ALL models agree on
- conflicts: 0-2 meaningful disagreements; use [] if they substantially agree
- flags: merge and deduplicate from all 3 models
- final_score: if models differ by more than 20 points, pull toward the middle
- final_verdict: pick the majority verdict; use UNCERTAIN if evenly split`;
}

function isUrl(str) {
  return /^https?:\/\//i.test(str);
}

async function fetchUrlText(url) {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    let html;
    try {
      const res = await fetch(url, {
        headers: {
          'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
        redirect: 'follow',
        signal: controller.signal,
      });
      clearTimeout(timeout);
      if (!res.ok) return null;
      html = await res.text();
    } finally {
      clearTimeout(timeout);
    }
    // og:description usually contains the post caption on Instagram/TikTok/Twitter
    const desc = html.match(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']{10,})["']/i)?.[1]
               || html.match(/<meta[^>]+content=["']([^"']{10,})["'][^>]+property=["']og:description["']/i)?.[1];
    const title = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']{5,})["']/i)?.[1]
                || html.match(/<meta[^>]+content=["']([^"']{5,})["'][^>]+property=["']og:title["']/i)?.[1];
    const decode = (s) => s
      ? s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'")
      : null;
    return decode(desc) || decode(title) || null;
  } catch {
    return null;
  }
}

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

async function callOpenRouter(modelId, messages, apiKey, maxTokens = 700) {
  const res = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      Authorization:  `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://credexa.app',
      'X-Title':      'Credexa',
    },
    body: JSON.stringify({ model: modelId, messages, temperature: 0.1, max_tokens: maxTokens }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? `OpenRouter HTTP ${res.status}`);
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error(`Empty response from ${modelId}`);
  const clean = content.replace(/^```json?\s*/i, '').replace(/```\s*$/i, '').trim();
  return JSON.parse(clean);
}

function buildImageUserMessage(imageBase64, mimeType) {
  return {
    role: 'user',
    content: [
      { type: 'image_url', image_url: { url: `data:${mimeType};base64,${imageBase64}` } },
      { type: 'text', text: 'Extract all visible text from this image, then fact-check it. Respond with the JSON schema from your system prompt.' },
    ],
  };
}

module.exports = async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'OPENROUTER_API_KEY not configured.' });

  const { claim, imageBase64, mimeType } = req.body ?? {};
  const isImage = typeof imageBase64 === 'string' && imageBase64.length > 0;

  if (!isImage && (!claim || typeof claim !== 'string' || claim.trim().length < 5))
    return res.status(400).json({ error: 'Provide a claim of at least 5 characters, or an imageBase64.' });
  if (isImage && imageBase64.length > 5_000_000)
    return res.status(400).json({ error: 'Image too large. Please use an image under ~3 MB.' });

  const trimmed = claim?.trim() ?? '';
  const resolvedMime = (typeof mimeType === 'string' && mimeType.startsWith('image/')) ? mimeType : 'image/jpeg';

  // If the claim is a URL, fetch the page and extract post text via OG meta tags
  let sourceUrl = null;
  let extractedClaim = null;
  let effectiveClaim = trimmed;

  if (!isImage && isUrl(trimmed)) {
    sourceUrl = trimmed;
    extractedClaim = await fetchUrlText(trimmed);
    if (extractedClaim) {
      effectiveClaim = extractedClaim;
      console.log(`[url] Extracted from ${trimmed}: "${extractedClaim.slice(0, 100)}"`);
    } else {
      console.log(`[url] Could not extract text from ${trimmed}, using URL as claim`);
    }
  }

  const panelResults = await Promise.all(
    PANEL_MODELS.map(async ({ id, name }) => {
      try {
        const systemPrompt = isImage ? buildPerModelSystemImage() : buildPerModelSystem();
        const userMessage  = isImage
          ? buildImageUserMessage(imageBase64, resolvedMime)
          : { role: 'user', content: `Claim: "${effectiveClaim}"` };
        const result = await callOpenRouter(id,
          [{ role: 'system', content: systemPrompt }, userMessage],
          apiKey, isImage ? 1000 : 700);
        return { model: name, model_id: id, ...result };
      } catch (err) {
        console.error(`[panel] ${name} failed:`, err.message);
        return { model: name, model_id: id, error: err.message };
      }
    })
  );

  const valid = panelResults.filter(r => !r.error);
  if (valid.length === 0)
    return res.status(502).json({ error: 'All panel models failed.', details: panelResults });

  const synthesisContext = isImage
    ? `[Image analyzed via OCR]\n\nPanel results:\n${JSON.stringify(valid, null, 2)}`
    : `Claim: "${effectiveClaim}"\n\nPanel results:\n${JSON.stringify(valid, null, 2)}`;

  let synthesis;
  try {
    synthesis = await callOpenRouter(SYNTHESIS_MODEL,
      [{ role: 'system', content: buildSynthesisSystem() },
       { role: 'user', content: synthesisContext }],
      apiKey);
  } catch (err) {
    console.error('[synthesis] failed — using fallback:', err.message);
    const avg = Math.round(valid.reduce((s, r) => s + (r.credibility_score ?? 50), 0) / valid.length);
    synthesis = {
      final_score:   avg,
      final_verdict: avg < 35 ? 'LIKELY_FALSE' : avg > 65 ? 'LIKELY_TRUE' : 'UNCERTAIN',
      agreements:    ['Multiple models reviewed this claim'],
      conflicts:     [],
      flags:         valid.flatMap(r => r.flags ?? []),
      summary:       valid[0]?.reasoning ?? 'Analysis partially complete.',
    };
  }

  const responseBody = { model_results: panelResults, synthesis };
  if (sourceUrl) responseBody.source_url = sourceUrl;
  if (extractedClaim) responseBody.extracted_claim = extractedClaim;
  return res.json(responseBody);
};
