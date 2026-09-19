import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/news_article.dart';
import 'services/article_reader_service.dart';
import 'services/connectivity_service.dart';
import 'theme/app_tokens.dart';
import 'widgets/app_widgets.dart';
import 'widgets/glass_button.dart';

/// Hostname without "www." for display, e.g. "bbc.co.uk".
String sourceDomain(NewsArticle article) {
  final host = Uri.tryParse(article.url)?.host ?? '';
  if (host.isEmpty) return article.source;
  return host.startsWith('www.') ? host.substring(4) : host;
}

Future<void> openArticleSource(NewsArticle article) async {
  HapticFeedback.lightImpact();
  final uri = Uri.tryParse(article.url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class NewsArticlePage extends StatefulWidget {
  final NewsArticle article;
  const NewsArticlePage({super.key, required this.article});

  @override
  State<NewsArticlePage> createState() => _NewsArticlePageState();
}

class _NewsArticlePageState extends State<NewsArticlePage> {
  late Future<List<ArticleBlock>?> _body;

  @override
  void initState() {
    super.initState();
    _body = ArticleReaderService.fetch(widget.article.url);
  }

  void _retry() {
    HapticFeedback.lightImpact();
    setState(() => _body = ArticleReaderService.fetch(widget.article.url));
  }

  String _fallbackText(NewsArticle a) {
    final cleaned =
        a.content.replaceAll(RegExp(r'\s*\[\+?\d+ chars\]\s*$'), '').trim();
    final withoutEllipsis =
        cleaned.endsWith('…') || cleaned.endsWith('...') ? cleaned : cleaned;
    return withoutEllipsis.length > a.description.length
        ? withoutEllipsis
        : a.description;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final domain = sourceDomain(a);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: a.imageUrl.isNotEmpty ? 260 : 0,
            backgroundColor: isDark ? AppColors.slate900 : AppColors.slate800,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
              },
            ),
            actions: [
              Builder(
                builder: (btnContext) => IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    final box = btnContext.findRenderObject() as RenderBox?;
                    final origin = box == null
                        ? const Rect.fromLTWH(0, 0, 1, 1)
                        : box.localToGlobal(Offset.zero) & box.size;
                    Share.share(
                      '${a.title}\n${a.url}',
                      sharePositionOrigin: origin,
                    );
                  },
                ),
              ),
            ],
            flexibleSpace: a.imageUrl.isNotEmpty
                ? FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          a.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Container(color: AppColors.slate800),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x66000000), Color(0x00000000)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.indigo.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            a.category.isEmpty
                                ? 'News'
                                : '${a.category[0].toUpperCase()}${a.category.substring(1)}',
                            style: const TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.indigo,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${a.ageRating}+',
                          style: const TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.greenDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    a.title,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${DateFormat('MMMM d, y · h:mm a').format(a.publishedAt.toLocal())}  ·  $domain',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SourceCard(article: a, domain: domain),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<ArticleBlock>?>(
              future: _body,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const _BodySkeleton();
                }
                final blocks = snap.data;
                if (blocks == null) {
                  return _FallbackBody(
                    text: _fallbackText(a),
                    domain: domain,
                    onRetry: _retry,
                    onOpen: () => openArticleSource(a),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in blocks)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: b.isHeading ? 8 : 16,
                              top: b.isHeading ? 8 : 0),
                          child: Text(
                            b.text,
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: b.isHeading ? 18 : 16,
                              fontWeight: b.isHeading
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                              height: b.isHeading ? 1.3 : 1.7,
                              color: cs.onSurface
                                  .withValues(alpha: b.isHeading ? 1 : 0.9),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 32 + MediaQuery.of(context).padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassButton(
                    label: 'Read original on $domain',
                    icon: Icons.open_in_new_rounded,
                    onTap: () => openArticleSource(a),
                    height: 52,
                    haptic: GlassHaptic.none,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Article text belongs to $domain. Credexa displays it for reading and always links back to the original publisher.',
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 11,
                      height: 1.5,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final NewsArticle article;
  final String domain;
  const _SourceCard({required this.article, required this.domain});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => openArticleSource(article),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const IconBadge(
                  icon: Icons.language_rounded,
                  color: AppColors.sky,
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source: $domain',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to visit the publisher and verify this story',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_outward_rounded,
                  size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BodySkeleton extends StatefulWidget {
  const _BodySkeleton();

  @override
  State<_BodySkeleton> createState() => _BodySkeletonState();
}

class _BodySkeletonState extends State<_BodySkeleton>
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
        final alpha = 0.06 + _c.value * 0.06;
        Widget line(double w) => Container(
              height: 12,
              width: w,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: base.withValues(alpha: alpha),
                borderRadius: BorderRadius.circular(6),
              ),
            );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  line(w),
                  line(w),
                  line(w),
                  line(w * 0.6),
                  const SizedBox(height: 14),
                ],
              ],
            );
          }),
        );
      },
    );
  }
}

class _FallbackBody extends StatelessWidget {
  final String text;
  final String domain;
  final VoidCallback onRetry;
  final VoidCallback onOpen;
  const _FallbackBody({
    required this.text,
    required this.domain,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 16,
                  height: 1.7,
                  color: cs.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: ConnectivityService.online,
            builder: (context, online, _) => _buildNotice(context, !online),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildNotice(BuildContext context, bool offline) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border:
                  Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                        offline
                            ? Icons.wifi_off_rounded
                            : Icons.info_outline_rounded,
                        color: AppColors.amber,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        offline
                            ? "You're offline"
                            : 'Full text unavailable here',
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  offline
                      ? '$kOfflineMessage The full article will load once you are back online.'
                      : '$domain may block in-app reading or require a subscription. You can retry or read the full article on their site.',
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try loading again'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
