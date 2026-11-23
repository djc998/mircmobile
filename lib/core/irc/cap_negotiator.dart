/// IRCv3 capability negotiation (CAP LS 302) and SASL PLAIN.
library;

import 'dart:convert';

import 'package:irc_client/core/irc/irc_message.dart';

/// Account credentials for SASL PLAIN.
class SaslCredentials {
  const SaslCredentials({required this.account, required this.password});

  final String account;
  final String password;
}

/// Outcome of SASL authentication.
enum SaslOutcome { notAttempted, success, failed, unavailable }

/// Capabilities the client asks for when the server offers them.
const Set<String> defaultWantedCaps = {
  'server-time',
  'message-tags',
  'multi-prefix',
  'away-notify',
  'account-notify',
  'extended-join',
  'echo-message',
  'cap-notify',
  'userhost-in-names',
  'batch',
  // Missed and older messages from servers and bouncers that keep them
  // (Ergo, soju). The draft name is what servers ship today.
  'draft/chathistory',
  'chathistory',
};

/// Drives the CAP/SASL exchange during registration.
///
/// It is a pure state machine: feed it messages with [handle] and it writes
/// replies through the `send` callback, which makes it easy to unit test.
class CapNegotiator {
  CapNegotiator({
    required this._send,
    this.wanted = defaultWantedCaps,
    this.sasl,
    this.onFinished,
  });

  final void Function(String line) _send;
  final Set<String> wanted;
  final SaslCredentials? sasl;

  /// Called once with the result when negotiation ends with CAP END.
  final void Function(SaslOutcome outcome)? onFinished;

  /// Capabilities the server advertised, with their values.
  final Map<String, String> available = {};

  /// Capabilities the server acknowledged.
  final Set<String> enabled = {};

  SaslOutcome saslOutcome = SaslOutcome.notAttempted;
  bool _finished = false;
  bool _started = false;
  int _pendingReqs = 0;

  /// Whether CAP END has been sent.
  bool get isFinished => _finished;

  /// Sends `CAP LS 302`. Call before NICK/USER.
  void start() {
    _started = true;
    _send('CAP LS 302');
  }

  /// Handles a message. Returns true when it belonged to the negotiation.
  bool handle(IrcMessage m) {
    switch (m.command) {
      case 'CAP':
        _handleCap(m);
        return true;
      case 'AUTHENTICATE':
        _handleAuthenticate(m);
        return true;
      case '900': // RPL_LOGGEDIN
        return true;
      case '903': // RPL_SASLSUCCESS
        saslOutcome = SaslOutcome.success;
        _end();
        return true;
      case '908': // RPL_SASLMECHS, informational; 904 follows.
        return true;
      case '902' || '904' || '905' || '906' || '907':
        if (saslOutcome != SaslOutcome.success) {
          saslOutcome = SaslOutcome.failed;
        }
        _end();
        return true;
      case '410' || '421' when !_finished && _started:
        // Invalid CAP subcommand, or a server without CAP support at all.
        if (m.param(1) == 'CAP' || m.command == '410') {
          _end();
          return true;
        }
        return false;
      case '001':
        // Some servers never answer CAP; registration completing ends it.
        _finished = true;
        return false;
    }
    return false;
  }

  void _handleCap(IrcMessage m) {
    final sub = m.param(1)?.toUpperCase();
    switch (sub) {
      case 'LS':
        final more = m.params.length > 3 && m.params[2] == '*';
        _addAvailable(m.trailing ?? '');
        if (!more && !_finished) _requestCaps();
      case 'ACK':
        _pendingReqs = _pendingReqs > 0 ? _pendingReqs - 1 : 0;
        for (final cap in _split(m.trailing ?? '')) {
          if (cap.startsWith('-')) {
            enabled.remove(cap.substring(1));
          } else {
            enabled.add(cap);
          }
        }
        if (_pendingReqs == 0 && !_finished) _afterAck();
      case 'NAK':
        _pendingReqs = _pendingReqs > 0 ? _pendingReqs - 1 : 0;
        if (_pendingReqs == 0 && !_finished) _afterAck();
      case 'NEW':
        _addAvailable(m.trailing ?? '');
        if (_finished) {
          final extra = wanted
              .where((c) => available.containsKey(c) && !enabled.contains(c))
              .toList();
          if (extra.isNotEmpty) _send('CAP REQ :${extra.join(' ')}');
        }
      case 'DEL':
        for (final cap in _split(m.trailing ?? '')) {
          available.remove(cap);
          enabled.remove(cap);
        }
    }
  }

  void _addAvailable(String list) {
    for (final token in _split(list)) {
      final eq = token.indexOf('=');
      if (eq == -1) {
        available[token] = '';
      } else {
        available[token.substring(0, eq)] = token.substring(eq + 1);
      }
    }
  }

  bool get _canSasl {
    if (sasl == null || !available.containsKey('sasl')) return false;
    final mechs = available['sasl']!;
    return mechs.isEmpty || mechs.split(',').contains('PLAIN');
  }

  void _requestCaps() {
    final req = wanted.where(available.containsKey).toList();
    if (_canSasl) {
      req.add('sasl');
    } else if (sasl != null) {
      saslOutcome = SaslOutcome.unavailable;
    }
    if (req.isEmpty) {
      _end();
      return;
    }
    // Keep each REQ line well under the 512-byte limit.
    final batches = <List<String>>[[]];
    var length = 0;
    for (final cap in req) {
      if (length + cap.length + 1 > 400) {
        batches.add([]);
        length = 0;
      }
      batches.last.add(cap);
      length += cap.length + 1;
    }
    _pendingReqs = batches.length;
    for (final batch in batches) {
      _send('CAP REQ :${batch.join(' ')}');
    }
  }

  void _afterAck() {
    if (sasl != null && enabled.contains('sasl')) {
      _send('AUTHENTICATE PLAIN');
    } else {
      if (sasl != null && saslOutcome == SaslOutcome.notAttempted) {
        saslOutcome = SaslOutcome.unavailable;
      }
      _end();
    }
  }

  void _handleAuthenticate(IrcMessage m) {
    final creds = sasl;
    if (creds == null || m.param(0) != '+') return;
    final payload = base64.encode(
      utf8.encode(
        '${creds.account}\u0000${creds.account}\u0000'
        '${creds.password}',
      ),
    );
    for (final chunk in saslChunks(payload)) {
      _send('AUTHENTICATE $chunk');
    }
  }

  /// Splits a base64 SASL payload into 400-byte AUTHENTICATE chunks.
  ///
  /// A payload whose length is an exact multiple of 400 is followed by `+`,
  /// as the IRCv3 SASL spec requires.
  static List<String> saslChunks(String payload) {
    if (payload.isEmpty) return ['+'];
    final chunks = <String>[];
    for (var i = 0; i < payload.length; i += 400) {
      chunks.add(
        payload.substring(
          i,
          i + 400 > payload.length ? payload.length : i + 400,
        ),
      );
    }
    if (payload.length % 400 == 0) chunks.add('+');
    return chunks;
  }

  void _end() {
    if (_finished) return;
    _finished = true;
    _send('CAP END');
    onFinished?.call(saslOutcome);
  }

  static Iterable<String> _split(String s) =>
      s.split(' ').where((t) => t.isNotEmpty);
}
