# Credexa Build Summary
**Date:** May 21, 2026  
**Build:** v1.1.0 — Launch Readiness Sprint  
**Team:** 4-agent parallel team (Frontend, API Designer, Backend Dev, QA Tester)

---

## What Was Built

### 1. Learning Quests (Gamified Critical Thinking)
A new full-screen feature (`lib/learning_quests_page.dart`, `lib/models/quest.dart`) that teaches
users to spot manipulation techniques in social-media posts. It ships with a hand-authored bank of
15 quests covering 10 manipulation techniques (Fear Appeal, Loaded Language, False Dichotomy, Cherry
Picking, Bandwagon, Appeal to Authority, Emotional Manipulation, Scapegoating, Us-vs-Them Framing,
Sensationalism) across topics such as Health, Politics, Environment, Technology, and Finance.

Flow: a landing screen ("How it works" + feature pills + **Start Quests →** button) → an active
quest screen (post card, 4 options, animated reveal panel with explanation, XP bar, streak counter)
→ a completion screen (total XP, best streak, quests done, unlocked badges, Try Again / Back to
Home). Each correct answer awards XP by difficulty (easy 10, medium 25, hard 50) and persists a
quest completion via `ProfileService.incrementQuests()`. Haptic feedback is wired throughout.
A separate `lib/services/quest_service.dart` (API Designer) provides an OpenRouter-backed generator
for future AI-generated quests; it is not yet wired into the page (the 15 quests are preset).

### 2. Home Page Hero Animation
`HomeDashboardPage` now runs a staggered slide-up + fade entrance (`_entranceCtrl`, 1200ms) for the
hero, streak, features, mission, and stat sections via `_staggered()` with `Interval` curves. A new
continuous `_PulseRing` custom-painter draws two expanding concentric rings behind the home logo
(`_pulseCtrl`, 2500ms repeat).

### 3. News Card Enhancement
`_NewsArticleCard` was upgraded with a category-color accent system (`_categoryColors` map driving
the left border and source pill), a 200px article image with `errorBuilder` fallback, an age-rating
pill, a conditional "Read more →" affordance, and relative-time formatting that falls back to
`DateFormat('MMM d')` from `package:intl` for older articles.

### 4. Visual Analyzer Polish
`visual_analyzer_page.dart` received UI polish including a dedicated `_ErrorCard` widget that shows
a context-aware title (Authorization Error vs Connection Problem) and a **Try Again →** retry
button wired to `onRetry: _pickFile`. (File finalized — not modified by QA.)

### 5. De-Bias Model Upgrade
`debias_service.dart` was upgraded from `gpt-4o-mini` to the primary model `openai/gpt-4o`, with a
new fallback model `anthropic/claude-3-5-haiku` (`_kFallbackModel`). The `_call()` helper now tries
the primary model and, on any failure, retries once with the fallback before surfacing the original
error. System prompts were strengthened with severity ratings, manipulation-tactic tagging, and
readability scoring.

### 6. Analysis Service Hardening
`analysis_service.dart` added a `_postWithRetry()` helper with a single automatic retry (3-second
delay) on `TimeoutException` or `SocketException`. Both `analyze()` and `analyzeImage()` now route
through it with a 90-second timeout (up from 65s).

### 7. Profile Service — Quest Integration
`profile_service.dart` gained a `quests` field on both `ProfileData` and `BadgeInfo`, persisted to
SharedPreferences and exposed via `incrementQuests()`. Two new badges were added: **🧭 Quest
Starter** (1 quest) and **⚔️ Quest Master** (10 quests). `BadgeInfo.isEarned` was extended to a
4-argument signature `isEarned(int c, int d, int p, [int q = 0])` so quest progress counts toward
badge unlocks.

---

## Key Decisions

