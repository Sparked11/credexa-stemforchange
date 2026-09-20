import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ignore: unnecessary_import
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'models/news_article.dart';
import 'news_article_page.dart';
import 'services/news_service.dart';
import 'services/share_service.dart';
import 'services/shared_content_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';
import 'debias_page.dart';
import 'community_hub_page.dart';
import 'trust_lens_page.dart';
import 'election_integrity_page.dart';
import 'onboarding_page.dart';
import 'auth_service.dart';
import 'auth_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'profile_page.dart';
import 'services/profile_service.dart';
import 'services/user_progress_service.dart';
import 'services/quest_service.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_widgets.dart';
import 'widgets/hero_3d_stage.dart';
import 'widgets/adaptive_chrome.dart';
import 'widgets/scroll_journey.dart';
import 'widgets/glass_button.dart';
import 'widgets/maturity_levels_sheet.dart';
import 'widgets/achievement_toast.dart';
import 'widgets/offline_banner.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/achievement_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  APP THEME SERVICE  — global dark / light mode with persistence
// ─────────────────────────────────────────────────────────────────────────────
class AppThemeService {
  AppThemeService._();

  static final mode = ValueNotifier<ThemeMode>(ThemeMode.light);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode.value = (p.getBool('darkMode') ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  static Future<void> toggle() async {
    final isDark = mode.value == ThemeMode.dark;
    mode.value = isDark ? ThemeMode.light : ThemeMode.dark;
    final p = await SharedPreferences.getInstance();
    await p.setBool('darkMode', !isDark);
  }

  static bool get isDark => mode.value == ThemeMode.dark;

  static final _buttonShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E293B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.slate100,
        fontFamily: 'Montserrat',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.slate100,
          foregroundColor: AppColors.slate800,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: _buttonShape),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(shape: _buttonShape),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E),
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF1E293B),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        fontFamily: 'Montserrat',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: _buttonShape),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(shape: _buttonShape),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Future.wait([
    AuthService.init(),
    AppThemeService.load(),
    NotificationService.init(),
  ]);
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
  bool? _hasSeenOnboarding; // null = still loading from prefs

  @override
  void initState() {
    super.initState();
    _loadOnboarding();
    AppThemeService.mode.addListener(_onThemeChanged);
  }

  void _onThemeChanged() => setState(() {});

  @override
  void dispose() {
    AppThemeService.mode.removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadOnboarding() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() =>
          _hasSeenOnboarding = p.getBool('hasSeenOnboarding') ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Credexa',
      debugShowCheckedModeBanner: false,
      themeMode: AppThemeService.mode.value,
      theme: AppThemeService.lightTheme,
      darkTheme: AppThemeService.darkTheme,
      home: ValueListenableBuilder<AuthUser?>(
        valueListenable: AuthService.authState,
        builder: (ctx, user, _) {
          // Still reading prefs — show blank splash to avoid flicker.
          if (_hasSeenOnboarding == null) {
            return const _BrandSplash();
          }
          // First launch → show onboarding before auth.
          if (!_hasSeenOnboarding!) {
            return OnboardingPage(
              onComplete: () => setState(() => _hasSeenOnboarding = true),
            );
          }
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
  late AnimationController _questSlideCtrl;
  final ChromeController _chrome = ChromeController();
  StreamSubscription<Achievement>? _achievementSub;
  StreamSubscription<String>? _notificationSub;
  static const double _navHeight = 64;
  String? _moreSubPage;
  bool   _showDailyQuest = false;
  bool   _questMinimized = false;
  bool            _showCredexaAd  = false;
  DateTime?       _lastAdShown;
  Map<String, dynamic>? _dailyQuestData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectivityService.start();
    _notificationSub = NotificationService.taps.listen(_onNotificationTap);
    _achievementSub = AchievementService.stream.listen((a) {
      if (!mounted) return;
      AchievementToaster.enqueue(
        context,
        a,
        onView: () => ProfileService.openProfile?.call(context),
      );
    });
    _pageTransitionController = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    )..forward();
    _questSlideCtrl = AnimationController(
      duration: const Duration(milliseconds: 480),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchPayload = NotificationService.consumeLaunchPayload();
      if (launchPayload != null) _onNotificationTap(launchPayload);
      _checkSharedContent();
      // Delay so the app finishes its entrance animation first.
      Future.delayed(const Duration(seconds: 2), _tryLoadDailyQuest);
      // Show Credexa+ ad on first launch after daily quest has appeared.
      Future.delayed(const Duration(seconds: 10), () => _maybeShowAd(delayMs: 0));
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
        // Local bank is instant and works offline; AI is the fallback.
        quest = QuestService.getLocalQuest();
      } catch (_) {
        try {
          quest = await QuestService.generateQuest();
        } catch (_) {
          return;
        }
      }
      await UserProgressService.cacheQuest(quest);
    }
    if (!mounted) return;
    setState(() { _dailyQuestData = quest; _showDailyQuest = true; });
    _questSlideCtrl.forward();
  }

  Future<void> _dismissDailyQuest() async {
    await _questSlideCtrl.reverse();
    if (mounted) setState(() { _showDailyQuest = false; _questMinimized = false; });
    await UserProgressService.markQuestSeen();
  }

  // X button: slide the banner out but keep the quest alive as a mini chip.
  Future<void> _minimizeQuest() async {
    HapticFeedback.lightImpact();
    await _questSlideCtrl.reverse();
    if (mounted) setState(() => _questMinimized = true);
    // Do NOT call markQuestSeen — quest remains accessible all day.
  }

  // Mini-chip tap: re-expand the banner.
  void _expandQuest() {
    setState(() => _questMinimized = false);
    _questSlideCtrl.forward();
  }

  // Show the Credexa+ ad with a 3-minute cooldown between showings.
  void _maybeShowAd({int delayMs = 1000}) {
    if (!kShowPromoAd) return;
    final now = DateTime.now();
    if (_lastAdShown != null && now.difference(_lastAdShown!).inMinutes < 3) return;
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _lastAdShown = DateTime.now();
      HapticFeedback.mediumImpact();
      setState(() => _showCredexaAd = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSharedContent();
      ConnectivityService.check();
    }
  }

  @override
  void didUpdateWidget(MainApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      _moreSubPage = null;
      _resetChromeAfterFrame();
      _triggerTransition();
      // Show ad after every tab switch (user just finished using a feature).
      _maybeShowAd(delayMs: 1500);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageTransitionController.dispose();
    _questSlideCtrl.dispose();
    _achievementSub?.cancel();
    _notificationSub?.cancel();
    _chrome.dispose();
    super.dispose();
  }

  // ── Transition helpers ───────────────────────────────────────────────────────

  void _triggerTransition() {
    if (!mounted) return;
    _pageTransitionController.forward(from: 0);
    HapticFeedback.selectionClick();
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
      )).then((_) => _maybeShowAd(delayMs: 800));
      return;
    }
    setState(() => _moreSubPage = item);
    _resetChromeAfterFrame();
    _triggerTransition();
  }

  Widget _buildPage() {
    if (_moreSubPage == 'election') {
      return const ElectionIntegrityPage(key: ValueKey('election'));
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

  // Tapping a Credexa notification lands on Home (and reopens the daily quest).
  void _onNotificationTap(String payload) {
    if (!mounted) return;
    if (_moreSubPage != null) setState(() => _moreSubPage = null);
    widget.onTabChanged(NavigationTab.home);
    if (_showDailyQuest && _questMinimized) _expandQuest();
  }

  void _resetChromeAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chrome.reset();
    });
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    if (n is ScrollUpdateNotification) {
      _chrome.onScroll(n.metrics.pixels, n.scrollDelta ?? 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final safeBottom = mq.padding.bottom;
    final navBottom = safeBottom > 0 ? safeBottom - 8 : 14.0;
    final navSpace = _navHeight + navBottom + 14;
    final onHomeTab = _moreSubPage == null &&
        (widget.selectedTab == NavigationTab.home ||
            widget.selectedTab == NavigationTab.more);
    final overlayPage = onHomeTab || (_moreSubPage == null &&
        widget.selectedTab == NavigationTab.newsFeed);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return ChromeScope(
      controller: _chrome,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        body: Stack(
          children: [
            // Status-bar strip: tinted dark while the hero is behind it so the
            // hero flows seamlessly to the top edge.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: mq.padding.top,
              child: ListenableBuilder(
                listenable: _chrome,
                builder: (context, _) {
                  final dark = onHomeTab ? _chrome.topDark : 0.0;
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: (dark > 0.5 || isDarkTheme)
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark,
                    child: ColoredBox(
                      color: Color.lerp(
                          scaffoldBg, const Color(0xFF03050B), dark)!,
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              bottom: false,
              child: LayoutBuilder(builder: (context, box) {
                return Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: Padding(
                        padding:
                            EdgeInsets.only(bottom: overlayPage ? 0 : navSpace),
                        child: FadeTransition(
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
                      ),
                    ),
                    if (_showDailyQuest &&
                        _dailyQuestData != null &&
                        !_questMinimized)
                      _DailyQuestBanner(
                        questData: _dailyQuestData!,
                        slideCtrl: _questSlideCtrl,
                        onMinimize: _minimizeQuest,
                        onAnswered: (bool correct) async {
                          await UserProgressService.recordQuestResult(
                              correct: correct);
                          await _dismissDailyQuest();
                        },
                      ),
                    if (_showDailyQuest && _questMinimized)
                      _QuestFloatingBadge(
                          onTap: _expandQuest, bottomInset: navSpace),
                    if (_showCredexaAd)
                      _CredexaPlusAd(
                        onDismiss: () {
                          if (mounted) setState(() => _showCredexaAd = false);
                        },
                      ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: navBottom + _navHeight + 12,
                      child: const OfflineBanner(),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: navBottom,
                      child: ListenableBuilder(
                        listenable: _chrome,
                        builder: (context, _) {
                          var dark = 0.0;
                          if (onHomeTab && _chrome.heroHeight > 0) {
                            final heroBottom =
                                _chrome.heroHeight - _chrome.offset;
                            final navTop =
                                box.maxHeight - navBottom - _navHeight;
                            dark = ((heroBottom - navTop) / 40).clamp(0.0, 1.0);
                          }
                          final hidden = overlayPage && _chrome.navHidden;
                          return AnimatedSlide(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            offset: hidden
                                ? Offset(0, (navSpace + 24) / _navHeight)
                                : Offset.zero,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: hidden ? 0 : 1,
                              child: _BottomNavBar(
                                selectedTab: widget.selectedTab,
                                dark: dark,
                                onTabChanged: (tab) {
                                  // Always clear any active More sub-page so
                                  // tapping Home while on a More sub-page
                                  // actually navigates back.
                                  if (_moreSubPage != null) {
                                    setState(() => _moreSubPage = null);
                                    _resetChromeAfterFrame();
                                  }
                                  widget.onTabChanged(tab);
                                },
                                onMoreItemSelected: _selectMoreItem,
                                moreIsActive: _moreSubPage != null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
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

  // Staggered entrance animation — runs once on first build.
  late final AnimationController _entranceCtrl;
  // Continuous pulse ring behind the logo.
  late final AnimationController _pulseCtrl;
  bool _maturityExpanded = true;

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
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
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

  List<JourneyStep> _journeySteps() => [
        JourneyStep(
          icon: Icons.videocam_rounded,
          color: const Color(0xFF0EA5E9),
          title: 'Spot it',
          body:
              'Point Trust Lens at any screen and flagged claims light up in real time.',
          cta: 'Open Trust Lens',
          onTap: () => widget.onNavigateMore?.call('trust_lens'),
        ),
        JourneyStep(
          icon: Icons.fact_check_rounded,
          color: const Color(0xFF6366F1),
          title: 'Check it',
          body:
              'Paste or snap a claim and a 3-model AI council explains what holds up and what does not.',
          cta: 'Explain a claim',
          onTap: () => widget.onNavigate(NavigationTab.explain),
        ),
        JourneyStep(
          icon: Icons.tune_rounded,
          color: const Color(0xFF14B8A6),
          title: 'Reframe it',
          body:
              'De-Bias rewrites loaded language into a neutral version so you see the facts.',
          cta: 'Try De-Bias',
          onTap: () => widget.onNavigate(NavigationTab.debiaseed),
        ),
        JourneyStep(
          icon: Icons.newspaper_rounded,
          color: const Color(0xFFF59E0B),
          title: 'Read wider',
          body:
              'Browse the news feed and follow each story back to the publisher to verify it.',
          cta: 'Open the news feed',
          onTap: () => widget.onNavigate(NavigationTab.newsFeed),
        ),
        JourneyStep(
          icon: Icons.forum_rounded,
          color: const Color(0xFF22C55E),
          title: 'Talk it through',
          body:
              'Ask "Is this real?" in the community and get anonymous, fact-checked answers.',
          cta: 'Join the Community Hub',
          onTap: () => widget.onNavigateMore?.call('learn'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final bottomSpace = MediaQuery.of(context).padding.bottom + 110;
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: HeroHeightReporter(
                child: _staggered(
                  Hero3DStage(
                    topInset: 64,
                    onCheckClaim: () =>
                        widget.onNavigate(NavigationTab.explain),
                    onOpenTrustLens: () =>
                        widget.onNavigateMore?.call('trust_lens'),
                  ),
                  0.0,
                  0.4,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(child: ScrollReveal(child: _buildMaturityTracker())),
            SliverToBoxAdapter(child: ScrollReveal(child: _buildStreak())),
            SliverToBoxAdapter(child: ScrollJourney(steps: _journeySteps())),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            SliverToBoxAdapter(
                child: ScrollReveal(child: _buildFeatures(context))),
            SliverToBoxAdapter(child: ScrollReveal(child: _buildMission())),
            SliverToBoxAdapter(child: ScrollReveal(child: _buildStat())),
            SliverToBoxAdapter(child: SizedBox(height: bottomSpace)),
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
          final pct = '${(s.predictionAccuracy * 100).round()}%';

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
                // ── Header (always visible, tap to collapse) ──
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _maturityExpanded = !_maturityExpanded);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.workspace_premium_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'MEDIA MATURITY',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFE0E7FF),
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
                      const SizedBox(width: 6),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showMaturityLevels(context),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.info_outline_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _maturityExpanded ? 0.0 : 0.5,
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        child: const Icon(Icons.keyboard_arrow_up_rounded,
                            color: Colors.white70, size: 22),
                      ),
                    ],
                  ),
                ),

                // ── Collapsible body ──
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                  child: _maturityExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),

                            // ── Progress bar ──
                            ClipRRect(
                              borderRadius: BorderRadius.circular(100),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.25),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (nextLvl != null)
                              Text(
                                '${lvl.pointsToNext(s.maturityPoints)} pts to ${nextLvl.title}',
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE0E7FF),
                                ),
                              ),
                            const SizedBox(height: 16),

                            // ── Stats row ──
                            Row(
                              children: [
                                _matStat(Icons.gps_fixed_rounded, 'Accuracy', pct),
                                _matDivider(),
                                _matStat(Icons.menu_book_rounded, 'Quests',
                                    '${s.questsAnswered}'),
                                _matDivider(),
                                _matStat(Icons.psychology_alt_rounded,
                                    'Predictions', '${s.predictionsTotal}'),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ── Growth message ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.trending_up_rounded,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.predictionsTotal >= 3
                                        ? 'Your prediction accuracy is $pct, proof that critical thinking can be learned.'
                                        : 'Answer daily quests and check claims to build evidence of your growth.',
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _matStat(IconData icon, String label, String value) => Expanded(
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.85),
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
          if (streak == 0) return const SizedBox.shrink();
          return _StreakCard(streak: streak);
        },
      ),
    );
  }

  Widget _dashboardLogo(double dark) {
    final useBadge =
        dark > 0.5 || Theme.of(context).brightness == Brightness.dark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      // Keep both variants pinned to the left edge so the swap never shifts.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [...previous, if (current != null) current],
      ),
      child: useBadge
          ? Row(
              key: const ValueKey('badge'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset('assets/logomain.png',
                        fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Credexa',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            )
          : Stack(
              key: const ValueKey('logo'),
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _PulseRing(controller: _pulseCtrl),
                Image.asset('assets/logomain.png',
                    height: 52, fit: BoxFit.contain),
              ],
            ),
    );
  }

  Widget _buildNavbar() {
    return GlassTopBar(
      builder: (context, dark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            GestureDetector(
              onTap: kDebugMode ? () async {
                final nav = Navigator.of(context);
                final p = await SharedPreferences.getInstance();
                await p.remove('hasSeenOnboarding');
                HapticFeedback.mediumImpact();
                nav.push(MaterialPageRoute(
                  builder: (_) => OnboardingPage(onComplete: nav.pop),
                ));
              } : null,
              child: SizedBox(height: 52, child: _dashboardLogo(dark)),
            ),
            const Spacer(),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: AppThemeService.mode,
              builder: (_, mode, _) {
                final isDark = mode == ThemeMode.dark;
                final base =
                    isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
                final iconBase = isDark
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF64748B);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    AppThemeService.toggle();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                          base, Colors.white.withValues(alpha: 0.16), dark),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => RotationTransition(
                        turns: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                        key: ValueKey(isDark),
                        size: 18,
                        color: Color.lerp(
                            iconBase, const Color(0xFFFBBF24), dark),
                      ),
                    ),
                  ),
                );
              },
            ),
            const ProfileIcon(),
          ],
        ),
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
          icon: Icons.how_to_vote_rounded,
          color: Color(0xFF1D4ED8),
          title: 'Election Integrity',
          desc: 'Fact-check political claims with bias analysis.',
        ),
        (
          icon: Icons.videocam_rounded,
          color: Color(0xFF00BFFF),
          title: 'Trust Lens',
          desc: 'Live AR camera scanner — bias overlay on any screen.',
        ),
      ],
    ];

    final items = [...pages[0], ...pages[1]];

    void tapFeature(int index) {
      HapticFeedback.lightImpact();
      switch (index) {
        case 0: widget.onNavigate(NavigationTab.explain);
        case 1: widget.onNavigate(NavigationTab.debiaseed);
        case 2: widget.onNavigate(NavigationTab.newsFeed);
        case 3: widget.onNavigateMore?.call('learn');
        case 4: widget.onNavigateMore?.call('election');
        case 5: widget.onNavigateMore?.call('trust_lens');
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore Features',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: List.generate(items.length, (i) {
              final f = items[i];
              return TiltCard(
                onTap: () => tapFeature(i),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF273449), AppColors.slate800]
                          : [Colors.white, const Color(0xFFF1F5F9)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: f.color.withValues(alpha: isDark ? 0.18 : 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              f.color.withValues(alpha: 0.9),
                              f.color.withValues(alpha: 0.6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: f.color.withValues(alpha: 0.45),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(f.icon, color: Colors.white, size: 23),
                      ),
                      const Spacer(),
                      Text(
                        f.title,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.desc,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface.withValues(alpha: 0.72),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBadge(
                    icon: Icons.public_rounded,
                    color: Color(0xFF22C55E),
                    size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'UN SDG Goal 16',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Peace, Justice & Strong Institutions',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Credexa promotes access to information and protects fundamental freedoms for all.',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            // Explicit tap affordance
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See the problem we\'re solving',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF22C55E),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 14, color: Color(0xFF22C55E)),
                ],
              ),
            ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
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
                                fontSize: 11,
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
                    icon: Icons.public_rounded,
                    color: const Color(0xFF0EA5E9),
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
                    icon: Icons.groups_rounded,
                    color: const Color(0xFF6366F1),
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
                    icon: Icons.balance_rounded,
                    color: const Color(0xFFF59E0B),
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
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBadge(icon: icon, color: color, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    )),
              ),
            ]),
            const SizedBox(height: 10),
            Text(body,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.75),
                  height: 1.6,
                )),
          ],
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DAILY QUEST BANNER — slides down from top once per day
// ─────────────────────────────────────────────────────────────────────────────

