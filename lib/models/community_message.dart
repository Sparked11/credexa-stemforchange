import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { question, reply, ai }

class CommunityMessage {
  const CommunityMessage({
    required this.id,
    required this.text,
    required this.type,
    required this.timestamp,
    this.userId,
    this.imageBase64,
    this.imageMimeType,
    this.reactions = const {},
    this.userReactions = const {},
    this.links = const [],
    this.reportCount = 0,
    this.reportedBy = const [],
  });

  final String id;
  final String text;
  final MessageType type;
  final DateTime timestamp;
  final String? userId;
  final String? imageBase64;
  final String? imageMimeType;
  // emoji → total count
  final Map<String, int> reactions;
  // userId → the emoji they chose
  final Map<String, String> userReactions;
  // [{title, source, url}] for AI messages
  final List<Map<String, String>> links;
  // Moderation: number of distinct users who reported this message, and their ids.
  final int reportCount;
  final List<String> reportedBy;

  bool get isQuestion => type == MessageType.question;
  bool get hasImage   => imageBase64 != null && imageBase64!.isNotEmpty;

  Uint8List? get imageBytes {
    if (imageBase64 == null || imageBase64!.isEmpty) return null;
    try { return base64Decode(imageBase64!); } catch (_) { return null; }
  }

  String get authorLabel {
    switch (type) {
      case MessageType.question: return 'Anonymous';
      case MessageType.reply:    return 'Community Member';
      case MessageType.ai:       return 'AI Analysis';
    }
  }

  String get authorIcon {
    switch (type) {
      case MessageType.question: return '👤';
      case MessageType.reply:    return '💬';
      case MessageType.ai:       return '🔍';
    }
  }

  factory CommunityMessage.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final typeStr = d['type'] as String? ?? 'question';
    final type = () {
      switch (typeStr) {
        case 'question': return MessageType.question;
        case 'reply':    return MessageType.reply;
        case 'ai':       return MessageType.ai;
        case 'user':     return MessageType.question; // backward compat
        case 'educator': return MessageType.ai;        // backward compat
        case 'tip':      return MessageType.ai;        // backward compat
        default:         return MessageType.question;
      }
    }();
    return CommunityMessage(
      id:            doc.id,
      text:          d['text']          as String? ?? '',
      type:          type,
      timestamp:     (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId:        d['userId']        as String?,
      imageBase64:   d['imageBase64']   as String?,
      imageMimeType: d['imageMimeType'] as String?,
      reactions: {
        for (final e in (d['reactions'] as Map<String, dynamic>? ?? {}).entries)
          e.key: (e.value as num).toInt(),
      },
      userReactions: {
        for (final e in (d['userReactions'] as Map<String, dynamic>? ?? {}).entries)
          e.key: e.value as String,
      },
      links: (d['links'] as List<dynamic>? ?? []).map((item) {
        final m = item as Map<String, dynamic>;
        return {
          'title':  m['title']  as String? ?? '',
          'source': m['source'] as String? ?? '',
          'url':    m['url']    as String? ?? '',
        };
      }).where((m) => m['url']!.isNotEmpty).toList(),
      reportCount: (d['reportCount'] as num?)?.toInt() ?? 0,
      reportedBy:  (d['reportedBy'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
