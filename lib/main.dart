import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ignore: unnecessary_import
import 'package:intl/intl.dart';
import 'models/news_article.dart';
import 'services/news_service.dart';
import 'services/share_service.dart';
import 'services/shared_content_router.dart';
import 'home_page.dart';
import 'debias_page.dart';
import 'community_hub_page.dart';
import 'visual_analyzer_page.dart';
import 'trust_lens_page.dart';
import 'auth_service.dart';
import 'auth_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'profile_page.dart';
import 'services/profile_service.dart';
import 'services/user_progress_service.dart';
import 'services/quest_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  AuthService.init(); // sync Firebase auth state to local ValueNotifier
  await ProfileService.load();
  await UserProgressService.load();
  // Register global profile navigation — used by every ProfileIcon automatically.
  ProfileService.openProfile = (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute(builder: (_) => const ProfilePage()),
      );
  runApp(const MyApp());
}

// App navigation screens
enum NavigationTab { home, explain, debiaseed, newsFeed, more }

extension NavigationTabExtension on NavigationTab {
  String get label {
    switch (this) {
      case NavigationTab.home:      return 'Home';
      case NavigationTab.explain:   return 'Explain';
      case NavigationTab.debiaseed: return 'De-Bias';
      case NavigationTab.newsFeed:  return 'News';
      case NavigationTab.more:      return 'More';
    }
  }

  IconData get icon {
    switch (this) {
      case NavigationTab.home:      return Icons.home_rounded;
      case NavigationTab.explain:   return Icons.fact_check_rounded;
      case NavigationTab.debiaseed: return Icons.tune_rounded;
      case NavigationTab.newsFeed:  return Icons.newspaper_rounded;
      case NavigationTab.more:      return Icons.more_horiz_rounded;
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  NavigationTab _selectedTab = NavigationTab.home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Credexa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E293B),
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
          displayMedium: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 16,
            color: Color(0xFF64748B),
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 14,
            color: Color(0xFF64748B),
          ),
        ),
      ),
      home: ValueListenableBuilder<AuthUser?>(
        valueListenable: AuthService.authState,
        builder: (ctx, user, _) {
          if (user == null) return const AuthPage();
          return MainApp(
            selectedTab: _selectedTab,
            onTabChanged: (tab) => setState(() => _selectedTab = tab),
          );
        },
      ),
    );
  }
}

class MainApp extends StatefulWidget {
  final NavigationTab selectedTab;
  final Function(NavigationTab) onTabChanged;

