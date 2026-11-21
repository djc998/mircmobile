/// Turns what the user types into IRC actions (`/join`, `/me`, plain text).
library;

import 'dart:async';

import 'package:irc_client/core/irc/irc_client.dart';

/// The result of running a line of input.
sealed class InputResult {
  const InputResult();
}

class InputSent extends InputResult {
  const InputSent();
}

/// The user asked to open a private conversation (e.g. `/query nick`).
class InputOpenQuery extends InputResult {
  const InputOpenQuery(this.nick);

  final String nick;
}

/// Something was wrong with the input; show [message] to the user.
class InputError extends InputResult {
  const InputError(this.message);

  final String message;
}

/// Commands shown in help and autocomplete.
const Map<String, String> inputCommandHelp = {
  '/join #channel [key]': 'Join a channel',
  '/part [#channel] [reason]': 'Leave a channel',
  '/msg nick message': 'Send a private message',
  '/query nick': 'Open a private conversation',
  '/me action': 'Describe an action',
  '/nick newnick': 'Change your nickname',
  '/topic [text]': 'Show or change the channel topic',
  '/whois nick': 'Look up a user',
  '/notice target message': 'Send a notice',
  '/list [min users]': 'List channels on the network',
  '/mode [#channel] +modes [args]': 'Change room settings (operators)',
  '/invite nick [#channel]': 'Invite someone to a room',
  '/kick nick [reason]': 'Remove someone from the room (operators)',
  '/ban nick': 'Ban someone from the room (operators)',
  '/op nick, /deop nick': 'Give or take operator status',
  '/voice nick, /devoice nick': 'Give or take voice',
  '/quote raw line': 'Send a raw IRC command',
  '/quit [reason]': 'Disconnect',
};

/// Runs one line of user input against [client].
///
/// [target] is the channel or nick of the open conversation, or null in the
/// server/status window.
InputResult runInput(IrcClient client, String input, {String? target}) {
  final text = input.trimRight();
  if (text.isEmpty) return const InputSent();

  // `//text` sends a literal line starting with '/'.
  if (!text.startsWith('/') || text.startsWith('//')) {
    final body = text.startsWith('//') ? text.substring(1) : text;
    if (target == null) {
      return const InputError(
        'Join a channel or open a chat to send messages.',
      );
    }
    client.sendMessage(target, body);
    return const InputSent();
  }

  final space = text.indexOf(' ');
  final command = (space == -1 ? text.substring(1) : text.substring(1, space))
      .toLowerCase();
  final rest = space == -1 ? '' : text.substring(space + 1).trim();
  final args = rest.isEmpty ? <String>[] : rest.split(RegExp(r'\s+'));

  String restAfter(int n) => args.length <= n ? '' : args.skip(n).join(' ');

  switch (command) {
    case 'join' || 'j':
      if (args.isEmpty) return const InputError('Usage: /join #channel [key]');
      var channel = args[0];
      if (!client.isChannel(channel)) channel = '#$channel';
      client.join(channel, key: args.length > 1 ? args[1] : null);
    case 'part' || 'leave':
      String? channel;
      var reasonFrom = 0;
      if (args.isNotEmpty && client.isChannel(args[0])) {
        channel = args[0];
        reasonFrom = 1;
      } else if (target != null && client.isChannel(target)) {
        channel = target;
      }
      if (channel == null) return const InputError('Usage: /part #channel');
      final reason = restAfter(reasonFrom);
      client.part(channel, reason: reason.isEmpty ? null : reason);
    case 'msg' || 'privmsg':
      if (args.length < 2) return const InputError('Usage: /msg nick message');
      client.sendMessage(args[0], restAfter(1));
    case 'query' || 'q':
      if (args.isEmpty) return const InputError('Usage: /query nick');
      if (args.length > 1) client.sendMessage(args[0], restAfter(1));
      return InputOpenQuery(args[0]);
    case 'me':
      if (target == null) return const InputError('/me only works in a chat.');
      if (rest.isEmpty) return const InputError('Usage: /me action');
      client.sendAction(target, rest);
    case 'notice':
      if (args.length < 2) {
        return const InputError('Usage: /notice target message');
      }
      client.sendNotice(args[0], restAfter(1));
    case 'nick':
      if (args.length != 1) return const InputError('Usage: /nick newnick');
      client.changeNick(args[0]);
    case 'topic':
      var channel = target;
      var topic = rest;
      if (args.isNotEmpty && client.isChannel(args[0])) {
        channel = args[0];
        topic = restAfter(1);
      }
      if (channel == null || !client.isChannel(channel)) {
        return const InputError('Usage: /topic #channel [text]');
      }
      if (topic.isEmpty) {
        client.sendRaw('TOPIC $channel');
      } else {
        client.setTopic(channel, topic);
      }
    case 'whois' || 'wi':
      if (args.isEmpty) return const InputError('Usage: /whois nick');
      client.whois(args[0]);
    case 'list':
      client.list(minUsers: args.isEmpty ? null : int.tryParse(args[0]));
    case 'mode':
      var channel = target;
      var from = 0;
      if (args.isNotEmpty && client.isChannel(args[0])) {
        channel = args[0];
        from = 1;
      }
      if (channel == null || !client.isChannel(channel)) {
        return const InputError('Usage: /mode #channel +modes [args]');
      }
      if (args.length <= from) {
        client.requestModes(channel);
      } else {
        client.setModes(channel, args[from], args.sublist(from + 1));
      }
    case 'invite':
      final channel = args.length > 1 ? args[1] : target;
      if (args.isEmpty || channel == null || !client.isChannel(channel)) {
        return const InputError('Usage: /invite nick #channel');
      }
      client.invite(args[0], channel);
    case 'kick' || 'k':
      if (args.isEmpty || target == null || !client.isChannel(target)) {
        return const InputError('Usage (in a room): /kick nick [reason]');
      }
      client.kick(target, args[0], reason: restAfter(1));
    case 'ban':
      if (args.isEmpty || target == null || !client.isChannel(target)) {
        return const InputError('Usage (in a room): /ban nick');
      }
      client.ban(target, args[0]);
    case 'op' || 'deop' || 'voice' || 'devoice':
      if (args.isEmpty || target == null || !client.isChannel(target)) {
        return InputError('Usage (in a room): /$command nick');
      }
      final mode = command.endsWith('op') ? 'o' : 'v';
      final sign = command.startsWith('de') ? '-' : '+';
      client.setModes(target, '$sign${mode * args.length}', args);
    case 'quote' || 'raw':
      if (rest.isEmpty) return const InputError('Usage: /quote RAW LINE');
      client.sendRaw(rest);
    case 'quit' || 'disconnect':
      unawaited(client.disconnect(rest.isEmpty ? 'Leaving' : rest));
    default:
      return InputError('Unknown command /$command. Type /help for a list.');
  }
  return const InputSent();
}