| Decision | Rationale |
|---|---|
| 15 hand-authored quests instead of live AI generation | Guarantees correct, vetted educational content offline; `QuestService` remains available for a future AI mode without blocking launch. |
| `BadgeInfo.isEarned` 4th arg `q` is optional with default `0` | Keeps all existing 3-arg callsites source-compatible while enabling quest-aware badge logic. |
| Quests added as a top-level nav tab (not under "More") | Gamification is a primary engagement loop and deserves first-class visibility. |
| Single retry with fallback model / fallback network attempt | Improves reliability against transient failures without unbounded retry loops or long user waits. |
| 90s analysis timeout | Vision + multi-model backend calls can legitimately run long; 65s was causing premature timeouts. |
| QA threaded `quests` through `profile_page.dart` badge grid | Without it, the two new quest badges could never display as earned on the profile screen. |

---

## QA Test Results

| Test | Status | Notes |
|---|---|---|
| All imports resolve to real files | ✅ PASS | Every import in changed files maps to an existing file under `lib/`. |
| No undefined variable/method references | ✅ PASS | `ProfileService.incrementQuests()`, `kBadges`, `ProfileService.data` all exist and are used correctly. |
| `BadgeInfo.isEarned` 4-arg signature + all callsites | ⚠️ FAIL → FIXED | Signature accepts 4 args (`[int q = 0]`). `auth_service.dart` and `profile_service.dart` pass 4. `profile_page.dart` passed only 3 (compiled via default, but quest badges would never unlock) — QA fixed to pass 4. |
| `ProfileData` has `quests` field; all constructors handle it | ✅ PASS | `quests` defaults to 0 in the constructor, `copyWith`, and `load()`; all `ProfileData(...)` sites are safe. |
| `LearningQuestsPage` exported and imported in `main.dart` | ✅ PASS | Public class in `learning_quests_page.dart`; imported and used in `main.dart`. |
| `NavigationTab` enum includes `quests`; all switches handle it | ✅ PASS | `label`, `icon`, `_tabColor`, and `_buildPage` switches all cover `NavigationTab.quests`. |
| `_buildPage` returns `LearningQuestsPage` for quests tab | ✅ PASS | Returns `const LearningQuestsPage(key: ValueKey(NavigationTab.quests))`. |
| `Quest`, `QuestOption`, `QuestDifficulty` exported from models | ✅ PASS | All three are top-level public declarations in `models/quest.dart`. |
| `ProfileService.incrementQuests()` called in quests page | ✅ PASS | Awaited inside `_selectOption()` after each answer. |
| `_kFallbackModel` referenced in `debias_service.dart` | ✅ PASS | Used by `_request(_kFallbackModel, ...)` inside the `_call()` retry branch. |
| `_postWithRetry` called from `analyze()` and `analyzeImage()` | ✅ PASS | Both methods route through it. |
| `DateFormat` has an intl import in `main.dart` | ✅ PASS | `import 'package:intl/intl.dart'` present; `DateFormat('MMM d')` used. |
| `HapticFeedback` import in `learning_quests_page.dart` | ✅ PASS | `import 'package:flutter/services.dart'` present. |
| No duplicate class/function names within a file | ✅ PASS | No collisions found in any changed file. |
| LearningQuestsPage compiles | ✅ PASS | `flutter analyze` reports 0 errors / 0 warnings for the file. |
| Quests tab appears in navigation | ✅ PASS | `_BottomNavBar` builds from `NavigationTab.values`, which includes `quests`. |
| Quests landing screen has a "Start Quests →" button | ✅ PASS | `_primaryButton(label: 'Start Quests →', onTap: _startQuests)`. |
| All 15 quests have exactly 4 options + one `isCorrect: true` | ✅ PASS | Every quest q1–q15 has 4 `QuestOption`s with exactly one `isCorrect: true`. |
| XP rewards match easy=10 / medium=25 / hard=50 | ✅ PASS | `Quest.xpReward` switch returns 10 / 25 / 50. |
| Completion screen exists and shows total XP | ✅ PASS | `_buildCompletionScreen()` renders a `⚡ Total XP` stat tile bound to `_totalXp`. |
| Visual analyzer error card has a retry button | ✅ PASS | `_ErrorCard` renders a "Try Again →" button wired to `onRetry`. |
| De-bias model is `openai/gpt-4o` (not `-mini`) | ✅ PASS | `_kModel = 'openai/gpt-4o'`. |
| Analysis service timeout is 90s (not 65s) | ✅ PASS | Both `analyze()` and `analyzeImage()` use `Duration(seconds: 90)`. |
| Fallback model `anthropic/claude-3-5-haiku` exists | ✅ PASS | `_kFallbackModel = 'anthropic/claude-3-5-haiku'`. |
| New badges 🧭 Quest Starter & ⚔️ Quest Master exist | ✅ PASS | Both present in `kBadges` (`quests: 1` and `quests: 10`). |
| `withOpacity` vs `withValues(alpha:)` | ⚠️ NOTED | 14 pre-existing `withOpacity` calls in `main.dart` flagged by analyzer (deprecation `info` only). Pre-existing — not changed per scope. |
| Full project `flutter analyze` | ✅ PASS | 0 errors, 0 warnings; only 16 `info`-level lints (deprecations + `unnecessary_underscores`). |

