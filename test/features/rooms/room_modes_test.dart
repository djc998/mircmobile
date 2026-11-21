import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/core/irc/services.dart';
import 'package:irc_client/features/rooms/domain/room_modes.dart';

void main() {
  group('modeChange', () {
    test('turns settings into one MODE change', () {
      final change = modeChange(
        current: {'n', 't'},
        currentKey: null,
        wanted: const RoomSettings(
          inviteOnly: true,
          secret: true,
          topicLocked: true,
          password: 'pw',
        ),
      );
      expect(change?.modes, '+isk');
      expect(change?.args, ['pw']);
    });

    test('removes and replaces a password', () {
      final removed = modeChange(
        current: {'i'},
        currentKey: 'old',
        wanted: const RoomSettings(inviteOnly: false, password: ''),
      );
      expect(removed?.modes, '-ik');
      expect(removed?.args, ['old']);
      final replaced = modeChange(
        current: {},
        currentKey: 'old',
        wanted: const RoomSettings(password: 'new'),
      );
      expect(replaced?.modes, '-k+k');
      expect(replaced?.args, ['old', 'new']);
    });

    test('no change gives null', () {
      expect(
        modeChange(
          current: {'i'},
          currentKey: 'pw',
          wanted: const RoomSettings(inviteOnly: true, password: 'pw'),
        ),
        isNull,
      );
    });
  });

  test('describes mode changes in words and hides passwords', () {
    expect(
      describeModeChange('+isk secret'),
      'invite only on, hidden from the room list on, password set',
    );
    expect(describeModeChange('-t+o bob'), contains('gave operator to bob'));
    expect(describeModeChange('+l 10'), 'user limit 10');
  });

  group('services', () {
    test('standard networks register by message', () {
      const s = NetworkServices(ServicesKind.standard);
      expect(s.registerNick('pw', 'a@b.c'), (
        target: 'NickServ',
        text: 'REGISTER pw a@b.c',
      ));
      expect(s.registerRoom('#mine'), (
        target: 'ChanServ',
        text: 'REGISTER #mine',
      ));
      expect(s.roomLimitation, isNull);
    });

    test('DALnet uses full service addresses and a room password', () {
      final s = NetworkServices(servicesFor('irc.dal.net'));
      expect(s.roomNeedsPassword, isTrue);
      expect(
        s.registerRoom('#mine', password: 'rpw').target,
        'ChanServ@services.dal.net',
      );
      expect(
        s.registerRoom('#mine', password: 'rpw').text,
        startsWith('REGISTER #mine rpw '),
      );
    });

    test('EFnet and Undernet explain why rooms cannot be kept', () {
      expect(
        NetworkServices(servicesFor('irc.efnet.org')).canRegisterRoom,
        isFalse,
      );
      expect(
        NetworkServices(servicesFor('irc.undernet.org')).roomLimitation,
        contains('cservice.undernet.org'),
      );
    });
  });
}
