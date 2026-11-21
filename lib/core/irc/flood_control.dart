/// Outgoing rate limiting so the server doesn't disconnect us for flooding.
library;

import 'dart:async';
import 'dart:collection';

/// A token bucket: up to [burst] lines go out immediately, then one line
/// every [interval].
class FloodControl {
  FloodControl({
    required this.write,
    this.burst = 5,
    this.interval = const Duration(milliseconds: 1500),
  }) : _tokens = burst.toDouble();

  final void Function(String line) write;
  final int burst;
  final Duration interval;

  final Queue<String> _queue = Queue();
  final Stopwatch _clock = Stopwatch()..start();
  double _tokens;
  Duration _last = Duration.zero;
  Timer? _timer;

  /// Lines waiting to be sent.
  int get pending => _queue.length;

  void send(String line) {
    _queue.add(line);
    _drain();
  }

  /// Sends a line right away, ahead of the queue (used for PONG and QUIT).
  void sendNow(String line) => write(line);

  void _refill() {
    if (interval == Duration.zero) {
      _tokens = burst.toDouble();
      return;
    }
    final now = _clock.elapsed;
    final gained = (now - _last).inMicroseconds / interval.inMicroseconds;
    _last = now;
    _tokens = (_tokens + gained).clamp(0, burst.toDouble());
  }

  void _drain() {
    _refill();
    while (_queue.isNotEmpty && _tokens >= 1) {
      _tokens -= 1;
      write(_queue.removeFirst());
    }
    if (_queue.isNotEmpty && _timer == null) {
      final waitUs = ((1 - _tokens) * interval.inMicroseconds).ceil();
      _timer = Timer(Duration(microseconds: waitUs), () {
        _timer = null;
        _drain();
      });
    }
  }

  /// Drops queued lines, e.g. on disconnect.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _tokens = burst.toDouble();
    _last = _clock.elapsed;
  }
}
