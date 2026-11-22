/// Avatars for people and rooms. IRC has no profile pictures, so both are
/// drawn from the name.
library;

import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A person's standing in a room, shown as a ring around their avatar.
enum NickRole { member, voiced, op }

/// Up to two initials on a circle tinted with the person's nick colour.
///
/// Operators get a gold ring, voiced people an accent ring, and people who
/// are away are drawn at half opacity. Screen readers hear the nick and
/// role, not the initials.
class NickAvatar extends StatelessWidget {
  const NickAvatar({
    required this.nick,
    this.size = 36,
    this.role = NickRole.member,
    this.away = false,
    super.key,
  });

  final String nick;
  final double size;
  final NickRole role;
  final bool away;

  /// Initials for [nick]: the first letters of its first two words, where
  /// words are split on punctuation (`_ - | . [ ]` and so on) and on
  /// lower-to-upper case changes. `alice` → `A`, `dark_star` → `DS`,
  /// `DarkStar` → `DS`, `[x]bob` → `XB`.
  static String initials(String nick) {
    final spaced = nick.replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    final words = spaced
        .split(RegExp('[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return nick.isEmpty ? '?' : nick.characters.first;
    final letters = words.take(2).map((w) => w[0]).join();
    return letters.toUpperCase();
  }

  /// What a screen reader says: `alice, operator, away`.
  String get semanticLabel => [
    nick,
    if (role == NickRole.op) 'operator',
    if (role == NickRole.voiced) 'voiced',
    if (away) 'away',
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final brightness = theme.brightness;
    final nickColor = ChatColors.of(context).nickColor(nick);
    final fill = Color.alphaBlend(
      nickColor.withValues(alpha: brightness == Brightness.dark ? 0.20 : 0.12),
      tokens.surface,
    );
    final textColor = AppTokens.readableOn(nickColor, fill, brightness);
    final ring = switch (role) {
      NickRole.op => tokens.op,
      NickRole.voiced => tokens.accent,
      NickRole.member => null,
    };
    final ringWidth = size >= 32 ? 2.0 : 1.5;

    Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(size * 0.18),
        child: FittedBox(
          child: Text(
            initials(nick),
            // Fixed size inside a fixed circle; the label is in semantics.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              color: textColor,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ),
    );
    if (ring != null) {
      // A coloured ring with a hairline of background between it and the
      // circle, so it reads on any fill.
      circle = Container(
        padding: EdgeInsets.all(ringWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: ringWidth),
        ),
        child: circle,
      );
    } else {
      circle = Padding(padding: EdgeInsets.all(ringWidth * 2), child: circle);
    }
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Opacity(opacity: away ? 0.5 : 1, child: circle),
    );
  }
}

/// The first letter of a room's name (after `#`) on an accent-soft rounded
/// square. Square in Classic mIRC.
class RoomAvatar extends StatelessWidget {
  const RoomAvatar({required this.name, this.size = 36, super.key});

  final String name;
  final double size;

  /// `#linux` → `L`, `##chat` → `C`, `&local` → `L`, `#` → `#`.
  static String letter(String name) {
    final match = RegExp('[A-Za-z0-9]').firstMatch(name);
    if (match == null) return name.isEmpty ? '#' : name.characters.first;
    return match[0]!.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: 'Room $name',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Color.alphaBlend(tokens.accentSoft, tokens.surface),
          borderRadius: BorderRadius.circular(tokens.radius(size / 3)),
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.2),
          child: FittedBox(
            child: Text(
              letter(name),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: tokens.onAccentSoft,
                fontSize: size * 0.45,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