  const MainApp({
    super.key,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pageTransitionController;
  late AnimationController _overlayController;
  late AnimationController _questSlideCtrl;
  String? _moreSubPage;
  bool   _showOverlay   = false;
  bool   _showDailyQuest = false;
  Map<String, dynamic>? _dailyQuestData;
  _TransitionInfo _transitionInfo = const _TransitionInfo(
    label: 'Home', icon: Icons.home_rounded, color: Color(0xFF22C55E));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageTransitionController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    )..forward();
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    _questSlideCtrl = AnimationController(
      duration: const Duration(milliseconds: 480),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSharedContent();
      // Delay so the app finishes its entrance animation first.
      Future.delayed(const Duration(seconds: 2), _tryLoadDailyQuest);
    });
  }

  Future<void> _tryLoadDailyQuest() async {
    if (!mounted) return;
    final shouldShow = await UserProgressService.shouldShowDailyQuest();
    if (!shouldShow || !mounted) return;

    // Use cached quest for today if already generated.
    var quest = await UserProgressService.getCachedQuest();
    if (quest == null) {
      try {
        quest = await QuestService.generateQuest();
        await UserProgressService.cacheQuest(quest);
      } catch (_) {
        return; // Silently skip if generation fails.
      }
    }
    if (!mounted) return;
    setState(() { _dailyQuestData = quest; _showDailyQuest = true; });
    _questSlideCtrl.forward();
  }

  Future<void> _dismissDailyQuest() async {
    await _questSlideCtrl.reverse();
    if (mounted) setState(() => _showDailyQuest = false);
    await UserProgressService.markQuestSeen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkSharedContent();
  }

  @override
  void didUpdateWidget(MainApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _moreSubPage = null;
      _triggerTransition(
        widget.selectedTab.label,
        widget.selectedTab.icon,
        _tabColor(widget.selectedTab),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageTransitionController.dispose();
    _overlayController.dispose();
    _questSlideCtrl.dispose();
    super.dispose();
  }

  // ── Transition helpers ───────────────────────────────────────────────────────

  Color _tabColor(NavigationTab tab) {
    switch (tab) {
      case NavigationTab.home:      return const Color(0xFF22C55E);
      case NavigationTab.explain:   return const Color(0xFF6366F1);
      case NavigationTab.debiaseed: return const Color(0xFF22C55E);
      case NavigationTab.newsFeed:  return const Color(0xFF0EA5E9);
      case NavigationTab.more:      return const Color(0xFF1E293B);
    }
  }

  (String, IconData, Color) _moreItemMeta(String item) {
    switch (item) {
      case 'visual_scanner':
        return ('Visual Scanner', Icons.image_search_rounded, const Color(0xFF8B5CF6));
      case 'learn':
        return ('Community Hub', Icons.forum_rounded, const Color(0xFF6366F1));
      default:
        return ('More', Icons.more_horiz_rounded, const Color(0xFF1E293B));
    }
  }

  Future<void> _triggerTransition(String label, IconData icon, Color color) async {
    if (!mounted) return;
    setState(() {
      _showOverlay   = true;
      _transitionInfo = _TransitionInfo(label: label, icon: icon, color: color);
    });
    _overlayController.reset();
    _pageTransitionController.reset();

    // Haptic rhythm: tap·beat·beat·land
    Future.delayed(const Duration(milliseconds: 80),  () { if (mounted) HapticFeedback.lightImpact(); });
    Future.delayed(const Duration(milliseconds: 210), () { if (mounted) HapticFeedback.mediumImpact(); });
    Future.delayed(const Duration(milliseconds: 270), () { if (mounted) HapticFeedback.mediumImpact(); });
    Future.delayed(const Duration(milliseconds: 430), () { if (mounted) HapticFeedback.lightImpact(); });

    // Overlay plays; page entrance starts at the tail of the overlay
    _overlayController.forward();
    await Future.delayed(const Duration(milliseconds: 340));
    if (mounted) _pageTransitionController.forward();
    await _overlayController.forward();
    if (mounted) setState(() => _showOverlay = false);
  }

  // ── Content ──────────────────────────────────────────────────────────────────

  Future<void> _checkSharedContent() async {
    final content = await ShareService.getSharedContent();
    if (content == null || !mounted) return;
    await ShareService.clearSharedContent();
    _showRoutingDialog(content);
  }

  void _showRoutingDialog(Map<String, dynamic> content) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ShareRoutingSheet(
        content: content,
        onFactcheck: () {
          Navigator.pop(context);
          SharedContentRouter.forFactcheck.value = content;
          widget.onTabChanged(NavigationTab.explain);
        },
        onDebias: () {
          Navigator.pop(context);
          SharedContentRouter.forDebias.value = content;
          widget.onTabChanged(NavigationTab.debiaseed);
        },
      ),
    );
  }

  void _selectMoreItem(String item) {
    if (item == 'trust_lens') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const TrustLensPage(),
        fullscreenDialog: true,
      ));
      return;
    }
    final (label, icon, color) = _moreItemMeta(item);
    setState(() => _moreSubPage = item);
    _triggerTransition(label, icon, color);
  }

  Widget _buildPage() {
    if (_moreSubPage == 'visual_scanner') {
      return const VisualAnalyzerPage(key: ValueKey('visual_scanner'));
    }
    if (_moreSubPage == 'learn') {
      return const CommunityHubPage(key: ValueKey('learn'));
    }
    switch (widget.selectedTab) {
      case NavigationTab.home:
        return HomeDashboardPage(
          key: ValueKey(widget.selectedTab),
          onNavigate: widget.onTabChanged,
          onNavigateMore: _selectMoreItem,
        );
      case NavigationTab.explain:
        return HomePage(key: ValueKey(widget.selectedTab));
      case NavigationTab.debiaseed:
        return const DebiasPage(key: ValueKey(NavigationTab.debiaseed));
      case NavigationTab.newsFeed:
        return const NewsPage();
      case NavigationTab.more:
        return HomeDashboardPage(
          key: ValueKey(widget.selectedTab),
          onNavigate: widget.onTabChanged,
          onNavigateMore: _selectMoreItem,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            FadeTransition(
              opacity: _pageTransitionController,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                  CurvedAnimation(
                      parent: _pageTransitionController,
                      curve: Curves.easeOutCubic),
                ),
                child: _buildPage(),
              ),
            ),
            if (_showOverlay)
              _PageTransitionOverlay(
                controller: _overlayController,
                info: _transitionInfo,
              ),
            if (_showDailyQuest && _dailyQuestData != null)
              _DailyQuestBanner(
                questData: _dailyQuestData!,
                slideCtrl: _questSlideCtrl,
                onDismiss: _dismissDailyQuest,
                onAnswered: (bool correct) async {
                  await UserProgressService.recordQuestResult(correct: correct);
                  await _dismissDailyQuest();
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNavBar(
        selectedTab: widget.selectedTab,
        onTabChanged: (tab) {
          // Always clear any active More sub-page so tapping Home while on
          // a More sub-page actually navigates back, even when selectedTab
          // hasn't changed (e.g. Home was already the last real tab).
          if (_moreSubPage != null) setState(() => _moreSubPage = null);
          widget.onTabChanged(tab);
        },
        onMoreItemSelected: _selectMoreItem,
        moreIsActive: _moreSubPage != null,
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  HOME DASHBOARD
// ─────────────────────────────────────────────────────────────────────────────
class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({
    super.key,
    required this.onNavigate,
    this.onNavigateMore,
  });
  final Function(NavigationTab) onNavigate;
  final Function(String)? onNavigateMore;

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeDashboardPageState extends State<HomeDashboardPage>
    with TickerProviderStateMixin {
  static const _bg       = Color(0xFFF1F5F9);
  static const _primary  = Color(0xFF1E293B);
  static const _secondary = Color(0xFF64748B);
  static const _accent   = Color(0xFF22C55E);

  // Staggered entrance animation — runs once on first build.
  late final AnimationController _entranceCtrl;
  // Continuous pulse ring behind the logo.
  late final AnimationController _pulseCtrl;
  // Features carousel controller + current page index.
  late final PageController _featuresPageCtrl;
  int _featuresPage = 0;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..forward();
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();
    _featuresPageCtrl = PageController();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _featuresPageCtrl.dispose();
    super.dispose();
  }

  // Wraps a child in a staggered slide-up + fade entrance.
  Widget _staggered(Widget child, double begin, double end) {
    final curved = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 64)),
            SliverToBoxAdapter(child: _staggered(_buildHero(), 0.0, 0.4)),
            SliverToBoxAdapter(child: _staggered(_buildMaturityTracker(), 0.15, 0.5)),
            SliverToBoxAdapter(child: _staggered(_buildStreak(), 0.2, 0.6)),
            SliverToBoxAdapter(
                child: _staggered(_buildFeatures(context), 0.4, 0.8)),
            SliverToBoxAdapter(child: _staggered(_buildMission(), 0.4, 0.8)),
            SliverToBoxAdapter(child: _staggered(_buildStat(), 0.6, 1.0)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
        Positioned(top: 0, left: 0, right: 0, child: _buildNavbar()),
      ],
    );
  }

  // ── User Maturity Tracker ────────────────────────────────────────────────────
  Widget _buildMaturityTracker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ValueListenableBuilder<UserProgressStats>(
        valueListenable: UserProgressService.stats,
        builder: (_, s, __) {
          final lvl      = s.level;
          final progress = lvl.progress(s.maturityPoints);
          final nextIdx  = kMaturityLevels.indexOf(lvl) + 1;
          final nextLvl  = nextIdx < kMaturityLevels.length
              ? kMaturityLevels[nextIdx]
              : null;
          final pct = s.predictionsTotal == 0
              ? '--'
              : '${(s.predictionAccuracy * 100).round()}%';

          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  children: [
                    Text(lvl.emoji,
                        style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MEDIA MATURITY',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFBBF7D0),
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            lvl.title,
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${s.maturityPoints} pts',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Progress bar ──
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF4ADE80)),
                  ),
                ),
                const SizedBox(height: 6),
                if (nextLvl != null)
                  Text(
                    '${lvl.pointsToNext(s.maturityPoints)} pts to ${nextLvl.title}',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFBBF7D0),
                    ),
                  ),
                const SizedBox(height: 16),

                // ── Stats row ──
                Row(
                  children: [
                    _matStat('🎯', 'Accuracy', pct),
                    _matDivider(),
                    _matStat('📚', 'Quests', '${s.questsAnswered}'),
                    _matDivider(),
                    _matStat('🔍', 'Predictions', '${s.predictionsTotal}'),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Core identity statement ──
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What Credexa is, in one sentence:',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFBBF7D0),
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '"An AI-powered platform that teaches you to evaluate information critically — not just gives you answers."',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.predictionsTotal >= 3
                            ? '📈  Your prediction accuracy is $pct — proof that critical thinking can be learned.'
                            : '📈  Answer daily quests and check claims to build evidence of your growth.',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _matStat(String emoji, String label, String value) => Expanded(
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );

  Widget _matDivider() => Container(
        width: 1,
        height: 40,
        color: Colors.white.withValues(alpha: 0.2),
      );

  // ── Streak counter ───────────────────────────────────────────────────────────
  Widget _buildStreak() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ValueListenableBuilder<ProfileData>(
        valueListenable: ProfileService.data,
        builder: (_, data, __) {
          final streak = data.checks + data.debiases + data.posts;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: streak),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, __) => Text(
                        '$value',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFEA580C),
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Action Streak',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'Keep it up!',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNavbar() {
    return Container(
      height: 64,
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(
            height: 62,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _PulseRing(controller: _pulseCtrl),
                Image.asset('assets/logomain.png',
                    height: 62, fit: BoxFit.contain),
              ],
            ),
          ),
          const Spacer(),
          const ProfileIcon(),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'CREDEXA · MEDIA LITERACY PLATFORM',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFF22C55E),
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Fight Misinformation.\nThink Critically.',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _primary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Your AI-powered companion for understanding, identifying, and combating misinformation — aligned with UN SDG 16.',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _secondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    // Page 0: core features  |  Page 1: newer features
    const pages = [
      [
        (
          icon: Icons.fact_check_rounded,
          color: Color(0xFF6366F1),
          title: 'Explain Why',
          desc: 'Fact-check any claim with a 3-model AI council.',
        ),
        (
          icon: Icons.tune_rounded,
          color: Color(0xFF22C55E),
          title: 'De-Bias',
          desc: 'Reframe content to remove hidden bias.',
        ),
        (
          icon: Icons.newspaper_rounded,
          color: Color(0xFF0EA5E9),
          title: 'News Feed',
          desc: 'Stay informed with age-appropriate news.',
        ),
        (
          icon: Icons.forum_rounded,
          color: Color(0xFF6366F1),
          title: 'Community Hub',
          desc: 'Ask "Is this real?" — get answers anonymously.',
        ),
      ],
      [
        (
          icon: Icons.image_search_rounded,
          color: Color(0xFF8B5CF6),
          title: 'Visual Scanner',
          desc: 'Detect AI-generated images and deepfakes instantly.',
        ),
        (
          icon: Icons.videocam_rounded,
          color: Color(0xFF00BFFF),
          title: 'Trust Lens',
          desc: 'Live AR camera scanner — bias overlay on any screen.',
        ),
      ],
    ];

    void tapFeature(int page, int index) {
      HapticFeedback.lightImpact();
      if (page == 0) {
        switch (index) {
          case 0: widget.onNavigate(NavigationTab.explain);
          case 1: widget.onNavigate(NavigationTab.debiaseed);
          case 2: widget.onNavigate(NavigationTab.newsFeed);
          case 3: widget.onNavigateMore?.call('learn');
        }
      } else {
        switch (index) {
          case 0: widget.onNavigateMore?.call('visual_scanner');
          case 1: widget.onNavigateMore?.call('trust_lens');
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Explore Features',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _primary,
                ),
              ),
              const Spacer(),
              // Page indicator dots
              Row(
                children: List.generate(pages.length, (i) {
                  final active = _featuresPage == i;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    width: active ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? _accent : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // Match the 2-column grid geometry to compute a stable height.
              final cellW = (w - 12) / 2;
              final cellH = cellW / 1.05;
              final gridH = 2 * cellH + 12;
              return SizedBox(
                height: gridH,
                child: PageView.builder(
                  controller: _featuresPageCtrl,
                  onPageChanged: (i) => setState(() => _featuresPage = i),
                  itemCount: pages.length,
                  itemBuilder: (context, pageIndex) {
                    final items = pages[pageIndex];
                    return GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.05,
                      children: List.generate(items.length, (i) {
                        final f = items[i];
                        return GestureDetector(
                          onTap: () => tapFeature(pageIndex, i),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: f.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(f.icon, color: f.color, size: 22),
                                ),
                                const Spacer(),
                                Text(
                                  f.title,
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: _primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  f.desc,
                                  style: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _secondary,
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMission() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _ProblemDefinitionPage(),
          ));
        },
        child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF334155)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'UN SDG Goal 16',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Peace, Justice & Strong Institutions',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Credexa promotes access to information and protects fundamental freedoms for all.',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Text('🕊️', style: TextStyle(fontSize: 40)),
          ],
        ),
      ),        // Container
      ),        // GestureDetector
    );
  }

  Widget _buildStat() => const _StatRouletteCard();
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROBLEM DEFINITION PAGE
// ─────────────────────────────────────────────────────────────────────────────

