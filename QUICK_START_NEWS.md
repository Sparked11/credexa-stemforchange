# 🚀 Quick Start - News Feed

## ⚡ 3-Step Setup (2 minutes)

### 1️⃣ Get API Key
- Visit: https://newsapi.org
- Sign up (free)
- Copy your API key

### 2️⃣ Add API Key
File: `/lib/services/news_service.dart` (line 6)
```dart
static const String _apiKey = 'your_api_key_here';  // ← Paste here
```

### 3️⃣ Run!
```bash
flutter pub get
flutter run
```

Tap the **📰 News** tab in the app!

---

## 📊 What It Does

| Feature | Status |
|---------|--------|
| Fetch latest news | ✅ Working |
| Filter by category | ✅ Working |
| Teen-safe sources only | ✅ Curated |
| Beautiful UI | ✅ Animated |
| Error handling | ✅ Graceful |
| Image loading | ✅ With fallback |

---

## 🎯 News Sources

- BBC News ✓
- CNN ✓
- Reuters ✓
- AP News ✓
- The Guardian ✓
- Washington Post ✓
- NY Times ✓
- ESPN ✓
- TechCrunch ✓
- National Geographic ✓

---

## 🔗 Categories

Users can filter by:
- General
- Business
- Sports
- Technology
- Health
- Science
- Entertainment

---

## 💡 Pro Tips

✅ Free tier gives 100 requests/day
✅ Each article load = 1 request
✅ Cache articles to save requests
✅ Add search functionality later

---

## ❓ FAQ

**Q: Is my API key secure?**
A: For production, use environment variables or Firebase instead of hardcoding.

**Q: What if I hit the rate limit?**
A: Wait until tomorrow or upgrade to paid plan.

**Q: Can I add more news sources?**
A: Yes! Edit `_teenSafeSources` in `news_service.dart`

**Q: Is the content really teen-safe?**
A: Yes, we only use reputable, fact-checked sources.

---

For full documentation, see: `NEWS_FEED_SETUP.md`
