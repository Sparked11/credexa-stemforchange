import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
//  FEEDBACK SERVICE  —  sends survey responses to Google Sheets via Apps Script
// ─────────────────────────────────────────────────────────────────────────────
//
// One-time setup:
//   1. Open the target Google Sheet.
//   2. Extensions → Apps Script → paste the script below → Save.
//   3. Deploy → New deployment → Web app
//        Execute as: Me   |   Who has access: Anyone
//   4. Copy the web-app URL and paste it as [_kWebAppUrl] below.
//   5. Add column headers on row 1: Timestamp | Helpful | Comment | Build
//
// Apps Script code:
//   function doPost(e) {
//     try {
//       const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
//       const d     = JSON.parse(e.postData.contents);
//       sheet.appendRow([d.timestamp, d.helpful, d.comment || '', d.build]);
//       return ContentService.createTextOutput('OK');
//     } catch(err) {
//       return ContentService.createTextOutput('ERROR: ' + err);
//     }
//   }

class FeedbackService {
  // Paste your deployed Apps Script URL here:
  static const _kWebAppUrl =
      'https://script.google.com/macros/s/AKfycbxZE7NgaG5e5Vr_8N_5He32xqTkMt-wiUnxWnJaZH7k296NvVD7S0CFchstYK4AZtYH/exec';

  static const _kBuild = '1.0.0';

  /// Submits a survey response to Google Sheets.
  /// Errors are swallowed — this must never crash or block the app.
  static Future<void> submit({
    required bool helpful,
    String? comment,
  }) async {
    if (_kWebAppUrl == 'https://script.google.com/macros/s/AKfycbxZE7NgaG5e5Vr_8N_5He32xqTkMt-wiUnxWnJaZH7k296NvVD7S0CFchstYK4AZtYH/exec') return;
    try {
      await http.post(
        Uri.parse(_kWebAppUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'timestamp': DateTime.now().toIso8601String(),
          'helpful':   helpful,
          'comment':   comment?.trim() ?? '',
          'build':     _kBuild,
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Silently ignored — offline or misconfigured URL must not surface to user.
    }
  }
}
