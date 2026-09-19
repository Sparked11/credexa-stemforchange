import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/quest.dart';
import 'services/profile_service.dart';
import 'auth_service.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_widgets.dart';
import 'widgets/glass_button.dart';
import 'dart:math' as math;

// ── Design tokens (match app-wide language) ───────────────────────────────────
const _kSecondary = Color(0xFF64748B);
const _kAccent = Color(0xFF22C55E);

extension _QuestTheme on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;
  Color get ink => Theme.of(this).colorScheme.onSurface;
  Color get muted =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.72);
  Color get surf => _isDark ? AppColors.slate800 : Colors.white;
  Color get pageBg =>
      _isDark ? AppColors.slate900 : const Color(0xFFF1F5F9);
  Color get subtle =>
      _isDark ? AppColors.slate900 : const Color(0xFFF8FAFC);
  Color get line => _isDark ? AppColors.slate700 : const Color(0xFFE2E8F0);
  Color tint(Color c) => c.withValues(alpha: _isDark ? 0.16 : 0.10);
}

const _kCardRadius = 24.0;
const _kBtnRadius = 14.0;

const _kCardShadow = BoxShadow(
  color: Color(0x0F000000), // black @ 0.06
  blurRadius: 20,
  offset: Offset(0, 6),
);

// ── Learning Quests page ──────────────────────────────────────────────────────
class LearningQuestsPage extends StatefulWidget {
  const LearningQuestsPage({super.key});

  @override
  State<LearningQuestsPage> createState() => _LearningQuestsPageState();
}

