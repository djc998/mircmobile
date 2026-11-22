import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/completions.dart';

void main() {
  const nicks = ['bob', 'alice', 'Alfred', 'carol'];
  const rooms = ['#linux', '#lisp', '#flutter'];

  List<String> labels(String text, {int? cursor}) => [
    for (final c in completionsFor(
      text,
      cursor ?? text.length,
      nicks: nicks,
      rooms: rooms,
    ))
      c.label,
  ];

  test('@ suggests people, sorted', () {
    expect(labels('@al'), ['@Alfred', '@alice']);
    expect(labels('hi @c'), ['@carol']);
    expect(labels('@'), ['@Alfred', '@alice', '@bob', '@carol']);
  });

  test('/ suggests commands only at the start of the line', () {
    expect(labels('/to'), ['/topic']);
    expect(labels('/de'), ['/deop', '/devoice']);
    expect(labels('see /to'), isEmpty);
  });

  test('# suggests rooms you are in', () {
    expect(labels('join #li'), ['#linux', '#lisp']);
  });

  test('nothing for plain words or an empty field', () {
    expect(labels(''), isEmpty);
    expect(labels('hello'), isEmpty);
    expect(labels('hello '), isEmpty);
  });

  test('picking a person addresses them at the start of a line', () {
    final c = completionsFor('@al', 3, nicks: ['alice']).single;
    expect(applyCompletion('@al', 3, c), ('alice: ', 7));
    final mid = completionsFor('thanks @al', 10, nicks: ['alice']).single;
    expect(applyCompletion('thanks @al', 10, mid), ('thanks alice ', 13));
  });

  test('completes the word at the cursor, keeping the rest', () {
    final c = completionsFor('/to rest', 3).single;
    expect(applyCompletion('/to rest', 3, c), ('/topic rest', 7));
  });

  test('at most 8 suggestions', () {
    final many = [for (var i = 0; i < 20; i++) 'nick$i'];
    expect(completionsFor('@n', 2, nicks: many), hasLength(maxCompletions));
  });
}
