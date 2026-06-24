import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'auth_service.dart';
import 'services/profile_service.dart';

// ── Colours ───────────────────────────────────────────────────────────────────
const _kBlue   = Color(0xFF1D4ED8);
const _kRed    = Color(0xFFDC2626);
const _kGold   = Color(0xFFF59E0B);
const _kGreen  = Color(0xFF22C55E);
const _kPurple = Color(0xFF7C3AED);
const _kPrimary = Color(0xFF1E293B);

TextStyle _m({
  required double size,
  FontWeight weight = FontWeight.w600,
  Color color = _kPrimary,
  double? height,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
    );

// ── Data models ───────────────────────────────────────────────────────────────
enum _PromiseStatus { completed, inProgress, unfulfilled }

class _Promise {
  final String title, description, evidence, date, category;
  final _PromiseStatus status;
  const _Promise({
    required this.title,
    required this.status,
    required this.description,
    required this.evidence,
    required this.date,
    required this.category,
  });
}

class _VoteRecord {
  final String billName, summary, vote, date, category, billNumber;
  const _VoteRecord({
    required this.billName,
    required this.summary,
    required this.vote,
    required this.date,
    required this.category,
    required this.billNumber,
  });
}

class _PoliticianData {
  final String name, party, role, state, bio;
  final Color partyColor;
  final List<_Promise> promises;
  final List<_VoteRecord> votes;
  const _PoliticianData({
    required this.name,
    required this.party,
    required this.role,
    required this.state,
    required this.bio,
    required this.partyColor,
    required this.promises,
    required this.votes,
  });
}

// ── Featured politicians ──────────────────────────────────────────────────────
class _FeaturedPolitician {
  final String name, role, party;
  final Color color;
  const _FeaturedPolitician(
      {required this.name,
      required this.role,
      required this.party,
      required this.color});
}

const _kFeatured = [
  _FeaturedPolitician(
      name: 'Donald Trump',
      role: 'President',
      party: 'Republican',
      color: _kRed),
  _FeaturedPolitician(
      name: 'Joe Biden',
      role: 'Former President',
      party: 'Democrat',
      color: _kBlue),
  _FeaturedPolitician(
      name: 'Kamala Harris',
      role: 'Vice President',
      party: 'Democrat',
      color: _kBlue),
  _FeaturedPolitician(
      name: 'Bernie Sanders',
      role: 'Senator',
      party: 'Independent',
      color: _kPurple),
  _FeaturedPolitician(
      name: 'Alexandria Ocasio-Cortez',
      role: 'Representative',
      party: 'Democrat',
      color: _kBlue),
  _FeaturedPolitician(
      name: 'Mitch McConnell',
      role: 'Senator',
      party: 'Republican',
      color: _kRed),
  _FeaturedPolitician(
      name: 'Nancy Pelosi',
      role: 'Former Speaker',
      party: 'Democrat',
      color: _kBlue),
  _FeaturedPolitician(
      name: 'Ron DeSantis',
      role: 'Governor',
      party: 'Republican',
      color: _kRed),
];

// ─────────────────────────────────────────────────────────────────────────────
//  ELECTION INTEGRITY PAGE
// ─────────────────────────────────────────────────────────────────────────────
class ElectionIntegrityPage extends StatefulWidget {
  const ElectionIntegrityPage({super.key});

  @override
  State<ElectionIntegrityPage> createState() => _ElectionIntegrityPageState();
}

class _ElectionIntegrityPageState extends State<ElectionIntegrityPage> {
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _scrolled = false;

  String? _selectedName;
  bool _loading = false;
  String? _error;
  _PoliticianData? _data;
  int _activeTab = 0; // 0 = promises, 1 = votes

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 10;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _selectPolitician(String name) async {
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedName = name;
      _loading = true;
      _error = null;
      _data = null;
      _activeTab = 0;
    });

    try {
      final data = await _fetchPoliticianData(name);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      HapticFeedback.heavyImpact();
      await ProfileService.incrementCheck();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<_PoliticianData> _fetchPoliticianData(String name) async {
    final resp = await http
        .post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $kOpenRouterApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'openai/gpt-4o-mini',
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a factual, non-partisan political information system. Respond ONLY with raw JSON — no markdown, no code fences.',
              },
              {
                'role': 'user',
                'content':
                    '''Provide factual public record information about $name. Respond with this exact JSON structure:
{
  "party": "Democrat" or "Republican" or "Independent",
  "role": "e.g. U.S. Senator for Vermont",
  "state": "e.g. Vermont",
  "bio": "One factual sentence about their career, max 130 chars",
  "promises": [
    {
      "title": "Short promise title, max 55 chars",
      "status": "completed" or "in_progress" or "unfulfilled",
      "description": "What was promised and what happened, max 110 chars",
      "evidence": "Bill name or public source, max 60 chars",
      "date": "Year promise was made, e.g. 2020",
      "category": "One of: Healthcare, Economy, Climate, Immigration, Education, Defense, Infrastructure, Criminal Justice"
    }
  ],
  "votes": [
    {
      "bill_name": "Official or common name of the legislation",
      "bill_number": "e.g. H.R. 1319 or S. 2332",
      "vote": "Yes" or "No" or "Abstain" or "Not eligible",
      "date": "e.g. March 2021",
      "category": "One of: Healthcare, Economy, Climate, Immigration, Education, Defense, Infrastructure, Criminal Justice",
      "summary": "Plain-language: what this bill does, max 95 chars"
    }
  ]
}

Include exactly 5 promises and 5 votes on major, real legislation. Only use verifiable public record information.'''
              },
            ],
            'max_tokens': 1400,
            'temperature': 0.1,
          }),
        )
        .timeout(const Duration(seconds: 28));

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw =
        (body['choices'] as List).first['message']['content'] as String;
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1) throw Exception('Invalid response from AI.');
    final json =
        jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;

    final party = (json['party'] as String?) ?? 'Independent';
    final partyColor = party == 'Democrat'
        ? _kBlue
        : party == 'Republican'
            ? _kRed
            : _kPurple;

    final promises = (json['promises'] as List? ?? []).map((p) {
      final s = (p['status'] as String?) ?? 'in_progress';
      return _Promise(
        title: (p['title'] as String?) ?? '',
        status: s == 'completed'
            ? _PromiseStatus.completed
            : s == 'unfulfilled'
                ? _PromiseStatus.unfulfilled
                : _PromiseStatus.inProgress,
        description: (p['description'] as String?) ?? '',
        evidence: (p['evidence'] as String?) ?? '',
        date: (p['date'] as String?) ?? '',
        category: (p['category'] as String?) ?? '',
      );
    }).toList();

    final votes = (json['votes'] as List? ?? [])
        .map((v) => _VoteRecord(
              billName: (v['bill_name'] as String?) ?? '',
              billNumber: (v['bill_number'] as String?) ?? '',
              vote: (v['vote'] as String?) ?? '',
              date: (v['date'] as String?) ?? '',
              category: (v['category'] as String?) ?? '',
              summary: (v['summary'] as String?) ?? '',
            ))
        .toList();

    return _PoliticianData(
      name: name,
      party: party,
      role: (json['role'] as String?) ?? '',
      state: (json['state'] as String?) ?? '',
      bio: (json['bio'] as String?) ?? '',
      partyColor: partyColor,
      promises: promises,
      votes: votes,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 64)),
              SliverToBoxAdapter(child: _buildContent(cs, bgColor)),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildNavbar(cs, bgColor)),
        ],
      ),
    );
  }

  Widget _buildNavbar(ColorScheme cs, Color bgColor) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      height: 64,
      decoration: BoxDecoration(
        color: _scrolled ? cs.surface : bgColor,
        border: _scrolled
            ? const Border(bottom: BorderSide(color: Color(0x12000000)))
            : null,
        boxShadow: _scrolled
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ]
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

  Widget _buildContent(ColorScheme cs, Color bgColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          _EyebrowChip(label: 'CREDEXA · ELECTION INTEGRITY', color: _kBlue),
          const SizedBox(height: 10),
          Text('Track Your\nPolitician',
              style: _m(
                  size: 30,
                  weight: FontWeight.w900,
                  height: 1.1,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            'Track campaign promises, voting records, and civic accountability for any elected official.',
            style: _m(
                size: 13,
                weight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.55),
                height: 1.6),
          ),
          const SizedBox(height: 22),

          // ── Search bar ────────────────────────────────────────────────
          _SearchBar(
            ctrl: _searchCtrl,
            onSubmit: _selectPolitician,
          ),
          const SizedBox(height: 18),

          // ── Featured politicians ──────────────────────────────────────
          Text('Featured Officials',
              style: _m(
                  size: 12,
                  weight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.50))),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kFeatured.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = _kFeatured[i];
                return _FeaturedChip(
                  politician: p,
                  selected: _selectedName == p.name,
                  onTap: () => _selectPolitician(p.name),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // ── Main area ─────────────────────────────────────────────────
          if (_selectedName == null) _EmptyState(),
          if (_loading) _LoadingCard(name: _selectedName ?? ''),
          if (_error != null && !_loading) _ErrorCard(message: _error!),
          if (_data != null && !_loading)
            _PoliticianView(
              data: _data!,
              activeTab: _activeTab,
              onTabChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _activeTab = i);
              },
            ),

          const SizedBox(height: 20),
          _SdgInfoCard(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SEARCH BAR
// ─────────────────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.ctrl, required this.onSubmit});
  final TextEditingController ctrl;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 4))
        ],
      ),
      child: TextField(
        controller: ctrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) onSubmit(v.trim());
        },
        style: _m(size: 14, weight: FontWeight.w600, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Search any politician by name…',
          hintStyle: _m(
              size: 14,
              weight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.38)),
          prefixIcon: Icon(Icons.search_rounded,
              color: cs.onSurface.withValues(alpha: 0.38), size: 22),
          suffixIcon: GestureDetector(
            onTap: () {
              if (ctrl.text.trim().isNotEmpty) onSubmit(ctrl.text.trim());
            },
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: _kBlue, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          filled: true,
          fillColor: cs.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _kBlue, width: 2)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FEATURED CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _FeaturedChip extends StatelessWidget {
  const _FeaturedChip(
      {required this.politician,
      required this.selected,
      required this.onTap});
  final _FeaturedPolitician politician;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = politician.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c : cs.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? c : cs.outlineVariant),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: c.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Text(
          politician.name.split(' ').last,
          style: _m(
            size: 12,
            weight: FontWeight.w700,
            color: selected
                ? Colors.white
                : cs.onSurface.withValues(alpha: 0.70),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          const Text('🏛️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Choose a Politician',
              style: _m(
                  size: 17, weight: FontWeight.w900, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            'Tap a featured official above or search for any elected representative to view their campaign promises and voting record.',
            textAlign: TextAlign.center,
            style: _m(
                size: 13,
                weight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.50),
                height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOADING CARD
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBlue.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_kBlue),
            ),
          ),
          const SizedBox(height: 18),
          Text('Loading $name\'s record…',
              style: _m(size: 14, weight: FontWeight.w800, color: _kBlue)),
          const SizedBox(height: 6),
          Text(
            'Fetching promises · Voting history · Civic profile',
            textAlign: TextAlign.center,
            style: _m(
                size: 11,
                weight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ERROR CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kRed.withValues(alpha: 0.50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: _m(
                      size: 12,
                      weight: FontWeight.w600,
                      color: _kRed,
                      height: 1.5))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  POLITICIAN VIEW (profile + tabs + content)
// ─────────────────────────────────────────────────────────────────────────────
class _PoliticianView extends StatelessWidget {
  const _PoliticianView({
    required this.data,
    required this.activeTab,
    required this.onTabChanged,
  });
  final _PoliticianData data;
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileCard(data: data),
        const SizedBox(height: 16),
        _TabSelector(activeTab: activeTab, onTabChanged: onTabChanged),
        const SizedBox(height: 16),
        if (activeTab == 0) _PromiseTracker(data: data),
        if (activeTab == 1) _VotingRecord(data: data),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROFILE CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.data});
  final _PoliticianData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials =
        data.name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: data.partyColor.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 6))
        ],
        border: Border.all(color: data.partyColor.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      data.partyColor,
                      data.partyColor.withValues(alpha: 0.65)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: data.partyColor.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.name,
                        style: _m(
                            size: 17,
                            weight: FontWeight.w900,
                            color: cs.onSurface)),
                    const SizedBox(height: 3),
                    Text(data.role,
                        style: _m(
                            size: 12,
                            weight: FontWeight.w600,
                            color: cs.onSurface.withValues(alpha: 0.50))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _PartyBadge(
                            label: data.party, color: data.partyColor),
                        if (data.state.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded,
                                  size: 11,
                                  color:
                                      cs.onSurface.withValues(alpha: 0.35)),
                              const SizedBox(width: 3),
                              Text(data.state,
                                  style: _m(
                                      size: 11,
                                      weight: FontWeight.w600,
                                      color: cs.onSurface
                                          .withValues(alpha: 0.40))),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data.bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: data.partyColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(data.bio,
                  style: _m(
                      size: 12,
                      weight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.70),
                      height: 1.55)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PartyBadge extends StatelessWidget {
  const _PartyBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: _m(size: 10, weight: FontWeight.w800, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB SELECTOR
// ─────────────────────────────────────────────────────────────────────────────
class _TabSelector extends StatelessWidget {
  const _TabSelector(
      {required this.activeTab, required this.onTabChanged});
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          _TabItem(
            icon: '🗓',
            label: 'Promise Tracker',
            active: activeTab == 0,
            onTap: () => onTabChanged(0),
          ),
          _TabItem(
            icon: '🗳',
            label: 'Voting Record',
            active: activeTab == 1,
            onTap: () => onTabChanged(1),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});
  final String icon, label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? _kBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: _kBlue.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : [],
          ),
          child: Text(
            '$icon  $label',
            textAlign: TextAlign.center,
            style: _m(
              size: 12,
              weight: FontWeight.w800,
              color: active
                  ? Colors.white
                  : cs.onSurface.withValues(alpha: 0.50),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROMISE TRACKER
// ─────────────────────────────────────────────────────────────────────────────
class _PromiseTracker extends StatelessWidget {
  const _PromiseTracker({required this.data});
  final _PoliticianData data;

  @override
  Widget build(BuildContext context) {
    final kept =
        data.promises.where((p) => p.status == _PromiseStatus.completed).length;
    final progress =
        data.promises.where((p) => p.status == _PromiseStatus.inProgress).length;
    final broken =
        data.promises.where((p) => p.status == _PromiseStatus.unfulfilled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats row
        Row(
          children: [
            Expanded(
                child: _StatPill(value: '$kept', label: 'Kept', color: _kGreen)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatPill(
                    value: '$progress', label: 'In Progress', color: _kGold)),
            const SizedBox(width: 8),
            Expanded(
                child: _StatPill(
                    value: '$broken', label: 'Broken', color: _kRed)),
          ],
        ),
        const SizedBox(height: 16),

        ...data.promises
            .map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PromiseCard(promise: p),
                )),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(
      {required this.value, required this.label, required this.color});
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text(value,
              style:
                  _m(size: 24, weight: FontWeight.w900, color: color)),
          const SizedBox(height: 3),
          Text(label,
              style: _m(
                  size: 10,
                  weight: FontWeight.w700,
                  color: color.withValues(alpha: 0.80))),
        ],
      ),
    );
  }
}