class _ProblemDefinitionPage extends StatelessWidget {
  const _ProblemDefinitionPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF1E293B),
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text('UN SDG GOAL 16',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF22C55E),
                                letterSpacing: 1.1,
                              )),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Problem Definition',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'The misinformation crisis — who it affects and why it matters.',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF94A3B8),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── The Problem ───────────────────────────────────────────
                  _probSection(
                    emoji: '🌐',
                    title: 'The Community Problem',
                    body:
                        'Misinformation spreads faster than ever — and most people '
                        'encounter it daily without realizing it. False headlines, '
                        'manipulated images, and emotionally loaded language flood '
                        'social media feeds, influencing beliefs, votes, and health '
                        'decisions.',
                  ),
                  const SizedBox(height: 16),

                  // ── Stats ─────────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('By the numbers',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF22C55E),
                            )),
                        const SizedBox(height: 14),
                        ...[
                          ('68%', 'of teens have shared misinformation without realizing it'),
                          ('6×', 'faster — how quickly false news spreads vs. factual news'),
                          ('26%', 'of Americans can correctly identify fake news'),
                          ('50%+', 'of teens get news from social media — zero editorial filter'),
                        ].map((s) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text(s.$1,
                                        style: const TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        )),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(s.$2,
                                        style: const TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF94A3B8),
                                          height: 1.5,
                                        )),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Who is affected ───────────────────────────────────────
                  _probSection(
                    emoji: '👥',
                    title: 'Who Is Affected',
                    body:
                        'Teenagers and young adults are the most vulnerable — they '
                        'consume the most social media and have the least experience '
                        'evaluating sources. But misinformation affects everyone: it '
                        'undermines elections, erodes trust in science, and fuels '
                        'division in communities.',
                  ),
                  const SizedBox(height: 16),

                  // ── Why it matters ────────────────────────────────────────
                  _probSection(
                    emoji: '⚖️',
                    title: 'Why It Matters',
                    body:
                        'UN SDG Goal 16 calls for peaceful, just, and inclusive '
                        'societies with access to accurate information. A democracy '
                        'cannot function when citizens cannot distinguish fact from '
                        'fiction. Critical thinking is not a skill people are born '
                        'with — it has to be taught.',
                  ),
                  const SizedBox(height: 16),

                  // ── Credexa's answer ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Credexa\'s Answer',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFBBF7D0),
                            )),
                        SizedBox(height: 8),
                        Text(
                          '"An AI-powered platform that teaches users how to evaluate '
                          'information critically for themselves — not just flags '
                          'misinformation, but builds the skill to detect it."',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _probSection({
    required String emoji,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                )),
          ]),
          const SizedBox(height: 10),
          Text(body,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
                height: 1.6,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DAILY QUEST BANNER — slides down from top once per day
// ─────────────────────────────────────────────────────────────────────────────

class _DailyQuestBanner extends StatefulWidget {
  const _DailyQuestBanner({
    required this.questData,
    required this.slideCtrl,
    required this.onDismiss,
    required this.onAnswered,
  });
  final Map<String, dynamic> questData;
  final AnimationController slideCtrl;
  final VoidCallback onDismiss;
  final void Function(bool correct) onAnswered;

  @override
  State<_DailyQuestBanner> createState() => _DailyQuestBannerState();
}

class _DailyQuestBannerState extends State<_DailyQuestBanner> {
  int?  _selected;
  bool  _revealed = false;

  int get _correctIndex =>
      (widget.questData['correct_index'] as num?)?.toInt() ?? 0;
  List<String> get _options =>
      (widget.questData['options'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      [];

  void _pick(int i) {
    if (_revealed) return;
    HapticFeedback.mediumImpact();
    setState(() { _selected = i; _revealed = true; });
  }

  @override
  Widget build(BuildContext context) {
    final slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: widget.slideCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    ));

    return SlideTransition(
      position: slideAnim,
      child: Stack(
        children: [
          // Scrim
          GestureDetector(
            onTap: _revealed ? null : widget.onDismiss,
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          // Card
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LayoutBuilder(
                builder: (context, constraints) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('📚', style: TextStyle(fontSize: 12)),
                                SizedBox(width: 5),
                                Text(
                                  'DAILY QUEST',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: widget.onDismiss,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 18, color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Post text ────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'What manipulation technique is this post using?',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '"${widget.questData['post_text'] ?? ''}"',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Options ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Column(
                        children: List.generate(_options.length, (i) {
                          Color bg = Colors.white;
                          Color border = const Color(0xFFE2E8F0);
                          Color textColor = const Color(0xFF1E293B);
                          Widget? trailing;

                          if (_revealed) {
                            if (i == _correctIndex) {
                              bg = const Color(0xFFEFFFF5);
                              border = const Color(0xFF22C55E);
                              textColor = const Color(0xFF15803D);
                              trailing = const Icon(Icons.check_circle_rounded,
                                  color: Color(0xFF22C55E), size: 18);
                            } else if (i == _selected) {
                              bg = const Color(0xFFFFEDE8);
                              border = const Color(0xFFEF4444);
                              textColor = const Color(0xFFB91C1C);
                              trailing = const Icon(Icons.cancel_rounded,
                                  color: Color(0xFFEF4444), size: 18);
                            }
                          } else if (_selected == i) {
                            bg = const Color(0xFFEFF6FF);
                            border = const Color(0xFF6366F1);
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () => _pick(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: border, width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _options[i],
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    if (trailing != null) ...[
                                      const SizedBox(width: 8),
                                      trailing,
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    // ── Explanation + Got it (after answer) ──────────────────
                    if (_revealed) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selected == _correctIndex
                                ? const Color(0xFFEFFFF5)
                                : const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selected == _correctIndex ? '🎉' : '💡',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.questData['explanation']?.toString() ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _selected == _correctIndex
                                        ? const Color(0xFF15803D)
                                        : const Color(0xFF92400E),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                        child: GestureDetector(
                          onTap: () => widget
                              .onAnswered(_selected == _correctIndex),
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              color: _selected == _correctIndex
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              _selected == _correctIndex
                                  ? '🎉  Nice work! +15 pts'
                                  : '💪  Got it! Keep learning +5 pts',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),       // Column
                ),       // SingleChildScrollView
              ),         // Container
                ),       // ConstrainedBox
              ),         // LayoutBuilder
            ),           // Padding
          ),             // SafeArea
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PULSE RING — expanding concentric rings behind the home logo
// ─────────────────────────────────────────────────────────────────────────────
class _PulseRing extends AnimatedWidget {
  const _PulseRing({required this.controller})
      : super(listenable: controller);
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(96, 96),
      painter: _PulseRingPainter(controller.value),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF22C55E).withOpacity(0.12);

    // Inner ring: radius 20 → 36
    canvas.drawCircle(center, 20 + 16 * t, paint);
    // Outer ring: radius 28 → 48 (offset phase for a layered ripple)
    canvas.drawCircle(center, 28 + 20 * t, paint);
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
//  STAT ROULETTE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _StatRouletteCard extends StatefulWidget {
  const _StatRouletteCard();

  @override
  State<_StatRouletteCard> createState() => _StatRouletteCardState();
}

class _StatRouletteCardState extends State<_StatRouletteCard> {
  static const _stats = [
    '68% of teens have shared misinformation online without realizing it. Credexa gives you the tools to check before you share.',
    'Only 26% of Americans can correctly identify fake news. Fact-checking takes under 60 seconds.',
    'Misinformation spreads 6× faster than factual news on social media. One share can reach thousands.',
    'Over 50% of teens get their news from social media — where there is no editorial filter.',
    'A false headline generates 70% more engagement than accurate news. Your skepticism is your superpower.',
    'It takes 10× more mental effort to correct a false belief than to form it. Checking first saves everyone effort.',
  ];

  int _index = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _stats.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:        const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Did You Know?',
                    style: TextStyle(
                      fontFamily:  'Montserrat',
                      fontSize:    13,
                      fontWeight:  FontWeight.w800,
                      color:       Color(0xFF1E40AF),
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _stats[_index],
                      key:   ValueKey(_index),
                      style: const TextStyle(
                        fontFamily:  'Montserrat',
                        fontSize:    12,
                        fontWeight:  FontWeight.w500,
                        color:       Color(0xFF1E40AF),
                        height:      1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOGO TICKER
// ─────────────────────────────────────────────────────────────────────────────

class PlaceholderPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;

  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 100,
          floating: false,
          pinned: true,
          backgroundColor: const Color(0xFF1E293B),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1E293B),
                    Color(0xFF334155),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 32,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 80,
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 16,
                      color: Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                    ),
                    child: const Text(
                      'Coming Soon',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  late Future<List<NewsArticle>> _newsArticles;
  String _selectedCategory = 'general';
  final List<String> _categories = ['general', 'business', 'sports', 'technology', 'health', 'science', 'entertainment'];
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _newsArticles = NewsService.fetchNewsByCategory(_selectedCategory);
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final scrolled = _scroll.offset > 10;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _changeCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _newsArticles = NewsService.fetchNewsByCategory(category);
    });
  }

  Widget _buildNavbar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      height: 64,
      decoration: BoxDecoration(
        color: _scrolled ? Colors.white : const Color(0xFFF1F5F9),
        border: _scrolled
            ? const Border(bottom: BorderSide(color: Color(0x12000000), width: 1))
            : null,
        boxShadow: _scrolled
            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Image.asset('assets/logomain.png', height: 62, fit: BoxFit.contain),
            const Spacer(),
            const ProfileIcon(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 64)),
        // Category Filter
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _changeCategory(category),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFE2E8F0),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // News List
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: FutureBuilder<List<NewsArticle>>(
            future: _newsArticles,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF22C55E).withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
                );
              } else if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Oops! Unable to load news',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _changeCategory(_selectedCategory),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final articles = snapshot.data ?? [];
              if (articles.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No articles found',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 14,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final article = articles[index];
                    return _NewsArticleCard(article: article);
                  },
                  childCount: articles.length,
                ),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 30),
        ),
      ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildNavbar(),
        ),
      ],
    );
  }
}

