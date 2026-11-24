import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/networks.dart';

void main() {
  IrcNetwork preset(String host) =>
      builtInNetworks.firstWhere((n) => n.host == host);

  test('Undernet connects in plain text on 6667: it has no TLS port', () {
    final undernet = preset('irc.undernet.org');
    expect(undernet.useTls, isFalse);
    expect(undernet.port, 6667);
    expect(undernet.description, contains('Not encrypted'));
  });

  test('every other preset uses TLS on 6697', () {
    for (final n in builtInNetworks) {
      if (n.host == 'irc.undernet.org') continue;
      expect(n.useTls, isTrue, reason: n.name);
      expect(n.port, 6697, reason: n.name);
    }
  });
}