class _PromiseCard extends StatelessWidget {
  const _PromiseCard({required this.promise});
  final _Promise promise;

  (Color, String, String) get _style {
    switch (promise.status) {
      case _PromiseStatus.completed:
        return (_kGreen, 'KEPT', '✅');
      case _PromiseStatus.inProgress:
        return (_kGold, 'IN PROGRESS', '🔄');
      case _PromiseStatus.unfulfilled:
        return (_kRed, 'BROKEN', '❌');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (statusColor, statusLabel, statusIcon) = _style;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: statusColor.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(promise.title,
                    style: _m(
                        size: 13,
                        weight: FontWeight.w800,
                        color: cs.onSurface)),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(statusIcon,
                        style: const TextStyle(fontSize: 10)),
                    const SizedBox(width: 4),
                    Text(statusLabel,
                        style: _m(
                            size: 9,
                            weight: FontWeight.w800,
                            color: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(promise.description,
              style: _m(
                  size: 12,
                  weight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.62),
                  height: 1.55)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (promise.category.isNotEmpty)
                _CategoryChip(label: promise.category),
              const Spacer(),
              if (promise.date.isNotEmpty)
                Text(promise.date,
                    style: _m(
                        size: 10,
                        weight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.35))),
            ],
          ),
          if (promise.evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.link_rounded,
                    size: 13, color: _kBlue.withValues(alpha: 0.75)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(promise.evidence,
                      style: _m(
                          size: 11,
                          weight: FontWeight.w600,
                          color: _kBlue.withValues(alpha: 0.80)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  VOTING RECORD
// ─────────────────────────────────────────────────────────────────────────────
class _VotingRecord extends StatelessWidget {
  const _VotingRecord({required this.data});
  final _PoliticianData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: data.votes
          .map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VoteCard(record: v),
              ))
          .toList(),
    );
  }
}

class _VoteCard extends StatelessWidget {
  const _VoteCard({required this.record});
  final _VoteRecord record;