class _NewsArticleCard extends StatelessWidget {
  final NewsArticle article;

  const _NewsArticleCard({required this.article});

  // Category → accent color map for the pill and left border.
  static const _categoryColors = <String, Color>{
    'general': Color(0xFF6366F1),
    'politics': Color(0xFFEF4444),
    'science': Color(0xFF22C55E),
    'technology': Color(0xFF0EA5E9),
    'health': Color(0xFFF59E0B),
    'entertainment': Color(0xFF8B5CF6),
  };

  Color get _categoryColor =>
      _categoryColors[article.category.toLowerCase()] ??
      const Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final catColor = _categoryColor;
    final hasReadMore =
        article.content.trim().length > article.description.trim().length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Show article details or open link
            _showArticlePreview(context, article);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 140),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Colored left accent bar — replaces non-uniform border
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: catColor,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(11),
                        bottomLeft: Radius.circular(11),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                // Image
                if (article.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                    ),
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      color: const Color(0xFFF1F5F9),
                      child: Image.network(
                        article.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(
                              Icons.image_not_supported_rounded,
                              color: Color(0xFFCBD5E1),
                              size: 40,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Source · Category pill
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                '${article.source} · '
                                '${_capitalize(article.category)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: catColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${article.ageRating}+',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        article.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          height: 1.4,
                        ),
                      ),
                      if (article.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          article.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (hasReadMore) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Read more →',
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(article.publishedAt),
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          Icon(
                            Icons.arrow_outward_rounded,
                            size: 14,
                            color: catColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      // "May 21" style — uses intl DateFormat.
      return DateFormat('MMM d').format(date);
    }
  }

  void _showArticlePreview(BuildContext context, NewsArticle article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (article.imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            article.imageUrl,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        article.source,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        article.title,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _formatDate(article.publishedAt),
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(
                        article.description,
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}



class _BottomNavBar extends StatefulWidget {
  final NavigationTab selectedTab;
  final Function(NavigationTab) onTabChanged;
  final Function(String) onMoreItemSelected;
  final bool moreIsActive;

  const _BottomNavBar({
    required this.selectedTab,
    required this.onTabChanged,
    required this.onMoreItemSelected,
    required this.moreIsActive,
  });

  @override
  State<_BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<_BottomNavBar> with TickerProviderStateMixin {
  late List<AnimationController> _tabControllers;

  @override
  void initState() {
    super.initState();
    _tabControllers = List.generate(
      NavigationTab.values.length,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in _tabControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectTab(NavigationTab tab) {
    HapticFeedback.selectionClick();
    final index = tab.index;
    _tabControllers[index].forward().then((_) {
      _tabControllers[index].reverse();
    });
    widget.onTabChanged(tab);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: NavigationTab.values.map((tab) {
              if (tab == NavigationTab.more) {
                return _MoreNavItem(
                  controller: _tabControllers[tab.index],
                  onItemSelected: widget.onMoreItemSelected,
                  isSelected: widget.moreIsActive,
                );
              }
              final isSelected = !widget.moreIsActive && widget.selectedTab == tab;
              return _NavBarItem(
                tab: tab,
                isSelected: isSelected,
                controller: _tabControllers[tab.index],
                onTap: () => _selectTab(tab),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final NavigationTab tab;
  final bool isSelected;
  final AnimationController controller;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.tab,
    required this.isSelected,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.8).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E293B).withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.icon,
                size: 24,
                color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreNavItem extends StatelessWidget {
  const _MoreNavItem({
    required this.controller,
    required this.onItemSelected,
    required this.isSelected,
  });
  final AnimationController controller;
  final Function(String) onItemSelected;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -68),
      onOpened: () => controller.forward().then((_) => controller.reverse()),
      onSelected: onItemSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      color: Colors.white,
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          value: 'visual_scanner',
          child: Row(
            children: [
              Icon(Icons.image_search_rounded, color: Color(0xFF1E293B), size: 20),
              SizedBox(width: 12),
              Text(
                'Visual Scanner',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'learn',
          child: Row(
            children: [
              Icon(Icons.forum_rounded, color: Color(0xFF1E293B), size: 20),
              SizedBox(width: 12),
              Text(
                'Community Hub',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'trust_lens',
          child: Row(
            children: [
              Icon(Icons.videocam_rounded, color: Color(0xFF00BFFF), size: 20),
              SizedBox(width: 12),
              Text(
                'Trust Lens',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.8).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeInOut),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1E293B).withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.more_horiz_rounded,
                size: 24,
                color: isSelected
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 4),
              Text(
                'More',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARE EXTENSION ROUTING SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _ShareRoutingSheet extends StatelessWidget {
  const _ShareRoutingSheet({
    required this.content,
    required this.onFactcheck,
    required this.onDebias,
  });
  final Map<String, dynamic> content;
  final VoidCallback onFactcheck;
  final VoidCallback onDebias;

  @override
  Widget build(BuildContext context) {
    final isImage = content['type'] == 'image';
    final text = content['text'] as String? ?? '';
    final preview = text.length > 80 ? '${text.substring(0, 78)}…' : text;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: Text('📤', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shared Content',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'What would you like to do with this ${isImage ? 'image' : 'text'}?',
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: isImage
                ? const Row(
                    children: [
                      Text('🖼️', style: TextStyle(fontSize: 20)),
                      SizedBox(width: 10),
                      Text(
                        'Image ready to analyze',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  )
                : Text(
                    '"$preview"',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                      height: 1.5,
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _RouteBtn(
                  icon: '⚡',
                  label: 'Fact-Check',
                  sublabel: 'Explain Why',
                  color: const Color(0xFF6366F1),
                  onTap: onFactcheck,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RouteBtn(
                  icon: '✍️',
                  label: 'De-Bias',
                  sublabel: 'Rewrite in Neutral',
                  color: const Color(0xFF22C55E),
                  onTap: onDebias,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteBtn extends StatelessWidget {
  const _RouteBtn({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });
  final String icon, label, sublabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.mediumImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  PAGE TRANSITION OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _TransitionInfo {
  const _TransitionInfo({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String   label;
  final IconData icon;
  final Color    color;
}

class _PageTransitionOverlay extends StatelessWidget {
  const _PageTransitionOverlay({
    required this.controller,
    required this.info,
  });
  final AnimationController controller;
  final _TransitionInfo     info;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;

        // Backdrop opacity: fade in 0→0.38, hold, fade out 0.62→1.0
        final backdropOpacity = t < 0.38
            ? t / 0.38
            : t > 0.62
                ? 1.0 - (t - 0.62) / 0.38
                : 1.0;

        // Center container: spring in, hold, shrink out
        final centerScale = t < 0.42
            ? Curves.elasticOut.transform((t / 0.42).clamp(0.0, 1.0)) * 0.25 + 0.75
            : t > 0.62
                ? 1.0 - (t - 0.62) / 0.38 * 0.18
                : 1.0;

        // Arc: 1.5 full rotations across the whole animation
        final arcAngle = t * math.pi * 3.0;

        // Icon pulse during the hold phase
        final iconPulse = (t >= 0.38 && t <= 0.62)
            ? 1.0 + 0.08 * math.sin((t - 0.38) / 0.24 * math.pi * 3)
            : 1.0;

        return Opacity(
          opacity: backdropOpacity.clamp(0.0, 1.0),
          child: Container(
            color: const Color(0xFFF1F5F9).withValues(alpha: 0.96),
            child: Center(
              child: Transform.scale(
                scale: centerScale.clamp(0.0, 1.15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 108, height: 108,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Faint track ring
                          CustomPaint(
                            size: const Size(108, 108),
                            painter: _RingTrackPainter(color: info.color),
                          ),
                          // Spinning gradient arc
                          Transform.rotate(
                            angle: arcAngle,
                            child: CustomPaint(
                              size: const Size(108, 108),
                              painter: _SpinningArcPainter(color: info.color),
                            ),
                          ),
                          // Pulsing center icon
                          Transform.scale(
                            scale: iconPulse,
                            child: Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                color: info.color.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(info.icon, color: info.color, size: 30),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: (backdropOpacity * 1.4).clamp(0.0, 1.0),
                      child: Text(
                        info.label,
                        style: TextStyle(
                          fontFamily:    'Montserrat',
                          fontSize:      14,
                          fontWeight:    FontWeight.w800,
                          color:         info.color,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: (backdropOpacity * 1.2).clamp(0.0, 1.0),
                      child: Container(
                        width: 36, height: 3,
                        decoration: BoxDecoration(
                          color:        info.color.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Faint full-circle track behind the arc
class _RingTrackPainter extends CustomPainter {
  const _RingTrackPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2 - 5,
      Paint()
        ..color       = color.withValues(alpha: 0.14)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );
  }

  @override
  bool shouldRepaint(_RingTrackPainter old) => old.color != color;
}

// 260° gradient arc — rotated externally via Transform.rotate
class _SpinningArcPainter extends CustomPainter {
  const _SpinningArcPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 1.44,
      false,
      Paint()
        ..shader = SweepGradient(
            startAngle: 0,
            endAngle:   math.pi * 2,
            colors:     [color.withValues(alpha: 0.0), color],
          ).createShader(rect)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap   = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpinningArcPainter old) => old.color != color;
}