class _DailyQuestBanner extends StatefulWidget {
  const _DailyQuestBanner({
    required this.questData,
    required this.slideCtrl,
    required this.onMinimize,
    required this.onAnswered,
  });
  final Map<String, dynamic> questData;
  final AnimationController slideCtrl;
  final VoidCallback onMinimize;
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
            onTap: _revealed ? null : widget.onMinimize,
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          // Card
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LayoutBuilder(
                builder: (context, constraints) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - 24).clamp(400.0, 640.0),
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
                                    fontSize: 11,
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
                            onTap: widget.onMinimize,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Icon(Icons.close_rounded,
                                  size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Post text (styled as social card) ────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF0F4FF), Color(0xFFF5F0FF)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD4CCFF), width: 1.5),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      widget.questData['topic_emoji'] as String? ?? '📱',
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Sample Post',
                                      style: TextStyle(
                                        fontFamily: 'Montserrat',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    Text(
                                      'Spot the manipulation 👇',
                                      style: TextStyle(
                                        fontFamily: 'Montserrat',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.questData['post_text'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 14,
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
                          const letters = ['A', 'B', 'C', 'D'];
                          const letterColors = [
                            Color(0xFF6366F1), // indigo
                            Color(0xFF8B5CF6), // purple
                            Color(0xFFF59E0B), // amber
                            Color(0xFFEC4899), // pink
                          ];

                          Color bg        = Colors.white;
                          Color border    = const Color(0xFFE2E8F0);
                          Color textColor = const Color(0xFF1E293B);
                          Color circleColor = letterColors[i % 4];
                          Widget circleChild = Text(
                            letters[i % 4],
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: circleColor,
                            ),
                          );

                          if (_revealed) {
                            if (i == _correctIndex) {
                              bg          = const Color(0xFFEFFFF5);
                              border      = const Color(0xFF22C55E);
                              textColor   = const Color(0xFF15803D);
                              circleColor = const Color(0xFF22C55E);
                              circleChild = const Icon(Icons.check_rounded,
                                  color: Color(0xFF22C55E), size: 14);
                            } else if (i == _selected) {
                              bg          = const Color(0xFFFFEDE8);
                              border      = const Color(0xFFEF4444);
                              textColor   = const Color(0xFFB91C1C);
                              circleColor = const Color(0xFFEF4444);
                              circleChild = const Icon(Icons.close_rounded,
                                  color: Color(0xFFEF4444), size: 14);
                            } else {
                              textColor = const Color(0xFF94A3B8);
                            }
                          } else if (_selected == i) {
                            bg     = const Color(0xFFEFF6FF);
                            border = letterColors[i % 4];
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GestureDetector(
                              onTap: () => _pick(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: border, width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 220),
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: circleColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(child: circleChild),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _options[i],
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
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
                        child: GlassButton(
                          height: 50,
                          radius: 14,
                          accent: _selected == _correctIndex
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF6366F1),
                          icon: _selected == _correctIndex
                              ? Icons.emoji_events_rounded
                              : Icons.lightbulb_rounded,
                          label: _selected == _correctIndex
                              ? 'Nice work! +15 pts'
                              : 'Got it! Keep learning +5 pts',
                          fontSize: 13,
                          onTap: () =>
                              widget.onAnswered(_selected == _correctIndex),
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
      ..color = const Color(0xFF22C55E).withValues(alpha: 0.12);

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
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
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
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCategory = category;
      _newsArticles = NewsService.fetchNewsByCategory(category);
    });
  }

  Widget _buildNavbar() {
    return GlassTopBar.simple(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (kDebugMode)
              GestureDetector(
                onTap: () async {
                  final nav = Navigator.of(context);
                  final p = await SharedPreferences.getInstance();
                  await p.remove('hasSeenOnboarding');
                  HapticFeedback.mediumImpact();
                  nav.push(MaterialPageRoute(
                    builder: (_) => OnboardingPage(onComplete: nav.pop),
                  ));
                },
                child: Image.asset('assets/logomain.png', height: 52, fit: BoxFit.contain),
              )
            else
              Image.asset('assets/logomain.png', height: 52, fit: BoxFit.contain),
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
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.surface,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.outlineVariant,
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
                                ? Theme.of(context).colorScheme.surface
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
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
                return const SliverToBoxAdapter(child: _NewsSkeleton());
              } else if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppErrorCard(
                      title: isOfflineError(snapshot.error)
                          ? "You're offline"
                          : 'Unable to load news',
                      message: friendlyError(snapshot.error),
                      onRetry: () => _changeCategory(_selectedCategory),
                    ),
                  ),
                );
              }

              final articles = snapshot.data ?? [];
              if (articles.isEmpty) {
                return SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.newspaper_rounded,
                    color: const Color(0xFFF59E0B),
                    title: 'No stories here yet',
                    message: _selectedCategory == 'general'
                        ? 'There are no articles right now. Check back soon.'
                        : 'There are no $_selectedCategory articles right now. Try another category.',
                    actionLabel: _selectedCategory == 'general'
                        ? 'Refresh'
                        : 'Show general news',
                    onAction: () => _changeCategory('general'),
                  ),
                );
              }

              return SliverMainAxisGroup(
                slivers: [
                  if (NewsService.servedStale)
                    const SliverToBoxAdapter(child: _StaleNewsNotice()),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final article = articles[index];
                        return _NewsArticleCard(article: article);
                      },
                      childCount: articles.length,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.of(context).padding.bottom + 110),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => NewsArticlePage(article: article),
            ));
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 140),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.1)),
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
                      color: Theme.of(context).colorScheme.surface,
                      child: Image.network(
                        article.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Theme.of(context).colorScheme.surface,
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
                                color: catColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                '${article.source} · '
                                '${_capitalize(article.category)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 11,
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
                              color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${article.ageRating}+',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
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
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                      if (article.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          article.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.72),
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Read full article →',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => openArticleSource(article),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.link_rounded,
                                        size: 16, color: Color(0xFF0EA5E9)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        sourceDomain(article),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0EA5E9),
                                          decoration:
                                              TextDecoration.underline,
                                          decorationColor: Color(0xFF0EA5E9),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.open_in_new_rounded,
                                        size: 13, color: Color(0xFF0EA5E9)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(article.publishedAt),
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
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

}