---

## Issues Fixed by QA

1. **`profile_page.dart` badge grid ignored quest progress.** `_buildBadges()` and its two
   `BadgeInfo.isEarned(...)` callsites passed only 3 arguments. This compiled (the 4th `q`
   parameter defaults to `0`), but it meant the new **🧭 Quest Starter** and **⚔️ Quest Master**
   badges could never appear as earned on the Profile screen, even after completing quests.
   **Fix:** changed `_buildBadges(int checks, int debiases, int posts)` to also accept
   `int quests`, threaded `data.quests` from the `ValueListenableBuilder<ProfileData>` callsite,
   and updated both `isEarned(...)` calls inside the method to pass `quests`. Verified with
   `flutter analyze` (0 errors).

No compilation-breaking issues were found — all agents delivered code that compiles. The fix above
addresses a functional gap (quest badges not displaying) rather than a build break.

---

## Files Modified

**New files**
- `lib/models/quest.dart` (Backend Dev)
- `lib/learning_quests_page.dart` (Backend Dev)
- `lib/services/quest_service.dart` (API Designer)

**Modified files**
- `lib/main.dart` (Frontend: hero animation, pulse ring, news cards, quests nav tab)
- `lib/visual_analyzer_page.dart` (Frontend: error card / retry UI polish)
- `lib/services/debias_service.dart` (API Designer: gpt-4o upgrade, fallback model, stronger prompts)
- `lib/services/analysis_service.dart` (API Designer: retry logic, 90s timeout)
- `lib/services/profile_service.dart` (Backend Dev: `quests` field, 2 new badges, `incrementQuests`)
- `lib/auth_service.dart` (Backend Dev: 4-arg `isEarned` callsite update)
- `lib/profile_page.dart` (QA Tester: threaded `quests` into badge grid — see Issues Fixed)

---

## Known Limitations

- **Runtime behavior unverified.** All checks were performed via static reading and
  `flutter analyze` (0 errors / 0 warnings). The app was not launched on a device or emulator, so
  visual layout, animation timing, haptics, and live navigation transitions are unverified at
  runtime.
- **`QuestService` is unused.** `lib/services/quest_service.dart` is fully implemented but not yet
  called anywhere — the Learning Quests page uses the 15 preset quests. The service uses
  `gpt-4o-mini` by design for cost efficiency; AI-generated quests are a future enhancement.
- **Hardcoded API keys.** `quest_service.dart`, `debias_service.dart`, and
  `visual_analyzer_page.dart` contain hardcoded OpenRouter / Hive keys. This is pre-existing and
  out of scope for this sprint, but should be moved to secure config before a public release.
- **Pre-existing `withOpacity` deprecations.** 14 `withOpacity` calls remain in `main.dart` (plus
  others elsewhere). These are deprecation `info` lints only, do not break the build, and were left
  unchanged as instructed (pre-existing).
- **Streak semantics differ.** The Learning Quests in-run `_streak` is separate from the home-page
  "Action Streak" (`checks + debiases + posts`); quest XP is tracked per-run and not persisted to
  the profile beyond the `quests` completion counter. This is by design but worth noting.
