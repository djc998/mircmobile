/// What the conversation lists show: each chat's last activity and preview,
/// sorted lists for Rooms home and the sidebar, and the Mentions feed.
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/chat_layout.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';

/// One room or private chat as a row: when something last happened and a
/// one-line preview of it.
class ConversationInfo {
  const ConversationInfo({
    required this.buffer,
    required this.network,
    this.last,
  });

  final ChatBuffer buffer;
  final NetworkSession network;

  /// The newest message, action or notice (not joins and other events).
  final ChatLine? last;

  String get key => buffer.key;
  String get name => buffer.name;
  bool get isRoom => buffer.isChannel;
  DateTime? get lastActivity => last?.time;

  /// `alice: does it run on the Mac?`, `You: on my way`, or `* bob waves`.
  String get preview {
    final l = last;
    if (l == null) return '';
    final text = stripFormatting(l.text).replaceAll(RegExp(r'\s+'), ' ');
    return switch (l.kind) {
      ChatLineKind.own => 'You: $text',
      ChatLineKind.action => '* ${l.sender} $text',
      _ when !isRoom => text,
      _ => '${l.sender}: $text',
    };
  }
}

/// Lines that count as activity in a conversation list.
bool _isActivity(ChatLine l) => switch (l.kind) {
  ChatLineKind.message ||
  ChatLineKind.action ||
  ChatLineKind.notice ||
  ChatLineKind.own => l.sender != null,
  _ => false,
};

ConversationInfo conversationInfo(ChatBuffer buffer, NetworkSession network) {
  ChatLine? last;
  for (final l in buffer.lines.reversed) {
    if (_isActivity(l)) {
      last = l;
      break;
    }
  }
  return ConversationInfo(buffer: buffer, network: network, last: last);
}

/// Every open room and private chat on every network, newest activity
/// first; ones with no messages yet keep the order they were opened in,
/// after the rest.
List<ConversationInfo> activeConversations(ChatState state) {
  final all = [
    for (final b in state.buffers.values)
      if (!b.isStatus && state.networks[b.networkId] != null)
        conversationInfo(b, state.networks[b.networkId]!),
  ];
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  // A stable sort: List.sort isn't, so sort indexes.
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final t = (b.$2.lastActivity ?? epoch).compareTo(
        a.$2.lastActivity ?? epoch,
      );
      return t != 0 ? t : a.$1.compareTo(b.$1);
    });
  return [for (final (_, c) in indexed) c];
}

/// The sidebar's sections, in order. Every conversation is in exactly one.
enum SidebarSection {
  favorites('Favorites'),
  rooms('Rooms'),
  privateChats('Private chats');

  SidebarSection(this.title);
  final String title;
}

/// Open conversations by sidebar section, each section in the order the
/// chats were opened (so rows don't jump around while you read).
Map<SidebarSection, List<ConversationInfo>> sidebarSections(
  ChatState state,
  RoomPrefs prefs,
) {
  final sections = {
    for (final s in SidebarSection.values) s: <ConversationInfo>[],
  };
  for (final b in state.buffers.values) {
    final net = state.networks[b.networkId];
    if (b.isStatus || net == null) continue;
    final info = conversationInfo(b, net);
    final section = !b.isChannel
        ? SidebarSection.privateChats
        : prefs.isFavorite(net.id, b.name)
        ? SidebarSection.favorites
        : SidebarSection.rooms;
    sections[section]!.add(info);
  }
  return sections;
}

/// The conversations Cmd+1…9 jump to: the sidebar's order.
List<ConversationInfo> sidebarOrder(ChatState state, RoomPrefs prefs) => [
  for (final list in sidebarSections(state, prefs).values) ...list,
];

/// A message that mentions you, for the Mentions list.
class MentionInfo {
  const MentionInfo(this.line, this.conversation);

  final ChatLine line;
  final ConversationInfo conversation;
}

/// Messages that mention you in any open conversation, newest first.
List<MentionInfo> mentionsIn(ChatState state, {int limit = 100}) {
  final found = <MentionInfo>[];
  for (final b in state.buffers.values) {
    final net = state.networks[b.networkId];
    if (b.isStatus || net == null) continue;
    final info = conversationInfo(b, net);
    for (final l in b.lines) {
      if (lineMentions(l, net.nick)) found.add(MentionInfo(l, info));
    }
  }
  found.sort((a, b) => b.line.time.compareTo(a.line.time));
  return found.take(limit).toList();
}

/// Conversations with an unread mention (the Mentions tab badge). Muted
/// chats don't count when [prefs] is given.
int unreadMentionChats(ChatState state, [RoomPrefs? prefs]) => state
    .buffers
    .values
    .where(
      (b) => b.mentioned && !(prefs?.isMuted(b.networkId, b.name) ?? false),
    )
    .length;

/// New messages in the chats you're not looking at, for the badge on a
/// phone chat's back button.
typedef UnreadElsewhere = ({int chats, bool mention});

/// How many conversations other than the open one have unread messages,
/// and whether any of them mentions you. Server tabs don't count, and muted
/// chats only count when they mention you.
UnreadElsewhere unreadElsewhere(ChatState state, RoomPrefs prefs) {
  var chats = 0;
  var mention = false;
  for (final b in state.buffers.values) {
    if (b.key == state.activeKey || b.isStatus || b.unread == 0) continue;
    if (prefs.isMuted(b.networkId, b.name) && !b.mentioned) continue;
    chats++;
    mention = mention || b.mentioned;
  }
  return (chats: chats, mention: mention);
}

/// A short network name for the chip on each row: `Libera.Chat` → `Libera`,
/// `irc.oftc.net` → `oftc`.
String shortNetworkName(String label) {
  const skip = {'irc', 'chat', 'net', 'org', 'com', 'io'};
  final parts = label.split('.');
  if (parts.length == 1) return label;
  for (final p in parts) {
    if (p.isNotEmpty && !skip.contains(p.toLowerCase())) return p;
  }
  return label;
}

/// Matches for the quick switcher: name starts with [query] first, then
/// contains it.
List<ConversationInfo> switcherMatches(ChatState state, String query) {
  final q = query.trim().toLowerCase().replaceFirst(RegExp('^[#&]+'), '');
  final all = activeConversations(state);
  if (q.isEmpty) return all;
  String bare(ConversationInfo c) =>
      c.name.toLowerCase().replaceFirst(RegExp('^[#&]+'), '');
  return [
    ...all.where((c) => bare(c).startsWith(q)),
    ...all.where((c) => !bare(c).startsWith(q) && bare(c).contains(q)),
  ];
}
