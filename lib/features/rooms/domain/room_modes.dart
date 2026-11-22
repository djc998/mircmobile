/// Plain-language descriptions of IRC channel modes and the settings a
/// room owner can change.
library;

/// Settings for a new room, or changes to an existing one. Null fields are
/// left as they are.
class RoomSettings {
  const RoomSettings({
    this.inviteOnly,
    this.secret,
    this.topicLocked,
    this.password,
    this.moderated,
    this.noOutsideMessages,
    this.limit,
  });

  /// Only invited people can join (+i).
  final bool? inviteOnly;

  /// Hidden from the room list and /whois (+s).
  final bool? secret;

  /// Only operators can change the topic (+t).
  final bool? topicLocked;

  /// Join password (+k). Empty removes it.
  final String? password;

  /// Only operators and people with a voice can talk (+m).
  final bool? moderated;

  /// People who aren't in the room can't send messages to it (+n).
  final bool? noOutsideMessages;

  /// Most people allowed in the room (+l). 0 removes the limit.
  final int? limit;
}

/// The MODE change that turns [current] into [wanted], as `modes` and
/// `args` (for example `+ik-s` and `['secret']`), or null if nothing
/// changes.
({String modes, List<String> args})? modeChange({
  required Set<String> current,
  required String? currentKey,
  required RoomSettings wanted,
  int? currentLimit,
}) {
  final add = StringBuffer();
  final remove = StringBuffer();
  final addArgs = <String>[];
  final removeArgs = <String>[];
  void flag(String mode, bool? on) {
    if (on == null || on == current.contains(mode)) return;
    (on ? add : remove).write(mode);
  }

  flag('i', wanted.inviteOnly);
  flag('s', wanted.secret);
  flag('t', wanted.topicLocked);
  flag('m', wanted.moderated);
  flag('n', wanted.noOutsideMessages);
  final limit = wanted.limit;
  if (limit != null) {
    if (limit <= 0 && currentLimit != null) {
      remove.write('l');
    } else if (limit > 0 && limit != currentLimit) {
      add.write('l');
      addArgs.add('$limit');
    }
  }
  final password = wanted.password?.trim();
  if (password != null) {
    if (password.isEmpty && currentKey != null) {
      remove.write('k');
      removeArgs.add(currentKey); // Some servers want the old key.
    } else if (password.isNotEmpty && password != currentKey) {
      if (currentKey != null) {
        remove.write('k');
        removeArgs.add(currentKey);
      }
      add.write('k');
      addArgs.add(password);
    }
  }
  if (add.isEmpty && remove.isEmpty) return null;
  return (
    modes: '${remove.isEmpty ? '' : '-$remove'}${add.isEmpty ? '' : '+$add'}',
    args: [...removeArgs, ...addArgs],
  );
}

const _modeNames = {
  'i': 'invite only',
  'k': 'password',
  's': 'hidden from the room list',
  'p': 'private',
  't': 'only operators change the topic',
  'n': 'no messages from outside',
  'm': 'moderated (only voiced people talk)',
  'l': 'user limit',
  'b': 'ban',
  'o': 'operator',
  'v': 'voice',
  'h': 'half-operator',
};

/// Describes a MODE change such as `+ik-s secret` in words, e.g.
/// "invite only on, password on, hidden from the room list off". Passwords
/// are not shown.
String describeModeChange(String change) {
  final parts = change.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return change;
  final args = parts.sublist(1);
  var argIndex = 0;
  var adding = true;
  final out = <String>[];
  for (final c in parts.first.split('')) {
    if (c == '+' || c == '-') {
      adding = c == '+';
      continue;
    }
    final name = _modeNames[c] ?? 'mode $c';
    switch (c) {
      case 'o' || 'v' || 'h' || 'b':
        final who = argIndex < args.length ? args[argIndex++] : '';
        out.add(
          '${adding ? 'gave' : 'took'} $name ${adding ? 'to' : 'from'} '
          '$who',
        );
      case 'k':
        argIndex++;
        out.add('$name ${adding ? 'set' : 'removed'}');
      case 'l':
        if (adding) {
          final n = argIndex < args.length ? args[argIndex++] : '';
          out.add('$name $n');
        } else {
          out.add('$name removed');
        }
      default:
        out.add('$name ${adding ? 'on' : 'off'}');
    }
  }
  return out.join(', ');
}
