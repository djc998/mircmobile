import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/features/chat/data/chat_history_store.dart';

StoredLine line(int i) => StoredLine(
  time: DateTime.utc(2026).add(Duration(minutes: i)),
  kind: 'message',
  text: 'line $i',
  sender: 'bob',
);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('history_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('saves and loads lines per network and conversation', () async {
    final store = FileChatHistoryStore(dir)
      ..append('irc.libera.chat', '#Room/1', line(1))
      ..append('irc.libera.chat', '#room/1', line(2))
      ..append('irc.oftc.net', '#room/1', line(3));
    final lines = await store.load('IRC.LIBERA.CHAT', '#ROOM/1');
    expect(lines.map((l) => l.text), ['line 1', 'line 2']);
    expect(lines.first.sender, 'bob');
    expect(lines.first.time, DateTime.utc(2026, 1, 1, 0, 1));

    // A new store (next launch) reads the same files.
    final again = await FileChatHistoryStore(dir)
        .load('irc.oftc.net', '#room/1');
    expect(again.single.text, 'line 3');
  });

  test('keeps only the newest lines', () async {
    final store = FileChatHistoryStore(dir, maxLines: 10);
    for (var i = 0; i < 15; i++) {
      store.append('n', 'alice', line(i));
    }
    expect((await store.load('n', 'alice', limit: 3)).map((l) => l.text), [
      'line 12',
      'line 13',
      'line 14',
    ]);
    // Trimmed back to half of maxLines on disk (once the trim has landed:
    // load waits for queued writes).
    await store.load('n', 'alice');
    final reread = await FileChatHistoryStore(
      dir,
      maxLines: 10,
    ).load('n', 'alice');
    expect(reread.length, 5);
    expect(reread.last.text, 'line 14');
  });

  test('skips damaged lines and clears', () async {
    final store = FileChatHistoryStore(dir)..append('n', 'alice', line(1));
    await store.load('n', 'alice');
    dir
        .listSync(recursive: true)
        .whereType<File>()
        .single
        .writeAsStringSync('{broken\n', mode: FileMode.append);
    store.append('n', 'alice', line(2));
    expect((await store.load('n', 'alice')).length, 2);

    await store.clear('n', 'alice');
    expect(await store.load('n', 'alice'), isEmpty);
    store.append('n', 'bob', line(3));
    await store.clearAll();
    expect(await store.load('n', 'bob'), isEmpty);
  });
}
