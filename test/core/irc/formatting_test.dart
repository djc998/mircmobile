import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/formatting.dart';

void main() {
  test('strips colours, styles and resets', () {
    expect(
      stripFormatting('\x02bold\x02 \x0304red\x03 \x034,12both\x0F'),
      'bold red both',
    );
    expect(
      stripFormatting('\x1Ditalic\x1D \x1Funder\x1F \x16rev'),
      'italic under rev',
    );
    expect(stripFormatting('\x04FF0000hex\x04'), 'hex');
  });

  test('keeps digits that are not part of a colour code', () {
    expect(stripFormatting('\x0312345'), '345');
    expect(stripFormatting('room 42'), 'room 42');
  });

  test('nick validation', () {
    expect(isValidNick('Dennis'), isTrue);
    expect(isValidNick('[away]_99'), isTrue);
    expect(isValidNick('9lives'), isFalse);
    expect(isValidNick('has space'), isFalse);
    expect(isValidNick(''), isFalse);
    expect(isValidNick('a' * 31), isFalse);
  });

  group('mentions', () {
    test('matches whole words only, ignoring case', () {
      expect(mentions('hi Al!', 'al'), isTrue);
      expect(mentions('al: you there?', 'al'), isTrue);
      expect(mentions('also, totally', 'al'), isFalse);
      expect(mentions('ping dennis_', 'dennis'), isFalse);
      expect(mentions('[x] wants dennis|away', 'dennis|away'), isTrue);
      expect(mentions('anything', ''), isFalse);
    });
  });

  group('completeNick', () {
    const nicks = ['bob', 'Alice', 'albert'];
    test('completes the last word, addressing at line start', () {
      expect(completeNick('al', nicks), 'albert: ');
      expect(completeNick('ali', nicks), 'Alice: ');
      expect(completeNick('thanks bo', nicks), 'thanks bob ');
      expect(completeNick('thanks zz', nicks), isNull);
      expect(completeNick('', nicks), isNull);
    });
  });
}
