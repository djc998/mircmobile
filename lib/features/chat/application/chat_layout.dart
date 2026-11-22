/// Turns a conversation's lines into what the chat view draws: day and
/// "New messages" dividers, groups of messages from one person, and runs of
/// joins and leaves collapsed into one line.
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';

/// Messages from one person this close together share one avatar and name.
const Duration messageGroupGap = Duration(minutes: 5);

/// One thing in the chat view, oldest first.
sealed class ChatItem {
  const ChatItem();
}

/// "Today", "Yesterday" or a date, before the first line of each day.
class DayItem extends ChatItem {
  const DayItem(this.day);

  /// Local midnight of the day.
  final DateTime day;
}

/// The coral "New messages" divider before the first unread line.
class UnreadItem extends ChatItem {
  const UnreadItem();
}

/// Messages in a row from [sender]: under one avatar and name in a room, or
/// as stacked bubbles in a private chat.
class GroupItem extends ChatItem {
  GroupItem(this.lines, {required this.own, required this.mentioned});

  final List<ChatLine> lines;

  /// Sent by you: accent bar in rooms, right-hand bubbles in private chats.
  final bool own;

  /// Mentions you: coral bar and tint.
  final bool mentioned;

  String get sender => lines.first.sender!;
  DateTime get time => lines.first.time;
}

/// Joins and leaves in a row, shown as one muted line that expands.
class PresenceItem extends ChatItem {
  PresenceItem(this.lines);

  final List<ChatLine> lines;
}

/// Any other event or error, as a centred muted line.
class SystemItem extends ChatItem {
  const SystemItem(this.line);

  final ChatLine line;
}

/// One line as `HH:MM <nick> text`, for Compact and the server tab.
class LineItem extends ChatItem {
  const LineItem(this.line);

  final ChatLine line;
}

/// Whether [line] mentions [ownNick] (never your own messages).
bool lineMentions(ChatLine line, String ownNick) =>
    line.kind != ChatLineKind.own &&
    line.sender != null &&
    ownNick.isNotEmpty &&
    mentions(line.text, ownNick);

/// Lays out [lines]. With [grouped] off (Compact, server tab) every line is
/// a [LineItem]; dividers are added either way. The "New messages" divider
/// goes before [unreadMarker].
List<ChatItem> layoutChat(
  List<ChatLine> lines, {
  required bool grouped,
  required String ownNick,
  ChatLine? unreadMarker,
}) {
  final items = <ChatItem>[];
  DateTime? day;
  // The group or presence run the next line may join; null after a divider
  // or any other item.
  GroupItem? group;
  PresenceItem? presence;
  for (final line in lines) {
    final local = line.time.toLocal();
    final lineDay = DateTime(local.year, local.month, local.day);
    if (lineDay != day) {
      day = lineDay;
      items.add(DayItem(lineDay));
      group = null;
      presence = null;
    }
    if (identical(line, unreadMarker)) {
      items.add(const UnreadItem());
      group = null;
      presence = null;
    }
    if (!grouped) {
      items.add(LineItem(line));
      continue;
    }
    switch (line.kind) {
      case ChatLineKind.event when line.presence != null:
        group = null;
        if (presence != null) {
          presence.lines.add(line);
        } else {
          presence = PresenceItem([line]);
          items.add(presence);
        }
      case ChatLineKind.event || ChatLineKind.error:
        group = null;
        presence = null;
        items.add(SystemItem(line));
      case _ when line.sender == null:
        // Server notices with no sender.
        group = null;
        presence = null;
        items.add(LineItem(line));
      case _:
        presence = null;
        final own = line.kind == ChatLineKind.own;
        final mentioned = lineMentions(line, ownNick);
        final previous = group?.lines.last;
        final joins =
            group != null &&
            previous != null &&
            group.own == own &&
            group.mentioned == mentioned &&
            previous.sender!.toLowerCase() == line.sender!.toLowerCase() &&
            (previous.kind == ChatLineKind.notice) ==
                (line.kind == ChatLineKind.notice) &&
            line.time.difference(previous.time) <= messageGroupGap;
        if (joins) {
          group.lines.add(line);
        } else {
          group = GroupItem([line], own: own, mentioned: mentioned);
          items.add(group);
        }
    }
  }
  return items;
}

/// "mara, kai and 3 others joined · sam left". A single line keeps its own
/// text, with any quit reason.
String presenceSummary(List<ChatLine> lines) {
  if (lines.length == 1) return lines.single.text;
  final joined = <String>[];
  final left = <String>[];
  for (final line in lines) {
    final who = line.subject ?? '';
    final list = line.presence == PresenceChange.joined ? joined : left;
    if (!list.contains(who)) list.add(who);
  }
  return [
    if (joined.isNotEmpty) '${nameList(joined)} joined',
    if (left.isNotEmpty) '${nameList(left)} left',
  ].join(' · ');
}

/// `a`, `a and b`, `a, b and c`, `a, b and 3 others`.
String nameList(List<String> names) => switch (names.length) {
  0 => '',
  1 => names.first,
  2 => '${names[0]} and ${names[1]}',
  3 => '${names[0]}, ${names[1]} and ${names[2]}',
  _ => '${names[0]}, ${names[1]} and ${names.length - 2} others',
};
