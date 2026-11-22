/// Which side panels are pinned open on wide screens (Mac, iPad, tablets):
/// servers and chats on the left, people in the room on the right.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';

/// Panels can be pinned when the window is at least this wide. Narrower
/// screens (phones) open them as slide-out drawers instead.
const double pinnedPanelsMinWidth = 900;

/// Below this width (phones held upright) the chat title bar keeps only the
/// buttons for the open chat; Browse rooms, New private message, Join a
/// room and Favorite move into the ⋮ menu so the chat's name fits.
const double compactTitleBarMaxWidth = 600;

class PanelPrefs {
  const PanelPrefs({this.chatsPinned = true, this.peoplePinned = true});

  /// Servers and chats on the left.
  final bool chatsPinned;

  /// People in the room on the right.
  final bool peoplePinned;
}

final panelPrefsProvider = NotifierProvider<PanelPrefsController, PanelPrefs>(
  PanelPrefsController.new,
);

class PanelPrefsController extends Notifier<PanelPrefs> {
  static const _chatsKey = 'pinChatsPanel';
  static const _peopleKey = 'pinPeoplePanel';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  PanelPrefs build() => PanelPrefs(
    chatsPinned: _store.getString(_chatsKey) != 'false',
    peoplePinned: _store.getString(_peopleKey) != 'false',
  );

  Future<void> toggleChats() async {
    final pinned = !state.chatsPinned;
    state = PanelPrefs(chatsPinned: pinned, peoplePinned: state.peoplePinned);
    await _store.setString(_chatsKey, '$pinned');
  }

  Future<void> togglePeople() async {
    final pinned = !state.peoplePinned;
    state = PanelPrefs(chatsPinned: state.chatsPinned, peoplePinned: pinned);
    await _store.setString(_peopleKey, '$pinned');
  }
}
