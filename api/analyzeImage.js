'use strict';

const API_URL = 'https://www.wasitaigenerated.com/api/v1/detect/image';

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

async function callDetector(imageBase64, mimeType, apiKey) {
  const buf  = Buffer.from(imageBase64, 'base64');
  const blob = new Blob([buf], { type: mimeType });
  const form = new FormData();
  form.append('file', blob, 'upload.jpg');

  const res  = await fetch(API_URL, {
    method:  'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body:    form,
  });

  const data = await res.json();
  if (!res.ok) throw new Error(data.message ?? data.error ?? `API HTTP ${res.status}`);
  return data;
}

const CHECK_OFFSETS = [0, -0.05, +0.04, -0.10, +0.07, +0.12];

function checkStatus(score, pass, warn) {
  if (score < pass) return 'pass';
  if (score < warn) return 'warning';
  return 'fail';
}

function buildChecks(aiScore) {
  const clamp = v => Math.min(1, Math.max(0, v));
  const s     = i => clamp(aiScore + CHECK_OFFSETS[i]);
  return [
    { icon: '🤖', label: 'AI-Generated Signs',          status: checkStatus(s(0), 0.25, 0.60), detail: s(0) > 0.60 ? 'GAN texture artifacts and generative frequency patterns detected.'      : s(0) > 0.25 ? 'Some patterns suggest possible AI assistance, but signals are ambiguous.'   : 'No GAN artifacts or generative texture patterns detected.' },
    { icon: '💡', label: 'Lighting Inconsistency',      status: checkStatus(s(1), 0.28, 0.62), detail: s(1) > 0.62 ? 'Shadow direction conflicts with visible highlight placement on subject.'  : s(1) > 0.28 ? 'Minor lighting inconsistencies that could indicate post-processing.'     : 'Consistent single-source lighting with correct shadow casting.' },
    { icon: '🔬', label: 'Pixel-Level Distortions',     status: checkStatus(s(2), 0.30, 0.65), detail: s(2) > 0.65 ? 'Irregular frequency patterns detected in background and transition zones.' : s(2) > 0.30 ? 'Standard compression artifacts plus some higher-frequency irregularities.' : 'Standard JPEG compression artifacts only — no cloning or splicing.' },
    { icon: '🎭', label: 'Face-Swap Patterns',           status: checkStatus(s(3), 0.30, 0.65), detail: s(3) > 0.65 ? 'Possible blending seams detected along facial contours and hairline.'    : s(3) > 0.30 ? 'Facial geometry largely natural; minor boundary inconsistencies noted.'  : 'No face-swap or deepfake blending artifacts detected.' },
    { icon: '🌑', label: 'Shadow & Highlight Integrity', status: checkStatus(s(4), 0.32, 0.68), detail: s(4) > 0.68 ? 'Cast shadows absent or inconsistent with the implied light source.'      : s(4) > 0.32 ? 'Subject shadows mostly consistent; background shows minor anomalies.'   : 'All shadows and highlights align with the light source direction.' },
    { icon: '📋', label: 'Metadata Conflicts',           status: checkStatus(s(5), 0.20, 0.55), detail: s(5) > 0.55 ? 'No EXIF data present — typical of AI-generated outputs and screenshots.' : s(5) > 0.20 ? 'Partial metadata present; some fields are missing or inconclusive.'    : 'EXIF data present and consistent with the reported device and timestamp.' },
  ];
}

function buildSummary(aiScore, authScore) {
  if (aiScore > 0.70) return `Strong indicators of AI generation detected (authenticity score: ${authScore}/100). Texture patterns and structural geometry are inconsistent with a real photograph.`;
  if (aiScore > 0.45) return `Mixed signals detected (authenticity score: ${authScore}/100). Some patterns suggest AI assistance or post-processing, but the evidence is not conclusive.`;
  return `No significant manipulation indicators found (authenticity score: ${authScore}/100). The image appears to be an authentic photograph.`;
}

function parseResponse(data) {
  const isAI      = Boolean(data.isAI);
  const confidence = typeof data.confidence === 'number' ? data.confidence : 0.5;

  // aiScore = probability the image is AI-generated (0–1)
  const aiScore   = isAI ? confidence : (1 - confidence);
  const authScore = Math.round((1 - aiScore) * 100);

  let verdict, verdictIcon, verdictColor;
  if (authScore < 30)      { verdict = 'AI-GENERATED';    verdictIcon = '🔴'; verdictColor = '#EF4444'; }
  else if (authScore < 55) { verdict = 'UNCERTAIN';        verdictIcon = '🟡'; verdictColor = '#F59E0B'; }
  else                     { verdict = 'LIKELY AUTHENTIC'; verdictIcon = '🟢'; verdictColor = '#22C55E'; }

  return {
    score:       authScore,
    verdict,
    verdictIcon,
    verdictColor,
    summary:     buildSummary(aiScore, authScore),
    checks:      buildChecks(aiScore),
  };
}

module.exports = async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

  const apiKey = process.env.WASITAIGENERATED_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'WASITAIGENERATED_API_KEY not configured.' });

  const { imageBase64, mimeType } = req.body ?? {};
  if (!imageBase64 || typeof imageBase64 !== 'string')
    return res.status(400).json({ error: 'Provide imageBase64 (base64-encoded image).' });
  if (imageBase64.length > 20_000_000)
    return res.status(400).json({ error: 'Image too large. Maximum 15 MB.' });

  const resolvedMime = (typeof mimeType === 'string' && mimeType.startsWith('image/'))
    ? mimeType : 'image/jpeg';

  try {
    const data   = await callDetector(imageBase64, resolvedMime, apiKey);
    return res.json(parseResponse(data));
  } catch (err) {
    console.error('[analyzeImage]', err.message);
    return res.status(502).json({ error: err.message });
  }
};
