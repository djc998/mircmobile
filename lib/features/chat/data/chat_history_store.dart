/// Saved chat history, so conversations survive disconnects and restarts.
///
/// Each conversation (room or private chat) on each network is kept as its
/// own file of JSON lines in the app's private support folder. Only chat
/// lines are saved (messages, actions, notices, your own messages); join
/// and quit noise and server messages are not.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One saved line. Kept separate from the UI's `ChatLine` so the storage
/// format doesn't change when the UI does.
class StoredLine {
  const StoredLine({
    required this.time,
    required this.kind,
    required this.text,
    this.sender,
    this.msgid,
  });

  factory StoredLine.fromJson(Map<String, Object?> json) => StoredLine(
    time: DateTime.fromMillisecondsSinceEpoch(
      json['t'] as int? ?? 0,
      isUtc: true,
    ),
    kind: json['k'] as String? ?? 'message',
    text: json['x'] as String? ?? '',
    sender: json['s'] as String?,
    msgid: json['m'] as String?,
  );

  final DateTime time;

  /// `ChatLineKind` name: message, action, notice or own.
  final String kind;
  final String text;
  final String? sender;

  /// The server's id for the message, when it gave one (IRCv3 `msgid`).
  final String? msgid;

  Map<String, Object?> toJson() => {
    't': time.toUtc().millisecondsSinceEpoch,
    'k': kind,
    'x': text,
    if (sender != null) 's': sender,
    if (msgid != null) 'm': msgid,
  };
}

abstract interface class ChatHistoryStore {
  /// The newest [limit] lines of a conversation, oldest first.
  Future<List<StoredLine>> load(
    String networkId,
    String conversation, {
    int limit = 1000,
  });

  /// Adds a line. Writes are queued, so callers don't wait.
  void append(String networkId, String conversation, StoredLine line);

  /// Deletes one conversation's history.
  Future<void> clear(String networkId, String conversation);

  /// Deletes all saved history.
  Future<void> clearAll();
}

/// Keeps history in memory only (tests, and the default before `main`
/// provides a file store).
class MemoryChatHistoryStore implements ChatHistoryStore {
  final Map<String, List<StoredLine>> conversations = {};

  static String _key(String networkId, String conversation) =>
      '${networkId.toLowerCase()}/${conversation.toLowerCase()}';

  @override
  Future<List<StoredLine>> load(
    String networkId,
    String conversation, {
    int limit = 1000,
  }) async {
    final lines = conversations[_key(networkId, conversation)] ?? const [];
    return lines.sublist(lines.length > limit ? lines.length - limit : 0);
  }

  @override
  void append(String networkId, String conversation, StoredLine line) =>
      (conversations[_key(networkId, conversation)] ??= []).add(line);

  @override
  Future<void> clear(String networkId, String conversation) async =>
      conversations.remove(_key(networkId, conversation));

  @override
  Future<void> clearAll() async => conversations.clear();
}

/// Stores each conversation as `<root>/<network>/<conversation>.jsonl`.
class FileChatHistoryStore implements ChatHistoryStore {
  FileChatHistoryStore(this.root, {this.maxLines = 2000});

  final Directory root;

  /// A file is trimmed back to half this size once it grows past it.
  final int maxLines;

  /// Pending writes per file, so appends stay in order.
  final Map<String, Future<void>> _queues = {};

  File _file(String networkId, String conversation) => File(
    '${root.path}/${Uri.encodeComponent(networkId.toLowerCase())}/'
    '${Uri.encodeComponent(conversation.toLowerCase())}.jsonl',
  );

  Future<void> _enqueue(File file, Future<void> Function() job) {
    final next = (_queues[file.path] ?? Future<void>.value())
        .then((_) => job())
        .catchError((Object _) {
          // History is best effort; a failed write must not break chat.
        });
    _queues[file.path] = next;
    return next;
  }

  @override
  Future<List<StoredLine>> load(
    String networkId,
    String conversation, {
    int limit = 1000,
  }) async {
    final file = _file(networkId, conversation);
    // Let queued writes land first.
    await (_queues[file.path] ?? Future<void>.value());
    if (!file.existsSync()) return const [];
    final List<String> raw;
    try {
      raw = await file.readAsLines();
    } on Object {
      return const [];
    }
    final lines = <StoredLine>[];
    for (final row in raw) {
      if (row.isEmpty) continue;
      try {
        lines.add(StoredLine.fromJson(jsonDecode(row) as Map<String, Object?>));
      } on Object {
        // Skip a damaged line (for example a write cut short).
      }
    }
    if (raw.length > maxLines) {
      final keep = lines.sublist(lines.length - maxLines ~/ 2);
      // Written aside and swapped in, so the file is never half-written
      // or empty if the app stops or another reader looks mid-trim.
      unawaited(
        _enqueue(file, () async {
          final temp = File('${file.path}.tmp');
          await temp.writeAsString(
            keep.map((l) => '${jsonEncode(l.toJson())}\n').join(),
            flush: true,
          );
          await temp.rename(file.path);
        }),
      );
    }
    return lines.sublist(lines.length > limit ? lines.length - limit : 0);
  }

  @override
  void append(String networkId, String conversation, StoredLine line) {
    final file = _file(networkId, conversation);
    unawaited(
      _enqueue(file, () async {
        await file.parent.create(recursive: true);
        await file.writeAsString(
          '${jsonEncode(line.toJson())}\n',
          mode: FileMode.append,
        );
      }),
    );
  }

  @override
  Future<void> clear(String networkId, String conversation) {
    final file = _file(networkId, conversation);
    return _enqueue(file, () async {
      if (file.existsSync()) await file.delete();
    });
  }

  @override
  Future<void> clearAll() async {
    await Future.wait(_queues.values);
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

/// `main.dart` overrides this with a [FileChatHistoryStore].
final chatHistoryStoreProvider = Provider<ChatHistoryStore>(
  (ref) => MemoryChatHistoryStore(),
);
