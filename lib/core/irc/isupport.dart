/// RPL_ISUPPORT (005) server feature parsing.
library;

/// Server features advertised with numeric 005.
class ISupport {
  /// Raw tokens, e.g. `{'CHANTYPES': '#&', 'ELIST': 'CMNTU'}`.
  final Map<String, String> tokens = {};

  /// Mode letters to prefix symbols, e.g. `o` -> `@`, in rank order.
  Map<String, String> prefixes = const {'o': '@', 'v': '+'};

  String chanTypes = '#&';
  String? networkName;
  String caseMapping = 'rfc1459';

  /// Applies the params of one 005 line (excluding our nick and the trailer).
  void apply(List<String> params) {
    for (final token in params) {
      if (token.isEmpty) continue;
      if (token.startsWith('-')) {
        tokens.remove(token.substring(1));
        continue;
      }
      final eq = token.indexOf('=');
      final key = eq == -1 ? token : token.substring(0, eq);
      final value = eq == -1 ? '' : token.substring(eq + 1);
      tokens[key] = value;
      switch (key) {
        case 'PREFIX':
          prefixes = _parsePrefix(value);
        case 'CHANTYPES':
          chanTypes = value;
        case 'NETWORK':
          networkName = value;
        case 'CASEMAPPING':
          caseMapping = value.toLowerCase();
      }
    }
  }

  /// Whether ELIST supports a filter letter, e.g. `U` for user counts.
  bool supportsElist(String letter) =>
      (tokens['ELIST'] ?? '').toUpperCase().contains(letter);

  bool isChannel(String target) =>
      target.isNotEmpty && chanTypes.contains(target[0]);

  /// The prefix symbols in rank order, e.g. `~&@%+`.
  String get prefixSymbols => prefixes.values.join();

  /// Case-folds a nick or channel for comparisons.
  String fold(String s) {
    final lower = s.toLowerCase();
    if (caseMapping == 'ascii') return lower;
    final strict = caseMapping == 'strict-rfc1459';
    return lower
        .replaceAll('[', '{')
        .replaceAll(']', '}')
        .replaceAll(r'\', '|')
        .replaceAll('~', strict ? '~' : '^');
  }

  static Map<String, String> _parsePrefix(String value) {
    final match = RegExp(r'^\(([^)]*)\)(.*)$').firstMatch(value);
    if (match == null) return const {};
    final modes = match.group(1)!;
    final symbols = match.group(2)!;
    final out = <String, String>{};
    for (var i = 0; i < modes.length && i < symbols.length; i++) {
      out[modes[i]] = symbols[i];
    }
    return out;
  }
}
