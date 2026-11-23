import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/chat_layout.dart';

final t0 = DateTime(2026, 11, 22, 10);

ChatLine msg(
  String sender,
  String text, {
  int minute = 0,
  ChatLineKind kind = ChatLineKind.message,
  DateTime? day,
}) => ChatLine(
  text: text,
  sender: sender,
  kind: kind,
  time: (day ?? t0).add(Duration(minutes: minute)),
);

ChatLine presence(String nick, PresenceChange change, {int minute = 0}) =>
    ChatLine(
      text: change == PresenceChange.joined ? '$nick joined' : '$nick left',
      kind: ChatLineKind.event,
      presence: change,
      subject: nick,
      time: t0.add(Duration(minutes: minute)),
    );

List<ChatItem> grouped(List<ChatLine> lines, {ChatLine? unread}) =>
    layoutChat(lines, grouped: true, ownNick: 'me', unreadMarker: unread);

void main() {
  test('messages from one person within 5 minutes share a group', () {
    final items = grouped([
      msg('bob', 'one'),
      msg('Bob', 'two', minute: 4),
      msg('bob', 'three', minute: 9), // 5 minutes after "two"
      msg('bob', 'later', minute: 15), // 6 minutes after "three"
      msg('alice', 'hi', minute: 15),
    ]);
    expect(items.first, isA<DayItem>());
    final groups = items.whereType<GroupItem>().toList();
    expect(groups.map((g) => g.lines.length), [3, 1, 1]);
    expect(groups.map((g) => g.sender), ['bob', 'bob', 'alice']);
  });

  test('mentions, own messages and notices start their own groups', () {
    final items = grouped([
      msg('bob', 'hello'),
      msg('bob', 'me: are you there?', minute: 1),
      msg('bob', 'ok', minute: 2),
      msg('bob', 'psst', minute: 2, kind: ChatLineKind.notice),
      msg('me', 'yes', minute: 3, kind: ChatLineKind.own),
      msg('me', 'here', minute: 3, kind: ChatLineKind.own),
    ]);
    final groups = items.whereType<GroupItem>().toList();
    expect(groups.map((g) => g.lines.length), [1, 1, 1, 1, 2]);
    expect(groups.map((g) => g.mentioned), [false, true, false, false, false]);
    expect(groups.last.own, isTrue);
  });

  test('joins and leaves in a row collapse into one item', () {
    final items = grouped([
      presence('mara', PresenceChange.joined),
      presence('kai', PresenceChange.joined),
      presence('sam', PresenceChange.left),
      msg('bob', 'hi', minute: 1),
      presence('zoe', PresenceChange.joined, minute: 2),
      ChatLine(
        text: 'bob set the topic: hi',
        kind: ChatLineKind.event,
        time: t0.add(const Duration(minutes: 3)),
      ),
    ]);
    expect(items.map((i) => i.runtimeType), [
      DayItem,
      PresenceItem,
      GroupItem,
      PresenceItem,
      SystemItem,
    ]);
    expect(
      presenceSummary((items[1] as PresenceItem).lines),
      'mara and kai joined · sam left',
    );
    expect(presenceSummary((items[3] as PresenceItem).lines), 'zoe joined');
  });

  test('a day divider before each day and the new-messages divider', () {
    final yesterday = t0.subtract(const Duration(days: 1));
    final unread = msg('bob', 'new one', minute: 2);
    final items = grouped([
      msg('bob', 'old', day: yesterday),
      msg('bob', 'seen'),
      unread,
      msg('bob', 'newer', minute: 3),
    ], unread: unread);
    expect(items.map((i) => i.runtimeType), [
      DayItem,
      GroupItem,
      DayItem,
      GroupItem,
      UnreadItem,
      GroupItem,
    ]);
    // The divider splits the group.
    expect((items.last as GroupItem).lines.length, 2);
  });

  test('Compact: one line each, still with dividers', () {
    final items = layoutChat(
      [
        msg('bob', 'one'),
        msg('bob', 'two'),
        presence('kai', PresenceChange.joined),
      ],
      grouped: false,
      ownNick: 'me',
    );
    expect(items.map((i) => i.runtimeType), [
      DayItem,
      LineItem,
      LineItem,
      LineItem,
    ]);
  });

  test('nameList', () {
    expect(nameList(['a']), 'a');
    expect(nameList(['a', 'b']), 'a and b');
    expect(nameList(['a', 'b', 'c']), 'a, b and c');
    expect(nameList(['a', 'b', 'c', 'd', 'e']), 'a, b and 3 others');
  });

  test('a single join or quit keeps its text (and reason)', () {
    final quit = ChatLine(
      text: 'sam quit (Ping timeout)',
      kind: ChatLineKind.event,
      presence: PresenceChange.left,
      subject: 'sam',
    );
    expect(presenceSummary([quit]), 'sam quit (Ping timeout)');
  });
}
