import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/quest.dart';
import 'services/profile_service.dart';
import 'auth_service.dart';

// ── Design tokens (match app-wide language) ───────────────────────────────────
const _kPrimary = Color(0xFF1E293B);
const _kSecondary = Color(0xFF64748B);
const _kAccent = Color(0xFF22C55E);
const _kBackground = Color(0xFFF1F5F9);

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
      } else {
        _streak = 0;
      }
    });

    if (isCorrect) {
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
      backgroundColor: _kBackground,
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
                            const Text('🧭',
                                style: TextStyle(fontSize: 44)),
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
                                _headerStat('🔥', '$actions', 'Actions'),
                                Container(
                                    width: 1,
                                    height: 32,
                                    color: Colors.white24),
                                _headerStat('⚡', '${data.xp}', 'XP'),
                                Container(
                                    width: 1,
                                    height: 32,
                                    color: Colors.white24),
                                _headerStat(
                                    '🧭', '${data.quests}', 'Quests'),
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
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            _TappableNode(
                              onTap: () =>
                                  setState(() => _headerExpanded = false),
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
                        onTap: () =>
                            setState(() => _headerExpanded = true),
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

  Widget _headerStat(String icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 2),
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
            fontSize: 10,
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
            const totalHeight = 56.0 + 14 * 108.0 + 28.0 + 160.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
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
      nodeInner = Text(
        _topicEmoji(topic),
        style: const TextStyle(fontSize: 22),
      );
    } else {
      nodeBg = const Color(0xFFE2E8F0);
      nodeBorder = const Color(0xFFCBD5E1);
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
        child: _TappableNode(
          onTap: _startQuests,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF15803D).withValues(alpha: 0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              'START',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
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
          _topBar(showXp: true),
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
                onTap: () => _selectOption(i),
              ),
            );
          }),
          // Reveal panel.
          SizeTransition(
            sizeFactor: _revealAnim,
            axisAlignment: -1,
            child: _answered ? _revealPanel(quest) : const SizedBox.shrink(),
          ),
          if (_answered) ...[
            const SizedBox(height: 16),
            _primaryButton(
              label: _currentQuestIndex >= _quests.length - 1
                  ? 'Complete! 🎉'
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
    final correctCount = _questsCompleted;
    return SafeArea(
      key: const ValueKey('done'),
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(showXp: true),
          const SizedBox(height: 36),
          const Center(child: Text('🎉', style: TextStyle(fontSize: 76))),
          const SizedBox(height: 14),
          const Text(
            'Quest Complete!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You completed all ${_quests.length} quests',
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
                    emoji: '⚡',
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
                    emoji: '🔥',
                    value: '$_streak',
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
                    emoji: '✅',
                    value: '$correctCount',
                    label: 'Quests Done',
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
                  const Text(
                    '🏆 Badges Unlocked',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._newlyEarnedBadges.map(_badgeRow),
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
    );
  }

  // ── Reusable building blocks ────────────────────────────────────────────────
  Widget _topBar({required bool showXp}) {
    return Row(
      children: [
        Image.asset('assets/logomain.png', height: 62, fit: BoxFit.contain),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Learning Quests',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _kPrimary,
            ),
          ),
        ),
        if (showXp)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _totalXp.toDouble()),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Text(
                '⚡ ${value.round()} XP',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF16A34A),
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
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '🔥 $_streak',
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFEA580C),
                ),
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
              backgroundColor: const Color(0xFFE2E8F0),
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
            child: Text(
              '${_topicEmoji(quest.topic)} ${quest.topic} · '
              '${_difficultyLabel(quest.difficulty)}',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _topicColor(quest.topic),
              ),
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
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.all(Radius.circular(12)),
              border: Border(
                left: BorderSide(color: _kAccent, width: 4),
              ),
            ),
            child: Text(
              quest.postText,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: _kPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'What manipulation technique is being used?',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _kPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _revealPanel(Quest quest) {
    final correct = _correct;
    final bg = correct ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5);
    final border =
        correct ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA);
    final accentColor =
        correct ? const Color(0xFF16A34A) : const Color(0xFFEF4444);

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
          Text(
            correct
                ? '✅ Correct!'
                : '❌ Not quite...',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            quest.explanation,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
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
    required String emoji,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _kPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kSecondary,
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(b.emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.title,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _kPrimary,
                  ),
                ),
                Text(
                  b.desc,
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: _kSecondary,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kCardRadius),
        boxShadow: const [_kCardShadow],
      ),
      child: child,
    );
  }

  Widget _primaryButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _kAccent,
          borderRadius: BorderRadius.circular(_kBtnRadius),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kBtnRadius),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _kPrimary,
          ),
        ),
      ),
    );
  }

  // ── Topic / difficulty helpers ──────────────────────────────────────────────
  static String _difficultyLabel(QuestDifficulty d) => switch (d) {
        QuestDifficulty.easy => 'Easy',
        QuestDifficulty.medium => 'Medium',
        QuestDifficulty.hard => 'Hard',
      };

  static String _topicEmoji(String topic) {
    switch (topic) {
      case 'Health':
        return '🏥';
      case 'Environment':
        return '🌍';
      case 'Politics':
      case 'Politics/Economy':
        return '🏛️';
      case 'Technology':
        return '📡';
      case 'Society':
        return '👥';
      case 'Finance':
        return '💰';
      case 'Education':
        return '🎓';
      default:
        return '📰';
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
    required this.onTap,
  });

  final QuestOption option;
  final int index;
  final int selectedIndex;
  final bool answered;
  final VoidCallback onTap;

  @override
  State<_OptionButton> createState() => _OptionButtonState();
}

class _OptionButtonState extends State<_OptionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selectedIndex == widget.index;
    final answered = widget.answered;
    final isCorrect = widget.option.isCorrect;

    // Resolve colors based on the current reveal state.
    Color bg = Colors.white;
    Color border = const Color(0xFFE2E8F0);
    Color textColor = _kPrimary;
    Widget? trailing;

    if (!answered) {
      if (isSelected) {
        bg = const Color(0xFFF0FDF4);
        border = _kAccent;
      }
    } else {
      if (isCorrect) {
        // Always show the correct answer in green after reveal.
        bg = const Color(0xFFF0FDF4);
        border = const Color(0xFF16A34A);
        textColor = const Color(0xFF166534);
        trailing = const _StatusIcon(
          icon: Icons.check_rounded,
          color: Color(0xFF16A34A),
        );
      } else if (isSelected) {
        // The user picked this and it was wrong.
        bg = const Color(0xFFFFF5F5);
        border = const Color(0xFFEF4444);
        textColor = const Color(0xFF991B1B);
        trailing = const _StatusIcon(
          icon: Icons.close_rounded,
          color: Color(0xFFEF4444),
        );
      }
    }

    final scale = _pressed && !answered ? 0.96 : 1.0;

    return GestureDetector(
      onTapDown: answered ? null : (_) => setState(() => _pressed = true),
      onTapUp: answered ? null : (_) => setState(() => _pressed = false),
      onTapCancel: answered ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,
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