class _LearningQuestsPageState extends State<LearningQuestsPage>
    with TickerProviderStateMixin {
  // ── Quest progression state ─────────────────────────────────────────────────
  int _currentQuestIndex = 0;
  int _selectedOptionIndex = -1; // -1 = not yet answered
  bool _answered = false;
  bool _correct = false;
  int _totalXp = 0;
  int _streak = 0;
  int _questsCompleted = 0;
  int _correctCount = 0;
  int _bestStreak = 0;

  // Tracks whether the user has started the quest run (false => landing screen).
  bool _started = false;
  // Tracks whether the whole quest run is finished (=> completion screen).
  bool _finished = false;
  // Tracks whether the landing-screen header is expanded or collapsed.
  bool _headerExpanded = true;
  // Badges unlocked during this run (shown on completion screen).
  final List<BadgeInfo> _newlyEarnedBadges = [];

  late final AnimationController _feedbackCtrl; // correct/incorrect reveal
  late final AnimationController _progressCtrl; // XP bar progress
  late final AnimationController _xpPulseCtrl; // XP pill pulse on correct
  late final AnimationController _pathPulseCtrl; // winding path current-node pulse
  late final Animation<double> _revealAnim;

  // ── The preset quest bank (15 quests) ───────────────────────────────────────
  final List<Quest> _quests = const [
    Quest(
      id: 'q1',
      postText:
          'BREAKING: Scientists CONFIRM vaccines cause 47% increase in autism '
          'risk, study suppressed by Big Pharma — share before they delete this!',
      technique: 'Fear Appeal',
      topic: 'Health',
      difficulty: QuestDifficulty.easy,
      options: [
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: true,
          explanation: 'Correct — panic and urgency are weaponised here.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation:
              'Cherry picking selectively uses data; this post leans on fear.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation:
              'No specific authority is cited — the hook is panic, not credentials.',
        ),
        QuestOption(
          label: 'Bandwagon',
          isCorrect: false,
          explanation:
              'Bandwagon relies on "everyone is doing it" — not the case here.',
        ),
      ],
      explanation:
          'The ALL CAPS "BREAKING" and conspiratorial "share before they '
          'delete this" are designed to trigger panic and bypass critical '
          'thinking.',
    ),
    Quest(
      id: 'q2',
      postText:
          'Every single independent study agrees: renewable energy creates '
          'MORE jobs than fossil fuels. Anyone who says otherwise is lying.',
      technique: 'Loaded Language',
      topic: 'Environment',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'Loaded Language',
          isCorrect: true,
          explanation:
              'Correct — absolute words eliminate nuance and brand dissent.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation:
              'No specific study is selectively highlighted here.',
        ),
        QuestOption(
          label: 'Emotional Manipulation',
          isCorrect: false,
          explanation:
              'The pressure is rhetorical absolutism, not emotional appeal.',
        ),
        QuestOption(
          label: 'Us-vs-Them Framing',
          isCorrect: false,
          explanation:
              'There is no in-group/out-group identity, just loaded wording.',
        ),
      ],
      explanation:
          '"Every single" and "Anyone who says otherwise is lying" use '
          'absolute language to eliminate nuance and brand disagreement as '
          'dishonesty.',
    ),
    Quest(
      id: 'q3',
      postText:
          'Real Americans protect their families. Don\'t let globalist elites '
          'take your rights — join 5 million patriots who\'ve signed our '
          'petition.',
      technique: 'Us-vs-Them Framing',
      topic: 'Politics',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'Bandwagon',
          isCorrect: false,
          explanation:
              '"5 million patriots" hints at bandwagon, but the core trick is '
              'the in-group/out-group divide.',
        ),
        QuestOption(
          label: 'Us-vs-Them Framing',
          isCorrect: true,
          explanation:
              'Correct — "Real Americans" vs "globalist elites" splits people.',
        ),
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: false,
          explanation:
              'There is some fear, but the dominant device is group identity.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation: 'No authority figure is invoked here.',
        ),
      ],
      explanation:
          '"Real Americans" vs "globalist elites" creates an artificial '
          'in-group/out-group divide, implying those who disagree aren\'t '
          '"real."',
    ),
    Quest(
      id: 'q4',
      postText:
          'New study by Harvard researchers proves coffee prevents cancer! '
          'Your doctor doesn\'t want you to know this simple trick.',
      technique: 'Appeal to Authority',
      topic: 'Health',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: true,
          explanation:
              'Correct — "Harvard researchers" is name-dropped with no source.',
        ),
        QuestOption(
          label: 'Sensationalism',
          isCorrect: false,
          explanation:
              'It is sensational, but the manipulation hinges on borrowed '
              'authority.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation:
              'No selective data is shown — just an unsourced claim.',
        ),
        QuestOption(
          label: 'Scapegoating',
          isCorrect: false,
          explanation: 'Nobody is being blamed for a societal problem here.',
        ),
      ],
      explanation:
          'Citing "Harvard researchers" without a source while claiming '
          'doctors are hiding information weaponizes authority to bypass '
          'skepticism.',
    ),
    Quest(
      id: 'q5',
      postText:
          'Crime is skyrocketing in cities run by liberals. Our neighborhoods '
          'were safe until they took over. Wake up before it\'s too late.',
      technique: 'Scapegoating',
      topic: 'Politics',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: false,
          explanation:
              'There is fear, but the post mainly assigns blame to one group.',
        ),
        QuestOption(
          label: 'Scapegoating',
          isCorrect: true,
          explanation:
              'Correct — one political group is blamed for all crime.',
        ),
        QuestOption(
          label: 'Sensationalism',
          isCorrect: false,
          explanation:
              'It is dramatic, but the central device is blame, not hype.',
        ),
        QuestOption(
          label: 'Loaded Language',
          isCorrect: false,
          explanation:
              'Some loaded words appear, yet scapegoating drives the message.',
        ),
      ],
      explanation:
          'Blaming all crime increases on one political group ignores complex '
          'causes and scapegoats a group for societal problems.',
    ),
    Quest(
      id: 'q6',
      postText:
          'URGENT: 5G towers are secretly destroying your immune system. '
          'Hospitals are overwhelmed but the media won\'t report it. SHARE NOW.',
      technique: 'Fear Appeal',
      topic: 'Technology',
      difficulty: QuestDifficulty.easy,
      options: [
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: true,
          explanation:
              'Correct — urgency and threat language drive the post.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation:
              'No selective data is presented — just alarm and conspiracy.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation: 'No credentialed authority is cited.',
        ),
        QuestOption(
          label: 'Bandwagon',
          isCorrect: false,
          explanation: 'There is no "everyone agrees" pressure here.',
        ),
      ],
      explanation:
          '"URGENT" and "SHARE NOW" trigger urgency to prevent reflection. '
          'The conspiracy framing ("won\'t report it") is a classic '
          'manipulation to make false claims seem suppressed.',
    ),
    Quest(
      id: 'q7',
      postText:
          '89% of economists agree: raising the minimum wage destroys small '
          'businesses. Do you want to destroy local jobs?',
      technique: 'False Dichotomy',
      topic: 'Politics/Economy',
      difficulty: QuestDifficulty.hard,
      options: [
        QuestOption(
          label: 'False Dichotomy',
          isCorrect: true,
          explanation:
              'Correct — only two extreme outcomes are offered.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation:
              'The poll is cited, but the trick is the forced binary choice.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation:
              'Economists are mentioned, but the leading question is the core.',
        ),
        QuestOption(
          label: 'Loaded Language',
          isCorrect: false,
          explanation:
              '"Destroy" is loaded, yet the binary framing dominates.',
        ),
      ],
      explanation:
          'The poll is presented as proof, then a leading question forces a '
          'binary: either oppose minimum wage increases or "destroy jobs," '
          'eliminating nuance.',
    ),
    Quest(
      id: 'q8',
      postText:
          'Celebrities are ALL pushing this weight loss drug because BIG '
          'PHARMA is paying them. I lost 40 lbs with this one weird trick they '
          'don\'t want you to know.',
      technique: 'Scapegoating',
      topic: 'Health',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'Scapegoating',
          isCorrect: true,
          explanation:
              'Correct — "Big Pharma" is blamed for hiding a "cure."',
        ),
        QuestOption(
          label: 'Bandwagon',
          isCorrect: false,
          explanation:
              '"Celebrities are ALL" hints at bandwagon, but blame is central.',
        ),
        QuestOption(
          label: 'Sensationalism',
          isCorrect: false,
          explanation:
              'It is sensational, yet scapegoating a corporation drives it.',
        ),
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: false,
          explanation: 'There is no real threat being raised here.',
        ),
      ],
      explanation:
          'Blaming "Big Pharma" for hiding a simple cure scapegoats '
          'corporations while promoting an unverified alternative.',
    ),
    Quest(
      id: 'q9',
      postText:
          'Young people today are LAZY and ENTITLED. In my day we worked hard '
          'and didn\'t expect handouts. This generation will destroy our '
          'country.',
      technique: 'Loaded Language',
      topic: 'Society',
      difficulty: QuestDifficulty.easy,
      options: [
        QuestOption(
          label: 'Loaded Language',
          isCorrect: true,
          explanation:
              'Correct — charged words provoke anger rather than describe.',
        ),
        QuestOption(
          label: 'Us-vs-Them Framing',
          isCorrect: false,
          explanation:
              'There is a generational contrast, but the trick is the wording.',
        ),
        QuestOption(
          label: 'Emotional Manipulation',
          isCorrect: false,
          explanation:
              'It stirs emotion via loaded words, not a personal appeal.',
        ),
        QuestOption(
          label: 'Bandwagon',
          isCorrect: false,
          explanation: 'No "everyone agrees" pressure appears here.',
        ),
      ],
      explanation:
          '"LAZY," "ENTITLED," and "destroy our country" are emotionally '
          'charged words chosen to provoke anger rather than describe reality '
          'accurately.',
    ),
    Quest(
      id: 'q10',
      postText:
          'Everyone is switching to this investment platform. 2 million users '
          'can\'t be wrong. Don\'t miss your chance to get rich — limited '
          'spots!',
      technique: 'Bandwagon',
      topic: 'Finance',
      difficulty: QuestDifficulty.easy,
      options: [
        QuestOption(
          label: 'Bandwagon',
          isCorrect: true,
          explanation:
              'Correct — "everyone is switching" is pure social proof pressure.',
        ),
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: false,
          explanation:
              '"Limited spots" adds FOMO, but the core is social proof.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation: 'No expert or authority is cited.',
        ),
        QuestOption(
          label: 'Sensationalism',
          isCorrect: false,
          explanation:
              'It is hyped, yet the manipulation rests on crowd pressure.',
        ),
      ],
      explanation:
          '"Everyone is switching" and "2 million users can\'t be wrong" use '
          'social proof pressure to make you fear missing out rather than '
          'evaluating the offer critically.',
    ),
    Quest(
      id: 'q11',
      postText:
          'Immigration is the real reason wages have stagnated for 30 years. '
          'Economists who deny this are paid by open-borders donors.',
      technique: 'Scapegoating',
      topic: 'Politics',
      difficulty: QuestDifficulty.hard,
      options: [
        QuestOption(
          label: 'Scapegoating',
          isCorrect: true,
          explanation:
              'Correct — one group is blamed for a complex economic trend.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation:
              'No selective data is shown — the post assigns blame instead.',
        ),
        QuestOption(
          label: 'Ad Hominem',
          isCorrect: false,
          explanation:
              'Experts are attacked, but the leading device is scapegoating.',
        ),
        QuestOption(
          label: 'Us-vs-Them Framing',
          isCorrect: false,
          explanation:
              'There is some grouping, yet blame-shifting is the core.',
        ),
      ],
      explanation:
          'Complex economic trends are blamed on one group, and experts who '
          'disagree are discredited by implying financial corruption rather '
          'than addressing their arguments.',
    ),
    Quest(
      id: 'q12',
      postText:
          'Climate change is either a hoax OR civilization will end in 10 '
          'years. There\'s no middle ground — pick a side.',
      technique: 'False Dichotomy',
      topic: 'Environment',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'False Dichotomy',
          isCorrect: true,
          explanation:
              'Correct — only two extreme options are presented.',
        ),
        QuestOption(
          label: 'Sensationalism',
          isCorrect: false,
          explanation:
              'The extremes are dramatic, but the trick is the false binary.',
        ),
        QuestOption(
          label: 'Emotional Manipulation',
          isCorrect: false,
          explanation:
              'It is not a personal emotional appeal — it is a forced choice.',
        ),
        QuestOption(
          label: 'Loaded Language',
          isCorrect: false,
          explanation:
              'Some loaded words appear, yet the binary framing dominates.',
        ),
      ],
      explanation:
          'Presenting only two extreme options ignores the wide spectrum of '
          'scientific consensus and policy positions between "hoax" and '
          '"civilizational collapse."',
    ),
    Quest(
      id: 'q13',
      postText:
          'LEAKED: Government documents PROVE they\'ve been secretly adding '
          'chemicals to drinking water to control the population. Full report '
          'below.',
      technique: 'Sensationalism',
      topic: 'Politics',
      difficulty: QuestDifficulty.easy,
      options: [
        QuestOption(
          label: 'Sensationalism',
          isCorrect: true,
          explanation:
              'Correct — "LEAKED" and "PROVE" are dramatic clickbait words.',
        ),
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: false,
          explanation:
              'There is fear, but the dominant device is dramatic hype.',
        ),
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: false,
          explanation: 'No selective data is actually presented.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation:
              '"Government documents" is vague — there is no real authority.',
        ),
      ],
      explanation:
          '"LEAKED" and "PROVE" are dramatic clickbait words designed to make '
          'an unverified conspiracy claim feel like explosive journalism.',
    ),
    Quest(
      id: 'q14',
      postText:
          'A small study of 50 people found that Supplement X reduced fatigue '
          'symptoms by 12%. This means Supplement X is scientifically proven '
          'to cure chronic fatigue syndrome.',
      technique: 'Cherry Picking',
      topic: 'Health',
      difficulty: QuestDifficulty.hard,
      options: [
        QuestOption(
          label: 'Cherry Picking',
          isCorrect: true,
          explanation:
              'Correct — one tiny, limited study is sold as definitive proof.',
        ),
        QuestOption(
          label: 'Appeal to Authority',
          isCorrect: false,
          explanation:
              'No authority is cited — the trick is over-claiming from data.',
        ),
        QuestOption(
          label: 'Sensationalism',
          isCorrect: false,
          explanation:
              'It overstates results, but the device is selective evidence.',
        ),
        QuestOption(
          label: 'Emotional Manipulation',
          isCorrect: false,
          explanation: 'There is no emotional appeal here — just bad inference.',
        ),
      ],
      explanation:
          'One small, limited study is presented as definitive proof. Cherry '
          'picking ignores that 50 participants is too small to establish '
          'clinical effectiveness, and "reduce fatigue" does not equal "cure '
          'a syndrome."',
    ),
    Quest(
      id: 'q15',
      postText:
          'Your children are being exposed to dangerous ideology in schools '
          'RIGHT NOW. Every day you wait is a day their innocence is stolen. '
          'ACT NOW.',
      technique: 'Emotional Manipulation',
      topic: 'Education',
      difficulty: QuestDifficulty.medium,
      options: [
        QuestOption(
          label: 'Emotional Manipulation',
          isCorrect: true,
          explanation:
              'Correct — parental love and fear are deliberately weaponised.',
        ),
        QuestOption(
          label: 'Fear Appeal',
          isCorrect: false,
          explanation:
              'It is close — but the post targets protective emotion directly.',
        ),
        QuestOption(
          label: 'Us-vs-Them Framing',
          isCorrect: false,
          explanation: 'No clear in-group/out-group identity is drawn here.',
        ),
        QuestOption(
          label: 'Loaded Language',
          isCorrect: false,
          explanation:
              'Loaded words appear, yet the emotional pull is the core device.',
        ),
      ],
      explanation:
          'This weaponizes parental love and fear. "Innocence is stolen" and '
          '"ACT NOW" are designed to trigger protective emotions and prevent '
          'rational evaluation of the actual claim.',
    ),
  ];

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Resume from where the user left off (clamped so it never overflows).
    final saved = ProfileService.data.value.quests;
    _currentQuestIndex = saved.clamp(0, _quests.length - 1);
    _feedbackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _xpPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _pathPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _revealAnim = CurvedAnimation(
      parent: _feedbackCtrl,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    _progressCtrl.dispose();
    _pathPulseCtrl.dispose();
    _xpPulseCtrl.dispose();
    super.dispose();
  }

  Quest get _quest => _quests[_currentQuestIndex];

  // ── Actions ─────────────────────────────────────────────────────────────────
  void _startQuests() {
    HapticFeedback.lightImpact();
    setState(() => _started = true);
  }

  Future<void> _selectOption(int index) async {
    if (_answered) return; // already locked in
    final option = _quest.options[index];
    final isCorrect = option.isCorrect;

    setState(() {
      _selectedOptionIndex = index;
      _answered = true;
      _correct = isCorrect;
      _questsCompleted++;
      if (isCorrect) {
        _totalXp += _quest.xpReward;
        _streak++;
        _correctCount++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });

    if (isCorrect) {
      _xpPulseCtrl.forward(from: 0);
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    _feedbackCtrl.forward(from: 0);
    _progressCtrl.forward(from: 0);

    // Persist progress and XP.
    await ProfileService.incrementQuests();
    if (isCorrect) await ProfileService.addXp(_quest.xpReward);
  }

  /// Leaves the active quest. Progress is already persisted per answer via
  /// ProfileService, so no confirmation is needed; we just resume from there.
  void _quitToPath() {
    HapticFeedback.lightImpact();
    final saved = ProfileService.data.value.quests;
    setState(() {
      _started = false;
      _currentQuestIndex = saved.clamp(0, _quests.length - 1);
      _selectedOptionIndex = -1;
      _answered = false;
      _correct = false;
    });
    _feedbackCtrl.reset();
  }

  void _nextQuest() {
    HapticFeedback.lightImpact();
    if (_currentQuestIndex >= _quests.length - 1) {
      _finishRun();
      return;
    }
    setState(() {
      _currentQuestIndex++;
      _selectedOptionIndex = -1;
      _answered = false;
      _correct = false;
    });
    _feedbackCtrl.reset();
  }

  void _finishRun() {
    // Determine which quest badges became newly reachable this run.
    final data = ProfileService.data.value;
    _newlyEarnedBadges.clear();
    for (final b in kBadges) {
      if (b.quests > 0 && data.quests >= b.quests) {
        _newlyEarnedBadges.add(b);
      }
    }
    HapticFeedback.heavyImpact();
    setState(() => _finished = true);
  }

  void _restart() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentQuestIndex = 0;
      _selectedOptionIndex = -1;
      _answered = false;
      _correct = false;
      _totalXp = 0;
      _streak = 0;
      _questsCompleted = 0;
      _correctCount = 0;
      _bestStreak = 0;
      _finished = false;
      _started = true;
      _newlyEarnedBadges.clear();
    });
    _feedbackCtrl.reset();
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        child: _finished
            ? _buildCompletionScreen()
            : _started
                ? _buildQuestScreen()
                : _buildLandingScreen(),
      ),
    );
  }

  // ── Landing (pre-quest) screen — Duolingo-style winding path ────────────────
  Widget _buildLandingScreen() {
    return SizedBox.expand(
      key: const ValueKey('landing'),
      child: Column(
        children: [
          _buildQuestHeader(),
          Expanded(child: _buildQuestPath()),
        ],
      ),
    );
  }

  Widget _buildQuestHeader() {
    return ValueListenableBuilder<ProfileData>(
      valueListenable: ProfileService.data,
      builder: (context, data, _) {
        final actions = data.quests;
        return AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: SafeArea(
                bottom: false,
                child: _headerExpanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Image.asset('assets/logomain.png',
                                    height: 52, fit: BoxFit.contain),
                                const Spacer(),
                                const ProfileIcon(),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const IconBadge(
                                icon: Icons.explore_rounded,
                                color: Colors.white,
                                size: 64),
                            const SizedBox(height: 4),
                            const Text(
                              'Learning Quests',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Build your misinformation radar',
                              style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceEvenly,
                              children: [
                                _headerStat(Icons.task_alt_rounded, '$actions', 'Answered'),
                                Container(
                                    width: 1,
                                    height: 32,
                                    color: Colors.white24),
                                _headerStat(Icons.bolt_rounded, '${data.xp}', 'XP'),
                                Container(
                                    width: 1,
                                    height: 32,
                                    color: Colors.white24),
                                _headerStat(
                                    Icons.flag_rounded,
                                    '${(_quests.length - data.quests).clamp(0, _quests.length)}',
                                    'Remaining'),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(100),
                              child: LinearProgressIndicator(
                                value: _quests.isEmpty
                                    ? 0
                                    : data.quests / _quests.length,
                                minHeight: 6,
                                backgroundColor: Colors.white24,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${data.quests} / ${_quests.length} completed',
                              style: const TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            _TappableNode(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _headerExpanded = false);
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  color: Colors.white54,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _TappableNode(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _headerExpanded = true);
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 14),
                          child: Row(
                            children: [
                              Image.asset('assets/logomain.png',
                                  height: 36, fit: BoxFit.contain),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Learning Quests',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const ProfileIcon(),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white70,
                                size: 26,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
        );
      },
    );
  }

  Widget _headerStat(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconBadge(icon: icon, color: Colors.white, size: 30),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestPath() {
    return ValueListenableBuilder<ProfileData>(
      valueListenable: ProfileService.data,
      builder: (context, data, _) {
        final completedCount = data.quests.clamp(0, _quests.length);
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final positions = _computeNodePositions(w);
            const totalHeight = 56.0 + 14 * 108.0 + 28.0 + 52.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: w,
                height: totalHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _QuestPathPainter(
                          positions: positions,
                          completedCount: completedCount,
                          difficulties: _quests
                              .map((q) => q.difficulty)
                              .toList(),
                        ),
                      ),
                    ),
                    for (int i = 0; i < _quests.length; i++)
                      _buildQuestNode(
                        index: i,
                        position: positions[i],
                        isCompleted: i < completedCount,
                        isCurrent: i == completedCount,
                      ),
                    if (completedCount < _quests.length)
                      _buildStartButton(positions[completedCount]),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Offset> _computeNodePositions(double width) {
    const xFractions = [
      0.0, 0.28, 0.40, 0.28, 0.0,
      -0.28, -0.40, -0.28, 0.0, 0.28,
      0.40, 0.0, -0.28, -0.40, 0.0,
    ];
    const kSpacing = 108.0;
    const kTopPad = 56.0;
    final cx = width / 2;
    return List.generate(15, (i) {
      final y = kTopPad + i * kSpacing;
      final x = cx + xFractions[i] * cx;
      return Offset(x, y);
    });
  }

  Widget _buildQuestNode({
    required int index,
    required Offset position,
    required bool isCompleted,
    required bool isCurrent,
  }) {
    const kNodeR = 28.0;
    const kNodeD = kNodeR * 2;
    final topic = _quests[index].topic;

    final Color nodeBg;
    final Color nodeBorder;
    final Color shadowColor;
    final Widget nodeInner;

    if (isCompleted) {
      nodeBg = const Color(0xFF16A34A);
      nodeBorder = const Color(0xFF15803D);
      shadowColor = const Color(0xFF16A34A);
      nodeInner = const Icon(Icons.check_rounded, color: Colors.white, size: 26);
    } else if (isCurrent) {
      nodeBg = const Color(0xFF22C55E);
      nodeBorder = const Color(0xFF16A34A);
      shadowColor = const Color(0xFF22C55E);
      nodeInner = Icon(_topicIcon(topic), color: Colors.white, size: 26);
    } else {
      nodeBg = context.line;
      nodeBorder = context._isDark ? AppColors.slate700 : const Color(0xFFCBD5E1);
      shadowColor = const Color(0xFFCBD5E1);
      nodeInner = const Icon(Icons.lock_rounded,
          color: Color(0xFF94A3B8), size: 18);
    }

    final circle = Container(
      width: kNodeD,
      height: kNodeD,
      decoration: BoxDecoration(
        color: nodeBg,
        shape: BoxShape.circle,
        border: Border.all(color: nodeBorder, width: 3),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(
                alpha: (isCompleted || isCurrent) ? 0.40 : 0.12),
            blurRadius: (isCompleted || isCurrent) ? 12 : 4,
            spreadRadius: (isCompleted || isCurrent) ? 2 : 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(child: nodeInner),
    );

    if (isCurrent) {
      return Positioned(
        left: position.dx - 48,
        top: position.dy - kNodeR,
        width: 96,
        child: _TappableNode(
          onTap: _startQuests,
          child: AnimatedBuilder(
            animation: _pathPulseCtrl,
            builder: (context, child) {
              final p = _pathPulseCtrl.value;
              final ringSize = kNodeD + 16 + p * 16;
              return SizedBox(
                width: 96,
                height: kNodeD,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF22C55E)
                            .withValues(alpha: 0.22 - p * 0.15),
                      ),
                    ),
                    child!,
                  ],
                ),
              );
            },
            child: circle,
          ),
        ),
      );
    }

    if (isCompleted) {
      return Positioned(
        left: position.dx - 40,
        top: position.dy - kNodeR,
        width: 80,
        child: _TappableNode(
          onTap: () => HapticFeedback.lightImpact(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: circle),
              const SizedBox(height: 4),
              Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Locked node — no tap interaction
    return Positioned(
      left: position.dx - 40,
      top: position.dy - kNodeR,
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: circle),
          const SizedBox(height: 4),
          Text(
            '${index + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(Offset position) {
    const kNodeR = 28.0;
    return Positioned(
      left: position.dx - 44,
      top: position.dy + kNodeR + 8,
      width: 88,
      child: Center(
        child: GlassButton(
          label: 'START',
          accent: const Color(0xFF16A34A),
          height: 34,
          radius: 100,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          haptic: GlassHaptic.none, // _startQuests fires its own haptic
          onTap: _startQuests,
        ),
      ),
    );
  }

  // ── Active quest screen ─────────────────────────────────────────────────────
  Widget _buildQuestScreen() {
    final quest = _quest;
    final progress = (_currentQuestIndex + (_answered ? 1 : 0)) / _quests.length;

    return SafeArea(
      key: const ValueKey('quest'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(showXp: true, onBack: _quitToPath),
          const SizedBox(height: 18),
          _progressRow(progress),
          const SizedBox(height: 20),
          // Quest card swaps with an animated transition between quests.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _questCard(quest, key: ValueKey(quest.id)),
          ),
          const SizedBox(height: 16),
          // Option buttons.
          ...List.generate(quest.options.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionButton(
                key: ValueKey('${quest.id}_opt_$i'),
                option: quest.options[i],
                index: i,
                selectedIndex: _selectedOptionIndex,
                answered: _answered,
                xp: quest.xpReward,
                onTap: () => _selectOption(i),
              ),
            );
          }),
          // Reveal panel.
          SizeTransition(
            sizeFactor: _revealAnim,
            alignment: Alignment.topCenter,
            child: _answered ? _revealPanel(quest) : const SizedBox.shrink(),
          ),
          if (_answered) ...[
            const SizedBox(height: 16),
            _primaryButton(
              label: _currentQuestIndex >= _quests.length - 1
                  ? 'Complete!'
                  : 'Next Quest →',
              onTap: _nextQuest,
            ),
          ],
        ],
        ),
      ),
    );
  }

  // ── Completion screen ───────────────────────────────────────────────────────
  Widget _buildCompletionScreen() {
    return Stack(
      key: const ValueKey('done'),
      children: [
    SafeArea(
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(showXp: true),
          const SizedBox(height: 36),
          const Center(
              child: IconBadge(
                  icon: Icons.emoji_events_rounded,
                  color: AppColors.amber,
                  size: 96)),
          const SizedBox(height: 14),
          Text(
            'Quest Complete!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: context.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You answered $_questsCompleted of ${_quests.length} quests',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _kSecondary,
            ),
          ),
          const SizedBox(height: 28),
          _card(
            child: Row(
              children: [
                Expanded(
                  child: _statTile(
                    icon: Icons.bolt_rounded,
                    color: AppColors.amber,
                    value: '$_totalXp',
                    label: 'Total XP',
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: const Color(0xFFE2E8F0),
                ),
                Expanded(
                  child: _statTile(
                    icon: Icons.local_fire_department_rounded,
                    color: const Color(0xFFEA580C),
                    value: '$_bestStreak',
                    label: 'Best Streak',
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: const Color(0xFFE2E8F0),
                ),
                Expanded(
                  child: _statTile(
                    icon: Icons.check_circle_rounded,
                    color: AppColors.green,
                    value: '$_correctCount/$_questsCompleted',
                    label: 'Correct',
                  ),
                ),
              ],
            ),
          ),
          if (_newlyEarnedBadges.isNotEmpty) ...[
            const SizedBox(height: 16),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.emoji_events_rounded,
                        color: AppColors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Badges Unlocked',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.ink,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  for (int i = 0; i < _newlyEarnedBadges.length; i++)
                    _StaggerIn(
                      delay: Duration(milliseconds: 500 + i * 160),
                      child: _badgeRow(_newlyEarnedBadges[i]),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          _primaryButton(label: 'Try Again', onTap: _restart),
          const SizedBox(height: 12),
          _secondaryButton(
            label: 'Back to Home',
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).maybePop();
            },
          ),
        ],
        ),
      ),
    ),
        const Positioned.fill(child: IgnorePointer(child: _ConfettiBurst())),
      ],
    );
  }

  // ── Reusable building blocks ────────────────────────────────────────────────
  Widget _topBar({required bool showXp, VoidCallback? onBack}) {
    return Row(
      children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              onPressed: onBack,
              tooltip: 'Back to quest path',
              icon: Icon(Icons.arrow_back_rounded, color: context.ink),
            ),
          ),
        Image.asset('assets/logomain.png',
            height: onBack != null ? 48 : 62, fit: BoxFit.contain),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Learning Quests',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.ink,
            ),
          ),
        ),
        if (showXp)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _totalXp.toDouble()),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => AnimatedBuilder(
              animation: _xpPulseCtrl,
              builder: (context, _) => Transform.scale(
                scale: 1 + 0.2 * math.sin(_xpPulseCtrl.value * math.pi),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: context.tint(AppColors.green),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: AppColors.green.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded,
                          size: 16, color: AppColors.greenDark),
                      const SizedBox(width: 3),
                      Text(
                        '${value.round()} XP',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.greenDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          const ProfileIcon(),
      ],
    );
  }

  Widget _progressRow(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quest ${_currentQuestIndex + 1} of ${_quests.length}',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _kSecondary,
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.tint(const Color(0xFFEA580C)),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_rounded,
                      size: 15, color: Color(0xFFEA580C)),
                  const SizedBox(width: 3),
                  Text(
                    '$_streak',
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: context.line,
              valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _questCard(Quest quest, {Key? key}) {
    return _card(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic + difficulty pill.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _topicColor(quest.topic).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_topicIcon(quest.topic),
                    size: 15, color: _topicColor(quest.topic)),
                const SizedBox(width: 6),
                Text(
                  '${quest.topic} · ${_difficultyLabel(quest.difficulty)}',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _topicColor(quest.topic),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Evaluate this post:',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _kSecondary,
            ),
          ),
          const SizedBox(height: 10),
          // The post text in a light-gray box with an accent left border.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: context.subtle,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              border: const Border(
                left: BorderSide(color: _kAccent, width: 4),
              ),
            ),
            child: Text(
              quest.postText,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: context.ink,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What manipulation technique is being used?',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _revealPanel(Quest quest) {
    final correct = _correct;
    final accentColor =
        correct ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
    final bg = context.tint(accentColor);
    final border = accentColor.withValues(alpha: 0.35);
    final picked = (!correct &&
            _selectedOptionIndex >= 0 &&
            _selectedOptionIndex < quest.options.length)
        ? quest.options[_selectedOptionIndex]
        : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  correct
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: accentColor,
                  size: 20),
              const SizedBox(width: 8),
              Text(
                correct ? 'Correct!' : 'Not quite...',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (picked != null) ...[
            Text(
              'Why "${picked.label}" is not it',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              picked.explanation,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: context.ink,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            quest.explanation,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: context.ink,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: context.surf,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: border),
            ),
            child: Text(
              'Technique: ${quest.technique}',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        IconBadge(icon: icon, color: color, size: 40),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: context.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.muted,
          ),
        ),
      ],
    );
  }

  Widget _badgeRow(BadgeInfo b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const IconBadge(
              icon: Icons.military_tech_rounded,
              color: AppColors.green,
              size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.title,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: context.ink,
                  ),
                ),
                Text(
                  b.desc,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: context.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, Key? key}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surf,
        borderRadius: BorderRadius.circular(_kCardRadius),
        boxShadow: const [_kCardShadow],
      ),
      child: child,
    );
  }

  // Handlers passed in already fire their own haptics.
  Widget _primaryButton({required String label, required VoidCallback onTap}) {
    return GlassButton(
      label: label,
      accent: _kAccent,
      height: 52,
      radius: _kBtnRadius,
      fontSize: 15,
      haptic: GlassHaptic.none,
      onTap: onTap,
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GlassButton(
      label: label,
      filled: false,
      accent: _kAccent,
      height: 52,
      radius: _kBtnRadius,
      fontSize: 15,
      haptic: GlassHaptic.none,
      onTap: onTap,
    );
  }

  // ── Topic / difficulty helpers ──────────────────────────────────────────────
  static String _difficultyLabel(QuestDifficulty d) => switch (d) {
        QuestDifficulty.easy => 'Easy',
        QuestDifficulty.medium => 'Medium',
        QuestDifficulty.hard => 'Hard',
      };

  static IconData _topicIcon(String topic) {
    switch (topic) {
      case 'Health':
        return Icons.health_and_safety_rounded;
      case 'Environment':
        return Icons.public_rounded;
      case 'Politics':
      case 'Politics/Economy':
        return Icons.account_balance_rounded;
      case 'Technology':
        return Icons.cell_tower_rounded;
      case 'Society':
        return Icons.groups_rounded;
      case 'Finance':
        return Icons.savings_rounded;
      case 'Education':
        return Icons.school_rounded;
      default:
        return Icons.newspaper_rounded;
    }
  }

  static Color _topicColor(String topic) {
    switch (topic) {
      case 'Health':
        return const Color(0xFF0EA5E9);
      case 'Environment':
        return const Color(0xFF16A34A);
      case 'Politics':
      case 'Politics/Economy':
        return const Color(0xFF7C3AED);
      case 'Technology':
        return const Color(0xFF0891B2);
      case 'Society':
        return const Color(0xFFEA580C);
      case 'Finance':
        return const Color(0xFFCA8A04);
      case 'Education':
        return const Color(0xFFDB2777);
      default:
        return _kSecondary;
    }
  }
}