class _BottomNavBar extends StatefulWidget {
  final NavigationTab selectedTab;
  final Function(NavigationTab) onTabChanged;
  final Function(String) onMoreItemSelected;
  final bool moreIsActive;

  /// 0 = light surface behind the bar, 1 = dark hero behind it.
  final double dark;

  const _BottomNavBar({
    required this.selectedTab,
    required this.onTabChanged,
    required this.onMoreItemSelected,
    required this.moreIsActive,
    this.dark = 0,
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
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final d = widget.dark;
    // Glass tint follows what is behind the bar so it never sticks out.
    final lightFill = isDarkTheme
        ? AppColors.slate800.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.74);
    final darkFill = const Color(0xFF0B1220).withValues(alpha: 0.62);
    final fill = Color.lerp(lightFill, darkFill, d)!;
    final edge = Color.lerp(
      Colors.white.withValues(alpha: isDarkTheme ? 0.10 : 0.85),
      Colors.white.withValues(alpha: 0.16),
      d,
    )!;
    final fg = Color.lerp(
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
      Colors.white.withValues(alpha: 0.7),
      d,
    )!;
    final accent = Color.lerp(_navAccent(context), AppColors.green, d)!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10 + 0.14 * d),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: _MainAppState._navHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: edge),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: NavigationTab.values.map((tab) {
                if (tab == NavigationTab.more) {
                  return _MoreNavItem(
                    controller: _tabControllers[tab.index],
                    onItemSelected: widget.onMoreItemSelected,
                    isSelected: widget.moreIsActive,
                    accent: accent,
                    idle: fg,
                  );
                }
                final isSelected =
                    !widget.moreIsActive && widget.selectedTab == tab;
                return _NavBarItem(
                  tab: tab,
                  isSelected: isSelected,
                  controller: _tabControllers[tab.index],
                  onTap: () => _selectTab(tab),
                  accent: accent,
                  idle: fg,
                );
              }).toList(),
            ),
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
  final Color accent;
  final Color idle;

  const _NavBarItem({
    required this.tab,
    required this.isSelected,
    required this.controller,
    required this.onTap,
    required this.accent,
    required this.idle,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.85).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _NavPill(
          icon: tab.icon,
          label: tab.label,
          isSelected: isSelected,
          accent: accent,
          idle: idle,
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final Color accent;
  final Color idle;
  const _NavPill({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.idle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: isSelected ? accent : idle),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? accent : idle,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreNavItem extends StatelessWidget {
  const _MoreNavItem({
    required this.controller,
    required this.onItemSelected,
    required this.isSelected,
    required this.accent,
    required this.idle,
  });
  final AnimationController controller;
  final Function(String) onItemSelected;
  final bool isSelected;
  final Color accent;
  final Color idle;

  PopupMenuItem<String> _item(
      BuildContext context, String value, IconData icon, Color color, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -76),
      onOpened: () {
        HapticFeedback.selectionClick();
        controller.forward().then((_) => controller.reverse());
      },
      onSelected: (v) {
        HapticFeedback.lightImpact();
        onItemSelected(v);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      itemBuilder: (context) => [
        _item(context, 'election', Icons.how_to_vote_rounded,
            const Color(0xFF1D4ED8), 'Election Integrity'),
        _item(context, 'learn', Icons.forum_rounded, const Color(0xFF6366F1),
            'Community Hub'),
        _item(context, 'trust_lens', Icons.videocam_rounded,
            const Color(0xFF00BFFF), 'Trust Lens'),
      ],
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.85).animate(
          CurvedAnimation(parent: controller, curve: Curves.easeInOut),
        ),
        child: _NavPill(
          icon: Icons.more_horiz_rounded,
          label: 'More',
          isSelected: isSelected,
          accent: accent,
          idle: idle,
        ),
      ),
    );
  }
}

