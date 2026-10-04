import 'dart:convert';
import 'package:http/http.dart' as http;

/// A promise the model council agreed on. Not checked against sources.
class CouncilPromise {
  const CouncilPromise({
    required this.title,
    required this.status,
    required this.description,
    required this.date,
    required this.agreed,
  });
  final String title, status, description, date;
  final int agreed; // how many of the models agreed (2 or 3)
}

/// A vote the model council agreed on. Not checked against official records.
class CouncilVote {
  const CouncilVote({
    required this.billName,
    required this.billNumber,
    required this.vote,
    required this.date,
    required this.summary,
    required this.agreed,
  });
  final String billName, billNumber, vote, date, summary;
  final int agreed;
}

class CouncilResult {
  const CouncilResult({required this.promises, required this.votes});
  final List<CouncilPromise> promises;
  final List<CouncilVote> votes;
}

/// Calls the server-side model council (api/politician.js). Items come back
/// only where at least two of three models agree. Returns null on any failure,
/// so the caller simply leaves the sections as they were.
class PoliticianCouncilService {
  static const _url = 'https://credexa-tawny.vercel.app/api/politician';

  static Future<CouncilResult?> lookup(String name) async {
    try {
      final resp = await http
          .post(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final promises = (json['promises'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((p) => CouncilPromise(
                title: (p['title'] as String?) ?? '',
                status: (p['status'] as String?) ?? 'in_progress',
                description: (p['description'] as String?) ?? '',
                date: (p['date'] as String?) ?? '',
                agreed: (p['agreed'] as int?) ?? 2,
              ))
          .where((p) => p.title.isNotEmpty)
          .toList();
      final votes = (json['votes'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((v) => CouncilVote(
                billName: (v['bill_name'] as String?) ?? '',
                billNumber: (v['bill_number'] as String?) ?? '',
                vote: (v['vote'] as String?) ?? '',
                date: (v['date'] as String?) ?? '',
                summary: (v['summary'] as String?) ?? '',
                agreed: (v['agreed'] as int?) ?? 2,
              ))
          .where((v) => v.billName.isNotEmpty)
          .toList();
      return CouncilResult(promises: promises, votes: votes);
    } catch (_) {
      return null;
    }
  }
}