// ── Option button with press-scale + reveal states ────────────────────────────
class _OptionButton extends StatefulWidget {
  const _OptionButton({
    super.key,
    required this.option,
    required this.index,
    required this.selectedIndex,
    required this.answered,
    required this.xp,
    required this.onTap,
  });

  final QuestOption option;
  final int index;
  final int selectedIndex;
  final bool answered;
  final int xp;
  final VoidCallback onTap;

  @override
  State<_OptionButton> createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _OptionButton old) {
    super.didUpdateWidget(old);
    if (!old.answered &&
        widget.answered &&
        widget.selectedIndex == widget.index) {
      _fx.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selectedIndex == widget.index;
    final answered = widget.answered;
    final isCorrect = widget.option.isCorrect;
    const green = Color(0xFF16A34A);
    const red = Color(0xFFEF4444);

    // Resolve colors based on the current reveal state.
    Color bg = context.surf;
    Color border = context.line;
    Color textColor = context.ink;
    Widget? trailing;

    if (!answered) {
      if (isSelected) {
        bg = context.tint(_kAccent);
        border = _kAccent;
      }
    } else {
      if (isCorrect) {
        // Always show the correct answer in green after reveal.
        bg = context.tint(green);
        border = green;
        textColor = context._isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534);
        trailing = const _StatusIcon(icon: Icons.check_rounded, color: green);
      } else if (isSelected) {
        // The user picked this and it was wrong.
        bg = context.tint(red);
        border = red;
        textColor = context._isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B);
        trailing = const _StatusIcon(icon: Icons.close_rounded, color: red);
      }
    }

    final scale = _pressed && !answered ? 0.96 : 1.0;
    final wrongPick = answered && isSelected && !isCorrect;
    final rightPick = answered && isSelected && isCorrect;

    return GestureDetector(
      onTapDown: answered ? null : (_) => setState(() => _pressed = true),
      onTapUp: answered ? null : (_) => setState(() => _pressed = false),
      onTapCancel: answered ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _fx,
        builder: (context, child) {
          final t = _fx.value;
          final dx = wrongPick && t < 1
              ? math.sin(t * math.pi * 6) * 9 * (1 - t)
              : 0.0;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.translate(offset: Offset(dx, 0), child: child),
              if (rightPick && t > 0 && t < 1)
                Positioned(
                  right: 20,
                  top: -8 - 44 * Curves.easeOut.transform(t),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0),
                      child: Text(
                        '+${widget.xp} XP',
                        style: const TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: green,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: scale),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (_, value, child) => Transform.scale(
            scale: value,
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(_kBtnRadius),
              border: Border.all(color: border, width: 1.6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.option.label,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Icon(icon, size: 15, color: Colors.white),
    );
  }
}

// ── Press-scale animation wrapper for quest nodes ─────────────────────────────
class _TappableNode extends StatefulWidget {
  const _TappableNode({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TappableNode> createState() => _TappableNodeState();
}

class _TappableNodeState extends State<_TappableNode> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ── Winding quest path painter ─────────────────────────────────────────────────
class _QuestPathPainter extends CustomPainter {
  const _QuestPathPainter({
    required this.positions,
    required this.completedCount,
    required this.difficulties,
  });

  final List<Offset> positions;
  final int completedCount;
  final List<QuestDifficulty> difficulties;

  Path _buildPath(int from, int to) {
    final path = Path();
    if (from >= to || positions.length < 2) return path;
    path.moveTo(positions[from].dx, positions[from].dy);
    for (int i = from; i < to && i + 1 < positions.length; i++) {
      final p0 = positions[i];
      final p1 = positions[i + 1];
      final midY = (p0.dy + p1.dy) / 2;
      path.cubicTo(p0.dx, midY, p1.dx, midY, p1.dx, p1.dy);
    }
    return path;
  }

  void _drawSolid(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawDashed(Canvas canvas, Path path, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const dash = 10.0;
    const gap = 7.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      bool draw = true;
      while (d < metric.length) {
        final end = (d + (draw ? dash : gap)).clamp(0.0, metric.length);
        if (draw) canvas.drawPath(metric.extractPath(d, end), paint);
        d = end;
        draw = !draw;
      }
    }
  }

  static Color _segmentColor(QuestDifficulty d) => switch (d) {
    QuestDifficulty.easy   => const Color(0xFFBBF7D0),
    QuestDifficulty.medium => const Color(0xFFFDE68A),
    QuestDifficulty.hard   => const Color(0xFFFCA5A5),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final total = positions.length - 1;
    final done = completedCount.clamp(0, total);
    if (done > 0) {
      _drawSolid(canvas, _buildPath(0, done), const Color(0xFF22C55E), 5);
    }
    // Each upcoming segment colored by that quest's difficulty
    for (int i = done; i < total; i++) {
      final color = i < difficulties.length
          ? _segmentColor(difficulties[i])
          : const Color(0xFFCBD5E1);
      _drawDashed(canvas, _buildPath(i, i + 1), color, 4);
    }
  }

  @override
  bool shouldRepaint(_QuestPathPainter old) =>
      old.completedCount != completedCount;
}


// ── Staggered scale/fade-in wrapper (badge rows) ──────────────────────────────
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.delay, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1).animate(a),
        alignment: Alignment.centerLeft,
        child: widget.child,
      ),
    );
  }
}

// ── Lightweight confetti burst (no packages) ──────────────────────────────────
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(_c.value),
          size: Size.infinite,
        ),
      );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;

  static const _colors = [
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFFEF4444),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final origin = Offset(size.width / 2, size.height * 0.26);
    final paint = Paint();
    for (int i = 0; i < 70; i++) {
      final angle = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.3;
      final speed = 180 + rnd.nextDouble() * 320;
      final spin = rnd.nextDouble() * 10;
      final sz = 5 + rnd.nextDouble() * 6;
      paint.color = _colors[i % _colors.length]
          .withValues(alpha: (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0));
      final secs = t * 2.8;
      final pos = origin +
          Offset(math.cos(angle) * speed * t * 1.1,
              math.sin(angle) * speed * t * 1.1 + 420 * secs * secs * 0.5 * 0.6);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: sz, height: sz * 0.55),
            const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
