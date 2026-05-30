'use strict';

const GNEWS_URL = 'https://gnews.io/api/v4/top-headlines';

const CATEGORY_MAP = {
  general:       'breaking-news',
  technology:    'technology',
  sports:        'sports',
  health:        'health',
  science:       'science',
  business:      'business',
  entertainment: 'entertainment',
};

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

module.exports = async (req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  const apiKey = process.env.GNEWS_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'GNEWS_API_KEY not configured.' });

  const category = req.query.category ?? 'general';
  const pageSize = Math.min(parseInt(req.query.pageSize ?? '10', 10), 20);
  const gnewsCategory = CATEGORY_MAP[category] ?? 'breaking-news';

  const url = new URL(GNEWS_URL);
  url.searchParams.set('category', gnewsCategory);
  url.searchParams.set('lang', 'en');
  url.searchParams.set('max', String(pageSize));
  url.searchParams.set('apikey', apiKey);

  try {
    const response = await fetch(url.toString());
    if (!response.ok) {
      const text = await response.text();
      return res.status(502).json({ error: `GNews API error: ${response.status}`, details: text });
    }
    const data = await response.json();

    const articles = (data.articles ?? []).map((a, i) => ({
      id: a.url ?? `${category}_${i}`,
      title: a.title ?? 'No title',
      description: a.description ?? '',
      content: a.content ?? a.description ?? '',
      imageUrl: a.image ?? '',
      source: a.source?.name ?? 'Unknown',
      publishedAt: a.publishedAt ?? new Date().toISOString(),
      url: a.url ?? '',
      category,
      ageRating: 13,
    }));

    // Cache for 24 hours on Vercel's CDN edge network
    res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=3600');
    return res.json({ articles, fetchedAt: new Date().toISOString() });
  } catch (err) {
    console.error('[news]', err.message);
    return res.status(502).json({ error: err.message });
  }
};
