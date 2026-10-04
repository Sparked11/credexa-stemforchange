import 'dart:convert';
import 'package:http/http.dart' as http;

/// One dated office a person has held, from Wikidata.
class OfficeRecord {
  const OfficeRecord({required this.title, this.start, this.end});
  final String title;
  final String? start; // yyyy-mm-dd, null if unknown
  final String? end;   // yyyy-mm-dd, null means still holding the office

  String get range => '${start ?? 'unknown start'} → ${end ?? 'present'}';
}

/// Verified identity facts for a person, taken from Wikidata rather than from
/// an AI model's memory. [found] is false when no matching entry exists.
class IdentityFacts {
  const IdentityFacts({
    this.found = false,
    this.officeTitle,
    this.officeYears,
    this.isFormer = false,
    this.partyLabel,
  });

  final bool found;
  final String? officeTitle; // latest political office
  final String? officeYears; // e.g. "2025–present" or "2021–2025"
  final bool isFormer;       // true only when every office has ended
  final String? partyLabel;  // e.g. "Democrat", "Republican", or Wikidata's label

  /// "President of the United States (2025–present)", or null if unknown.
  String? get roleLine => officeTitle == null
      ? null
      : '$officeTitle${officeYears == null ? '' : ' ($officeYears)'}';
}

/// Looks up a person's public office and party history in Wikidata.
///
/// Wikidata is a free, structured, community-maintained database with start and
/// end dates, so it is the source of truth for office, dates and party.
class OfficeholderService {
  static const _userAgent = 'CredeXa/1.0 (credexa.support@gmail.com)';

  // Offices we want to show. Excludes generic labels (e.g. a company's "president").
  static final _politicalOffice = RegExp(
    r'(president|senator|representative|governor|mayor|secretary|speaker|'
    r'attorney general|prime minister|member of|congress|parliament|'
    r'council|chancellor|minister)',
    caseSensitive: false,
  );

  /// Verified identity facts for [name]. Returns [IdentityFacts.found] = false
  /// on any failure, so callers must treat that as "unknown", never as a claim.
  static Future<IdentityFacts> identity(String name) async {
    try {
      final qid = await _entityId(name);
      if (qid == null) return const IdentityFacts();

      final offices = await _officeRecords(qid);
      final parties = await _partyRecords(qid);

      // The most recent office by start date decides. Wikidata often leaves an
      // old office without an end date, so an older open-ended record must not
      // count as current.
      final office = offices.firstOrNull;
      final currentOffice = office?.end == null ? office : null;
      final currentParty =
          parties.where((p) => p.end == null).firstOrNull ?? parties.firstOrNull;

      return IdentityFacts(
        found: true,
        officeTitle: office?.title,
        officeYears: office == null ? null : _years(office),
        isFormer: office != null && currentOffice == null,
        partyLabel: currentParty == null ? null : _partyName(currentParty.title),
      );
    } catch (_) {
      return const IdentityFacts();
    }
  }

  /// Office history for [name], newest first. Empty if unknown.
  static Future<List<OfficeRecord>> officeHistory(String name) async {
    try {
      final qid = await _entityId(name);
      if (qid == null) return [];
      return await _officeRecords(qid);
    } catch (_) {
      return [];
    }
  }

  static Future<List<OfficeRecord>> _officeRecords(String qid) async {
    final rows = await _sparql('''
SELECT ?posLabel ?start ?end WHERE {
  wd:$qid p:P39 ?st . ?st ps:P39 ?pos .
  OPTIONAL { ?st pq:P580 ?start }
  OPTIONAL { ?st pq:P582 ?end }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
ORDER BY DESC(?start)
LIMIT 60''');
    final records = <OfficeRecord>[];
    for (final r in rows) {
      final title = (r['posLabel']?['value'] as String?) ?? '';
      if (title.isEmpty) continue;
      if (!_politicalOffice.hasMatch(title)) continue;
      if (title.toLowerCase().contains('elect')) continue; // "President-elect"
      if (title.toLowerCase() == 'president') continue;
      records.add(OfficeRecord(
        title: title,
        start: _day(r['start']?['value'] as String?),
        end:   _day(r['end']?['value'] as String?),
      ));
    }
    return records;
  }

  static Future<List<OfficeRecord>> _partyRecords(String qid) async {
    final rows = await _sparql('''
SELECT ?partyLabel ?start ?end WHERE {
  wd:$qid p:P102 ?st . ?st ps:P102 ?party .
  OPTIONAL { ?st pq:P580 ?start }
  OPTIONAL { ?st pq:P582 ?end }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
ORDER BY DESC(?start)
LIMIT 20''');
    return rows
        .map((r) => OfficeRecord(
              title: (r['partyLabel']?['value'] as String?) ?? '',
              start: _day(r['start']?['value'] as String?),
              end:   _day(r['end']?['value'] as String?),
            ))
        .where((p) => p.title.isNotEmpty)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> _sparql(String query) async {
    final uri = Uri.https('query.wikidata.org', '/sparql', {
      'query': query,
      'format': 'json',
    });
    final resp = await http.get(uri, headers: {
      'User-Agent': _userAgent,
      'Accept': 'application/sparql-results+json',
    }).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return [];
    final rows = jsonDecode(resp.body)['results']['bindings'] as List;
    return rows.cast<Map<String, dynamic>>();
  }

  // Finds the Wikidata item for a person, preferring entries described as
  // politicians. Returns null when nothing matches.
  static Future<String?> _entityId(String name) async {
    final uri = Uri.https('www.wikidata.org', '/w/api.php', {
      'action':   'wbsearchentities',
      'search':   name,
      'language': 'en',
      'type':     'item',
      'limit':    '5',
      'format':   'json',
    });
    final resp = await http.get(uri, headers: {
      'User-Agent': _userAgent,
    }).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;

    final hits = (jsonDecode(resp.body)['search'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    if (hits.isEmpty) return null;
    final politician = hits.firstWhere(
      (h) => ((h['description'] as String?) ?? '')
          .toLowerCase()
          .contains('politician'),
      orElse: () => hits.first,
    );
    return politician['id'] as String?;
  }

  static String _years(OfficeRecord o) {
    final from = o.start?.substring(0, 4);
    final to   = o.end?.substring(0, 4) ?? 'present';
    return from == null ? to : '$from–$to';
  }

  static String _partyName(String label) {
    final l = label.toLowerCase();
    if (l.contains('democratic')) return 'Democrat';
    if (l.contains('republican')) return 'Republican';
    if (l.contains('independent')) return 'Independent';
    return label;
  }

  // "2025-01-20T00:00:00Z" → "2025-01-20"
  static String? _day(String? iso) =>
      (iso == null || iso.length < 10) ? null : iso.substring(0, 10);
}
