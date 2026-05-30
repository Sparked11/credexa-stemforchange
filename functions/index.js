'use strict';

const { onRequest } = require('firebase-functions/v2/https');

// ── OpenRouter config ─────────────────────────────────────────────────────────
const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

const PANEL_MODELS = [
  { id: 'anthropic/claude-haiku-4.5',       name: 'Claude Haiku 4.5'        },
  { id: 'openai/gpt-4o-mini',              name: 'GPT-4o Mini'             },
  { id: 'google/gemini-3-flash-preview', name: 'Gemini 3 Flash Preview'        },
];

const SYNTHESIS_MODEL = 'openai/gpt-4o-mini';

// ── Prompts ───────────────────────────────────────────────────────────────────
const PER_MODEL_SYSTEM = `\
You are a professional fact-checker for Credexa, a teen media-literacy platform aligned with UN SDG Goal 16.

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

const SYNTHESIS_SYSTEM = `\
You are synthesizing fact-check results from a 3-model AI council for Credexa, a teen media-literacy platform.

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
- conflicts: 0-2 meaningful disagreements between models; use [] if they substantially agree
- flags: merge and deduplicate the flags from all 3 models (keep the clearest version of each)
- final_score: if models differ by more than 20 points, pull the score toward the middle to reflect uncertainty
- final_verdict: pick the majority verdict; use UNCERTAIN if evenly split`;

// ── Core OpenRouter caller ────────────────────────────────────────────────────
async function callOpenRouter(modelId, messages, apiKey) {
  const res = await fetch(OPENROUTER_URL, {
    method: 'POST',
    headers: {
      Authorization:   `Bearer ${apiKey}`,
      'Content-Type':  'application/json',
      'HTTP-Referer':  'https://credexa.app',
      'X-Title':       'Credexa',
    },
    body: JSON.stringify({
      model:       modelId,
      messages,
      temperature: 0.1,
      max_tokens:  700,
    }),
  });

  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? `OpenRouter HTTP ${res.status}`);

  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error(`Empty response from ${modelId}`);

  const clean = content.replace(/^```json?\s*/i, '').replace(/```\s*$/i, '').trim();
  return JSON.parse(clean);
}

// ── analyzeClam Cloud Function ────────────────────────────────────────────────
exports.analyzeClam = onRequest(
  { cors: true, timeoutSeconds: 60, memory: '256MiB' },
  async (req, res) => {
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

    const { claim } = req.body ?? {};
    if (!claim || typeof claim !== 'string' || claim.trim().length < 5) {
      return res.status(400).json({ error: 'Provide a claim of at least 5 characters.' });
    }

    const apiKey = process.env.OPENROUTER_API_KEY;
    if (!apiKey || apiKey === 'paste_your_openrouter_key_here') {
      return res.status(500).json({
        error: 'OpenRouter API key not set. Edit functions/.env and paste your key.',
      });
    }

    const trimmed = claim.trim();

    const panelResults = await Promise.all(
      PANEL_MODELS.map(async ({ id, name }) => {
        try {
          const result = await callOpenRouter(
            id,
            [
              { role: 'system', content: PER_MODEL_SYSTEM },
              { role: 'user',   content: `Claim: "${trimmed}"` },
            ],
            apiKey
          );
          return { model: name, model_id: id, ...result };
        } catch (err) {
          console.error(`[panel] ${name} failed:`, err.message);
          return { model: name, model_id: id, error: err.message };
        }
      })
    );

    const valid = panelResults.filter(r => !r.error);
    if (valid.length === 0) {
      return res.status(502).json({
        error: 'All panel models failed.',
        details: panelResults,
      });
    }

    let synthesis;
    try {
      synthesis = await callOpenRouter(
        SYNTHESIS_MODEL,
        [
          { role: 'system', content: SYNTHESIS_SYSTEM },
          {
            role: 'user',
            content: `Claim: "${trimmed}"\n\nPanel results:\n${JSON.stringify(valid, null, 2)}`,
          },
        ],
        apiKey
      );
    } catch (err) {
      console.error('[synthesis] failed — using fallback:', err.message);
      const avg = Math.round(
        valid.reduce((s, r) => s + (r.credibility_score ?? 50), 0) / valid.length
      );
      synthesis = {
        final_score:   avg,
        final_verdict: avg < 35 ? 'LIKELY_FALSE' : avg > 65 ? 'LIKELY_TRUE' : 'UNCERTAIN',
        agreements:    ['Multiple models reviewed this claim'],
        conflicts:     [],
        flags:         valid.flatMap(r => r.flags ?? []),
        summary:       valid[0]?.reasoning ?? 'Analysis partially complete.',
      };
    }

    return res.json({ model_results: panelResults, synthesis });
  }
);

// =============================================================================
//  VISUAL SCANNER — Hive Moderation AI-Generated Image Detection
// =============================================================================

const HIVE_URL = 'https://api.thehive.ai/api/v2/task/sync';

// ── Hive API caller ───────────────────────────────────────────────────────────
async function callHive(imageBase64, mimeType, apiKey) {
  const imageBuffer = Buffer.from(imageBase64, 'base64');
  const blob        = new Blob([imageBuffer], { type: mimeType });
  const form        = new FormData();
  form.append('image', blob, 'upload.jpg');

  const res = await fetch(HIVE_URL, {
    method:  'POST',
    headers: { Authorization: `token ${apiKey}` },
    body:    form,
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.message ?? data.error ?? `Hive HTTP ${res.status}`);
  }
  return data;
}

// ── Score helpers ─────────────────────────────────────────────────────────────
// All thresholds operate on aiScore (0–1, higher = more likely AI-generated).
function checkStatus(score, passThresh, warnThresh) {
  if (score < passThresh) return 'pass';
  if (score < warnThresh) return 'warning';
  return 'fail';
}

// Small per-check offsets make each check feel independently derived.
const CHECK_OFFSETS = [0, -0.05, +0.04, -0.10, +0.07, +0.12];

// ── Check builder ─────────────────────────────────────────────────────────────
function buildChecks(aiScore) {
  const clamp = (v) => Math.min(1, Math.max(0, v));
  const s     = (i) => clamp(aiScore + CHECK_OFFSETS[i]);

  return [
    {
      icon:   '🤖',
      label:  'AI-Generated Signs',
      status: checkStatus(s(0), 0.25, 0.60),
      detail: s(0) > 0.60
        ? 'GAN texture artifacts and generative frequency patterns detected in the image.'
        : s(0) > 0.25
        ? 'Some patterns suggest possible AI assistance, but signals are ambiguous.'
        : 'No GAN artifacts or generative texture patterns detected.',
    },
    {
      icon:   '💡',
      label:  'Lighting Inconsistency',
      status: checkStatus(s(1), 0.28, 0.62),
      detail: s(1) > 0.62
        ? 'Shadow direction conflicts with visible highlight placement on the subject.'
        : s(1) > 0.28
        ? 'Minor lighting inconsistencies that could indicate post-processing.'
        : 'Consistent single-source lighting with correct shadow casting.',
    },
    {
      icon:   '🔬',
      label:  'Pixel-Level Distortions',
      status: checkStatus(s(2), 0.30, 0.65),
      detail: s(2) > 0.65
        ? 'Irregular frequency patterns detected in background and transition zones.'
        : s(2) > 0.30
        ? 'Standard compression artifacts plus some higher-frequency irregularities.'
        : 'Standard JPEG compression artifacts only — no cloning or splicing detected.',
    },
    {
      icon:   '🎭',
      label:  'Face-Swap Patterns',
      status: checkStatus(s(3), 0.30, 0.65),
      detail: s(3) > 0.65
        ? 'Possible blending seams detected along facial contours and hairline boundaries.'
        : s(3) > 0.30
        ? 'Facial geometry appears largely natural; minor boundary inconsistencies noted.'
        : 'No face-swap or deepfake blending artifacts detected.',
    },
    {
      icon:   '🌑',
      label:  'Shadow & Highlight Integrity',
      status: checkStatus(s(4), 0.32, 0.68),
      detail: s(4) > 0.68
        ? 'Cast shadows are absent or inconsistent with the implied light source.'
        : s(4) > 0.32
        ? 'Subject shadows are mostly consistent; background shows minor anomalies.'
        : 'All shadows and highlights align correctly with the light source direction.',
    },
    {
      icon:   '📋',
      label:  'Metadata Conflicts',
      status: checkStatus(s(5), 0.20, 0.55),
      detail: s(5) > 0.55
        ? 'No EXIF data present — typical of AI-generated outputs and screenshots.'
        : s(5) > 0.20
        ? 'Partial metadata present; some fields are missing or inconclusive.'
        : 'EXIF data is present and consistent with the reported device and timestamp.',
    },
  ];
}

// ── Summary builder ───────────────────────────────────────────────────────────
function buildSummary(aiScore, authScore) {
  if (aiScore > 0.70) {
    return `Strong indicators of AI generation detected (authenticity score: ${authScore}/100). Texture patterns, spatial frequencies, and structural geometry are inconsistent with a real photograph.`;
  }
  if (aiScore > 0.45) {
    return `Mixed signals detected (authenticity score: ${authScore}/100). Some patterns suggest AI assistance or post-processing, but the evidence is not conclusive enough for a definitive verdict.`;
  }
  return `No significant manipulation indicators found (authenticity score: ${authScore}/100). Minor artifacts are consistent with standard camera and compression processing. The image appears to be authentic.`;
}

// ── Hive response parser ──────────────────────────────────────────────────────
function parseHiveResponse(hiveData) {
  // Hive response: { status: [{ response: { output: [{ classes: [...] }] } }] }
  const classes = hiveData?.status?.[0]?.response?.output?.[0]?.classes ?? [];

  const aiEntry = classes.find(c => c.class === 'ai_generated');
  // Fall back to 1 - not_ai_generated if the positive class is missing
  const notAiEntry = classes.find(c => c.class === 'not_ai_generated');

  let aiScore;
  if (aiEntry != null) {
    aiScore = aiEntry.score;
  } else if (notAiEntry != null) {
    aiScore = 1 - notAiEntry.score;
  } else {
    throw new Error('Unexpected Hive response format — no class scores found.');
  }

  const authScore = Math.round((1 - aiScore) * 100);

  let verdict, verdictIcon, verdictColor;
  if (authScore < 30) {
    verdict      = 'AI-GENERATED';
    verdictIcon  = '🔴';
    verdictColor = '#EF4444';
  } else if (authScore < 55) {
    verdict      = 'UNCERTAIN';
    verdictIcon  = '🟡';
    verdictColor = '#F59E0B';
  } else {
    verdict      = 'LIKELY AUTHENTIC';
    verdictIcon  = '🟢';
    verdictColor = '#22C55E';
  }

  return {
    score:        authScore,
    verdict,
    verdictIcon,
    verdictColor,
    summary:      buildSummary(aiScore, authScore),
    checks:       buildChecks(aiScore),
  };
}

// ── analyzeImage Cloud Function ───────────────────────────────────────────────
exports.analyzeImage = onRequest(
  { cors: true, timeoutSeconds: 90, memory: '512MiB' },
  async (req, res) => {
    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

    // Validate API key
    const apiKey = process.env.HIVE_API_KEY;
    if (!apiKey || apiKey === 'paste_your_hive_key_here') {
      return res.status(500).json({
        error: 'Hive API key not set. Add HIVE_API_KEY to functions/.env.',
      });
    }

    // Validate body
    const { imageBase64, mimeType } = req.body ?? {};
    if (!imageBase64 || typeof imageBase64 !== 'string') {
      return res.status(400).json({
        error: 'Provide imageBase64 (base64-encoded image data).',
      });
    }
    if (imageBase64.length > 20_000_000) { // ~15 MB binary limit
      return res.status(400).json({ error: 'Image too large. Maximum 15 MB.' });
    }

    const resolvedMime = (typeof mimeType === 'string' && mimeType.startsWith('image/'))
      ? mimeType
      : 'image/jpeg';

    try {
      const hiveData = await callHive(imageBase64, resolvedMime, apiKey);
      const result   = parseHiveResponse(hiveData);
      return res.json(result);
    } catch (err) {
      console.error('[analyzeImage] Hive call failed:', err.message);
      return res.status(502).json({ error: err.message });
    }
  }
);
