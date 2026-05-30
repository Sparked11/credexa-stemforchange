# 📰 News Feed Setup Guide - Credexa App

## ✅ What's Implemented

Your news feed feature is now ready! Here's what you have:

### **Features:**
- ✅ Real-time news articles from trusted sources
- ✅ Category filtering (General, Business, Sports, Technology, Health, Science, Entertainment)
- ✅ Teen-safe content curation (only reputable sources)
- ✅ Beautiful article cards with images
- ✅ Article preview modal with full details
- ✅ Relative time formatting (e.g., "2 hours ago")
- ✅ Loading and error states
- ✅ Responsive design with Montserrat typography

---

## 🔑 Step 1: Get Your NewsAPI Key

**CRITICAL:** Without this, the news feed won't work!

1. Go to **https://newsapi.org**
2. Click **"Get API Key"** (free tier)
3. Sign up with your email
4. Copy your API key (looks like: `abc123xyz456...`)
5. Open `/lib/services/news_service.dart`
6. Replace `'YOUR_NEWSAPI_KEY_HERE'` on line 6 with your actual API key:

```dart
static const String _apiKey = 'your_actual_api_key_here';
```

**Example:**
```dart
static const String _apiKey = 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6';
```

---

## 🏗️ Project Structure

```
lib/
├── main.dart                    # Main app + NewsPage widget
├── models/
│   └── news_article.dart        # NewsArticle data model
└── services/
    └── news_service.dart        # API integration service
```

---

## 📡 Safe News Sources (Curated)

Your app only shows articles from these trusted sources:
- **News:** BBC, CNN, Reuters, Associated Press, The Guardian, Washington Post, New York Times
- **Tech:** TechCrunch
- **Sports:** ESPN
- **Nature:** National Geographic

This ensures **zero misinformation** for your teen audience!

---

## 🛠️ Customization Options

### **Add More Sources**

Edit `/lib/services/news_service.dart`:

```dart
static const List<String> _teenSafeSources = [
    'bbc-news',
    'your-new-source-here',  // Add here
    'cnn',
    // ...
];
```

Find all available sources at: https://newsapi.org/sources

### **Change API Rate Limits**

Free tier: **100 requests/day**
Paid tier: Up to **500+ requests/day**

To upgrade, visit your NewsAPI dashboard.

### **Customize Categories**

Edit in `_NewsPageState`:

```dart
final List<String> _categories = [
    'general', 'business', 'sports', 
    'technology', 'health', 'science', 
    'entertainment'
    // Add or remove categories here
];
```

---

## 🚀 Running the App

```bash
cd /Users/santanudey/Downloads/credexa_stemforchange
flutter pub get
flutter run
```

Then tap the **"News"** tab (📰 icon) in the bottom navigation!

---

## 🔍 API Methods Available

### In `news_service.dart`:

1. **`fetchTeenNews()`** - Get top headlines from safe sources
2. **`fetchNewsByCategory(String category)`** - Filter by topic
3. **`searchNews(String query)`** - Search for specific keywords

### Example Usage:
```dart
// Fetch sports news
List<NewsArticle> sports = await NewsService.fetchNewsByCategory('sports');

// Search for climate news
List<NewsArticle> climate = await NewsService.searchNews('climate change');
```

---

## ⚠️ Important Notes

### **API Key Security**
- Your API key in `news_service.dart` is **currently hardcoded**
- For production, use **environment variables** or **Firebase Remote Config**
- Never commit your real API key to GitHub!

### **Rate Limiting**
- Free tier: 100 requests/day
- Each article load counts as 1 request
- If you hit the limit, articles won't load until next day
- Consider adding caching in production

### **Error Handling**
The app gracefully handles:
- ❌ No internet connection
- ❌ Invalid API key
- ❌ Rate limit exceeded
- ❌ No articles found

---

## 🎨 UI Customization

### Colors (in main.dart):
- Primary: `#1E293B` (Slate Blue)
- Accent: `#22C55E` (Calm Green)
- Background: `#F1F5F9` (Light Gray)

### Typography:
- Font: Montserrat (weights: 400 Regular, 700 Bold)
- Sizes: 20px (titles), 14px (body), 12px (meta)

---

## 📱 Next Steps (Optional Enhancements)

1. **Add Search**: Search bar to find specific topics
2. **Save Articles**: Let users bookmark favorites
3. **Share Feature**: Share articles to social media
4. **Fact-Check Integration**: Link to credibility scores
5. **Notification**: Alert users about trending topics
6. **Dark Mode**: Support dark theme

---

## 🐛 Troubleshooting

### "No articles found"
- Check your API key is correct
- Verify internet connection
- Check that NewsAPI service is up: https://status.newsapi.org

### "Invalid API key"
- Make sure you replaced `'YOUR_NEWSAPI_KEY_HERE'`
- Verify the key was copied completely

### "Rate limit exceeded"
- You've made 100+ requests today
- Wait until next day or upgrade to paid plan

### Articles not loading images
- Some sources don't provide image URLs
- The app shows a placeholder icon instead

---

## 📚 Documentation

- **NewsAPI Docs:** https://newsapi.org/docs
- **Available Sources:** https://newsapi.org/sources
- **Flutter http package:** https://pub.dev/packages/http

---

**Built with ❤️ for Credexa | Teen-Safe News for Digital Literacy**