  (Color, String, String) _voteStyle(String vote) {
    switch (vote.toLowerCase()) {
      case 'yes':
        return (_kGreen, 'YES', '✅');
      case 'no':
        return (_kRed, 'NO', '❌');
      case 'abstain':
        return (_kGold, 'ABSTAIN', '🟡');
      default:
        return (const Color(0xFF64748B), 'N/A', '—');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (voteColor, voteLabel, voteIcon) = _voteStyle(record.vote);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.billName,
                        style: _m(
                            size: 13,
                            weight: FontWeight.w800,
                            color: cs.onSurface)),
                    if (record.billNumber.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(record.billNumber,
                          style: _m(
                              size: 10,
                              weight: FontWeight.w700,
                              color: _kBlue.withValues(alpha: 0.80))),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Vote badge
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: voteColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: voteColor.withValues(alpha: 0.28)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(voteIcon,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 2),
                    Text(voteLabel,
                        style: _m(
                            size: 8,
                            weight: FontWeight.w900,
                            color: voteColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(record.summary,
              style: _m(
                  size: 12,
                  weight: FontWeight.w500,
                  color: cs.onSurface.withValues(alpha: 0.62),
                  height: 1.55)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (record.category.isNotEmpty)
                _CategoryChip(label: record.category),
              const Spacer(),
              if (record.date.isNotEmpty)
                Text(record.date,
                    style: _m(
                        size: 10,
                        weight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.35))),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cs.outlineVariant.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_outline_rounded,
              size: 10, color: cs.onSurface.withValues(alpha: 0.40)),
          const SizedBox(width: 4),
          Text(label,
              style: _m(
                  size: 10,
                  weight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.45))),
        ],
      ),
    );
  }
}

class _EyebrowChip extends StatelessWidget {
  const _EyebrowChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style:
              _m(size: 10, weight: FontWeight.w800, color: color, spacing: 1.1)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SDG INFO CARD
// ─────────────────────────────────────────────────────────────────────────────
class _SdgInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF1E40AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _kBlue.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
                child: Text('🕊️', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SDG 16 · Peace, Justice & Strong Institutions',
                    style: _m(
                        size: 12,
                        weight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'Credexa promotes civic accountability aligned with the UN\'s goal for transparent, effective government.',
                  style: _m(
                      size: 11,
                      weight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.75),
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