Color _navAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.green
        : AppColors.greenDark;

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

    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                child: const Icon(Icons.ios_share_rounded,
                    color: Color(0xFF22C55E), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shared Content',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'What would you like to do with this ${isImage ? 'image' : 'text'}?',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.7),
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
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
            ),
            child: isImage
                ? Row(
                    children: [
                      const Icon(Icons.image_rounded,
                          color: Color(0xFF6366F1), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Image ready to analyze',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  )
                : Text(
                    '"$preview"',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.8),
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
                  icon: Icons.bolt_rounded,
                  label: 'Fact-Check',
                  sublabel: 'Explain Why',
                  color: const Color(0xFF6366F1),
                  onTap: onFactcheck,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RouteBtn(
                  icon: Icons.edit_note_rounded,
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
  final IconData icon;
  final String label, sublabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassButton(
      height: 108,
      radius: 18,
      filled: false,
      accent: color,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 30),
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
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
//  QUEST MINI CHIP  —  persistent pill shown after the banner is minimized
// ─────────────────────────────────────────────────────────────────────────────

class _QuestFloatingBadge extends StatefulWidget {
  const _QuestFloatingBadge({required this.onTap, this.bottomInset = 0});
  final VoidCallback onTap;
  final double bottomInset;

  @override
  State<_QuestFloatingBadge> createState() => _QuestFloatingBadgeState();
}

class _QuestFloatingBadgeState extends State<_QuestFloatingBadge>
    with SingleTickerProviderStateMixin {
  static const double _collapsedW = 52;
  static const double _expandedW = 148;
  static const double _h = 52;
  static const double _margin = 12;

  // Remembered for the session so the badge returns where the user left it.
  static double? _savedTop;
  static bool _savedDockRight = true;

  late final AnimationController _pulse;
  Timer? _collapseTimer;
  bool _expanded = true;
  bool _dragging = false;
  bool _dockRight = _savedDockRight;
  double? _top;
  double _dragLeft = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _collapseTimer = Timer(const Duration(seconds: 4), _collapse);
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _collapse() {
    if (mounted && !_dragging) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final minTop = 84.0;
        final maxTop =
            (h - _h - 16 - widget.bottomInset).clamp(minTop, double.infinity);
        _top ??= (_savedTop ?? h * 0.55).clamp(minTop, maxTop);
        final curW = _expanded ? _expandedW : _collapsedW;
        final dockedLeft = _dockRight ? w - curW - _margin : _margin;
        final left = _dragging ? _dragLeft : dockedLeft;

        return Stack(
          children: [
            AnimatedPositioned(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: left,
              top: _top,
              child: IgnorePointer(
                ignoring: keyboardOpen,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: keyboardOpen ? 0 : (_dragging ? 1 : 0.94),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onTap();
                    },
                    onPanStart: (_) {
                      HapticFeedback.selectionClick();
                      _collapseTimer?.cancel();
                      setState(() {
                        _dragging = true;
                        _dragLeft = dockedLeft;
                      });
                    },
                    onPanUpdate: (d) {
                      setState(() {
                        _dragLeft = (_dragLeft + d.delta.dx)
                            .clamp(_margin, w - curW - _margin);
                        _top = (_top! + d.delta.dy).clamp(minTop, maxTop);
                      });
                    },
                    onPanEnd: (_) {
                      HapticFeedback.lightImpact();
                      final centre = _dragLeft + curW / 2;
                      setState(() {
                        _dragging = false;
                        _dockRight = centre > w / 2;
                        _savedDockRight = _dockRight;
                        _savedTop = _top;
                      });
                      _collapseTimer =
                          Timer(const Duration(seconds: 3), _collapse);
                    },
                    child: _buildBadge(curW),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildBadge(double curW) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
        scale: 1.0 + _pulse.value * 0.03,
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: curW,
        height: _h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(_h / 2),
          border: Border.all(color: const Color(0xFFFBBF24), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.menu_book_rounded,
                    color: Color(0xFF6366F1), size: 24),
                if (curW > _collapsedW + 20) ...[
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Daily Quest',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Positioned(
              top: 9,
              right: curW > _collapsedW + 20 ? 10 : 9,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color.lerp(const Color(0xFFF59E0B),
                        const Color(0xFFEA580C), _pulse.value),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STREAK CARD  —  bobble on tap + floating fire particles
// ─────────────────────────────────────────────────────────────────────────────

class _StreakCard extends StatefulWidget {
  const _StreakCard({required this.streak});
  final int streak;

  @override
  State<_StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<_StreakCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bobble;
  final List<({int id, double x, double y})> _fires = [];
  int _fireId = 0;

  @override
  void initState() {
    super.initState();
    _bobble = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _bobble.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails d) {
    HapticFeedback.mediumImpact();
    _bobble.forward(from: 0.0);
    final id = _fireId++;
    setState(() =>
        _fires.add((id: id, x: d.localPosition.dx, y: d.localPosition.dy)));
  }

  void _removeFire(int id) {
    if (mounted) setState(() => _fires.removeWhere((f) => f.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Bobble-animated card ─────────────────────────────────────────
        AnimatedBuilder(
          animation: _bobble,
          builder: (_, child) {
            final t = _bobble.value;
            double sx, sy;
            if (t < 0.18) {
              // Phase 1: quick squash — compress vertically, widen horizontally
              final p = t / 0.18;
              sx = 1.0 + p * 0.09;
              sy = 1.0 - p * 0.08;
            } else {
              // Phase 2: elastic spring-back with overshoot
              final p = Curves.elasticOut
                  .transform(((t - 0.18) / 0.82).clamp(0.0, 1.0));
              sx = 1.09 - p * 0.09;
              sy = 0.92 + p * 0.08;
            }
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(sx, sy, 1.0),
              child: child,
            );
          },
          child: GestureDetector(
            onTapDown: _onTapDown,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  const Icon(Icons.local_fire_department_rounded,
                      color: Color(0xFFF97316), size: 32),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: widget.streak),
                        duration: const Duration(milliseconds: 1100),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, _) => Text(
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
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'Keep it up!',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Fire particles ───────────────────────────────────────────────
        ..._fires.map((f) => _FireParticle(
              key: ValueKey(f.id),
              x: f.x,
              y: f.y,
              onDone: () => _removeFire(f.id),
            )),
      ],
    );
  }
}

// ── Single floating fire emoji ────────────────────────────────────────────────
class _FireParticle extends StatefulWidget {
  const _FireParticle({
    super.key,
    required this.x,
    required this.y,
    required this.onDone,
  });
  final double x, y;
  final VoidCallback onDone;

  @override
  State<_FireParticle> createState() => _FireParticleState();
}

class _FireParticleState extends State<_FireParticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        final dy = Curves.easeOut.transform(t) * -80.0;
        final dx = math.sin(t * math.pi * 2.5) * 9.0;
        final opacity = (t < 0.45 ? 1.0 : 1.0 - ((t - 0.45) / 0.55))
            .clamp(0.0, 1.0);
        final scale = (1.3 - t * 0.9).clamp(0.1, 1.5);

        return Positioned(
          left: widget.x - 12 + dx,
          top: widget.y - 12 + dy,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: const Icon(Icons.local_fire_department_rounded,
                    color: Color(0xFFF97316), size: 24),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SOCIAL POSTS MARQUEE  —  variable-width tiles sized to each image's aspect ratio
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  CREDEXA+ AD — purple accent constant
// ─────────────────────────────────────────────────────────────────────────────

const _kAdPurple = Color(0xFF9333EA);

// Renders "Credexa" in [base] colour with a glowing purple "+".
Widget _credexaPlusText({
  double size = 28,
  FontWeight weight = FontWeight.w900,
  Color base = Colors.white,
}) =>
    RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: size,
          fontWeight: weight,
          color: base,
        ),
        children: [
          const TextSpan(text: 'Credexa'),
          TextSpan(
            text: '+',
            style: TextStyle(
              color: _kAdPurple,
              shadows: [Shadow(blurRadius: 14, color: _kAdPurple)],
            ),
          ),
        ],
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
//  CREDEXA+ AD OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _CredexaPlusAd extends StatefulWidget {
  const _CredexaPlusAd({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  State<_CredexaPlusAd> createState() => _CredexaPlusAdState();
}

class _CredexaPlusAdState extends State<_CredexaPlusAd>
    with TickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _staggerCtrl;
  late final AnimationController _floatCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl   = AnimationController(
      duration: const Duration(milliseconds: 650),
      reverseDuration: const Duration(milliseconds: 300),
      vsync: this,
    )..forward();
    _shimmerCtrl = AnimationController(duration: const Duration(milliseconds: 1800), vsync: this)..repeat();
    _pulseCtrl   = AnimationController(duration: const Duration(milliseconds: 1400), vsync: this)..repeat(reverse: true);
    _staggerCtrl = AnimationController(duration: const Duration(milliseconds: 1000), vsync: this);
    _floatCtrl   = AnimationController(duration: const Duration(milliseconds: 2600), vsync: this)..repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) _staggerCtrl.forward();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _shimmerCtrl.dispose();
    _pulseCtrl.dispose();
    _staggerCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  // Dismiss (X or tap-outside) → haptic tap, then reverse the enter animation so
  // the card fades + scales out before the parent removes it.
  bool _dismissing = false;
  Future<void> _handleDismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    HapticFeedback.lightImpact();
    await _enterCtrl.reverse();
    if (mounted) widget.onDismiss();
  }

  // ── Mini browser mockup ─────────────────────────────────────────────────────

  Widget _buildBrowserMockup() {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            // Browser chrome bar
            Container(
              height: 22,
              color: const Color(0xFF334155),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final c in [const Color(0xFFEF4444), const Color(0xFFF59E0B), const Color(0xFF22C55E)])
                    Container(
                      width: 7, height: 7,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '🔒  twitter.com/home',
                        style: TextStyle(fontFamily: 'Montserrat', fontSize: 6, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Page content
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 5, width: double.infinity,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3))),
                        const SizedBox(height: 4),
                        Container(height: 4, width: 180,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3))),
                        const SizedBox(height: 4),
                        Container(height: 4, width: 140,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3))),
                        const SizedBox(height: 6),
                        // Credexa warning label
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_rounded, color: Colors.white, size: 7),
                              SizedBox(width: 3),
                              Text('MISLEADING', style: TextStyle(fontFamily: 'Montserrat', fontSize: 6, fontWeight: FontWeight.w800, color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Credexa+ badge — bottom right
                  Positioned(
                    right: 7, bottom: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_kAdPurple, Color(0xFF00BFFF)]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('C+', style: TextStyle(fontFamily: 'Montserrat', fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
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

  // ── Staggered feature pill ──────────────────────────────────────────────────

  Widget _featurePill(IconData icon, String label, double staggerStart) {
    // Expanded must be the direct Row child — keep it outside AnimatedBuilder.
    return Expanded(
      child: AnimatedBuilder(
        animation: _staggerCtrl,
        builder: (_, child) {
          final t = Interval(staggerStart, (staggerStart + 0.45).clamp(0.0, 1.0), curve: Curves.easeOutBack)
              .transform(_staggerCtrl.value);
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kAdPurple.withValues(alpha: 0.38)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _kAdPurple, size: 18),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontFamily: 'Montserrat', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enterCurved = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    final fadeCurved  = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeIn);

    return AnimatedBuilder(
      animation: Listenable.merge([_enterCtrl, _shimmerCtrl, _pulseCtrl, _floatCtrl]),
      builder: (_, __) {
        final pulse   = _pulseCtrl.value;
        final shimmer = _shimmerCtrl.value;
        final float   = math.sin(_floatCtrl.value * math.pi) * 5.0;

        return FadeTransition(
          opacity: fadeCurved,
          child: GestureDetector(
            // tap outside card → dismiss
            onTap: _handleDismiss,
            child: Container(
              color: Colors.black.withValues(alpha: 0.68),
              alignment: Alignment.center,
              child: GestureDetector(
                // block dismiss when touching the card itself
                onTap: () {},
                child: ScaleTransition(
                  scale: enterCurved,
                  child: Transform.translate(
                    offset: Offset(0, float),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D1225), Color(0xFF1A0D35), Color(0xFF0D1225)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _kAdPurple.withValues(alpha: 0.30 + pulse * 0.22),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _kAdPurple.withValues(alpha: 0.28 + pulse * 0.14),
                            blurRadius: 44 + pulse * 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: const Color(0xFF00BFFF).withValues(alpha: 0.08 + pulse * 0.06),
                            blurRadius: 60,
                            offset: const Offset(0, -12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(27),
                        child: Stack(
                          children: [
                            // ── Shimmer sweep across card ──────────────────────
                            Positioned.fill(
                              child: ShaderMask(
                                shaderCallback: (rect) => LinearGradient(
                                  begin: Alignment(-1.5 + shimmer * 4, -0.5),
                                  end:   Alignment( shimmer * 4,        0.5),
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(alpha: 0.045),
                                    Colors.transparent,
                                  ],
                                ).createShader(rect),
                                child: Container(color: Colors.white),
                              ),
                            ),

                            // ── Top tagline bar ────────────────────────────────
                            Positioned(
                              top: 0, left: 0, right: 0,
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      _kAdPurple.withValues(alpha: 0.18),
                                      const Color(0xFF00BFFF).withValues(alpha: 0.10),
                                    ],
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final word in ['Stay', 'Rooted', 'In', 'Reality'])
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text(
                                          word,
                                          style: TextStyle(
                                            fontFamily: 'Montserrat',
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: word == 'Reality'
                                                ? _kAdPurple
                                                : Colors.white.withValues(alpha: 0.45),
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // ── Main card content ──────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 40, 20, 22),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Badge + close button
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _kAdPurple.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(100),
                                          border: Border.all(color: _kAdPurple.withValues(alpha: 0.45)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.extension_rounded, color: _kAdPurple, size: 10),
                                            SizedBox(width: 4),
                                            Text('CHROME EXTENSION',
                                              style: TextStyle(fontFamily: 'Montserrat', fontSize: 8, fontWeight: FontWeight.w800, color: _kAdPurple, letterSpacing: 0.8)),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: _handleDismiss,
                                        child: Container(
                                          width: 28, height: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.09),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(Icons.close_rounded,
                                              color: Colors.white.withValues(alpha: 0.55), size: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  // Browser mockup illustration
                                  _buildBrowserMockup(),
                                  const SizedBox(height: 16),

                                  // Hero headline
                                  Text(
                                    'Stay connected with',
                                    style: TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.50)),
                                  ),
                                  const SizedBox(height: 2),
                                  _credexaPlusText(size: 30),
                                  const SizedBox(height: 5),
                                  Text(
                                    'All in your browser',
                                    style: TextStyle(fontFamily: 'Montserrat', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.65)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Real-time misinformation detector\nfor social media posts in Chrome.',
                                    style: TextStyle(fontFamily: 'Montserrat', fontSize: 11, color: Colors.white.withValues(alpha: 0.40), height: 1.5),
                                  ),
                                  const SizedBox(height: 16),

                                  // Feature pills — staggered entrance
                                  Row(
                                    children: [
                                      _featurePill(Icons.lock_outline_rounded,  'Secure',   0.00),
                                      const SizedBox(width: 8),
                                      _featurePill(Icons.bolt_rounded,           'Fast',     0.18),
                                      const SizedBox(width: 8),
                                      _featurePill(Icons.gps_fixed_rounded,      'Accurate', 0.36),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Pulsing CTA button
                                  Container(
                                    width: double.infinity,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _kAdPurple,
                                          Color.lerp(_kAdPurple, const Color(0xFF00BFFF), 0.45 + pulse * 0.22)!,
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _kAdPurple.withValues(alpha: 0.38 + pulse * 0.20),
                                          blurRadius: 18 + pulse * 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          HapticFeedback.lightImpact();
                                          launchUrl(
                                            Uri.parse('https://chromewebstore.google.com/detail/abflkecbafbaojegnhpdcdlkcmpdemgd?utm_source=item-share-cb'),
                                            mode: LaunchMode.externalApplication,
                                          );
                                        },
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Text('Get ',
                                              style: TextStyle(fontFamily: 'Montserrat', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                                            _credexaPlusText(size: 15),
                                            const Text('  Free',
                                              style: TextStyle(fontFamily: 'Montserrat', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: Text(
                                      'Available on the Chrome Web Store',
                                      style: TextStyle(fontFamily: 'Montserrat', fontSize: 9, color: Colors.white.withValues(alpha: 0.28)),
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
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _BrandSplash extends StatelessWidget {
  const _BrandSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logomain.png', width: 120, height: 120),
              const SizedBox(height: 20),
              const Text(
                'Credexa',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _StaleNewsNotice extends StatelessWidget {
  const _StaleNewsNotice();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Showing saved stories. Reconnect to see the latest news.',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewsSkeleton extends StatefulWidget {
  const _NewsSkeleton();

  @override
  State<_NewsSkeleton> createState() => _NewsSkeletonState();
}

class _NewsSkeletonState extends State<_NewsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final a = 0.06 + 0.06 * _c.value;
        Widget bar(double w, double h) => Container(
              width: w,
              height: h,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: base.withValues(alpha: a),
                borderRadius: BorderRadius.circular(6),
              ),
            );
        return Column(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: base.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 140,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: base.withValues(alpha: a),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    bar(120, 12),
                    bar(double.infinity, 16),
                    bar(220, 16),
                    bar(160, 11),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
