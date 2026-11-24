import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheet, CupertinoAlertDialog;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/ui/adaptive.dart';
import 'package:material_ui/material_ui.dart';

/// A button that opens [open] with its context and the tap position.
Widget _host(
  TargetPlatform platform,
  Future<void> Function(BuildContext, Offset) open,
) => MaterialApp(
  theme: ThemeData(platform: platform),
  home: Scaffold(
    body: Center(
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => open(context, d.globalPosition),
          onSecondaryTapUp: (d) => open(context, d.globalPosition),
          child: const SizedBox(width: 100, height: 50, child: Text('open')),
        ),
      ),
    ),
  ),
);

void main() {
  final picked = <String>[];
  setUp(picked.clear);

  List<MenuAction> actions() => [
    MenuAction(
      icon: Icons.reply,
      label: 'Reply',
      onSelected: () => picked.add('reply'),
    ),
    MenuAction(
      icon: Icons.logout,
      label: 'Leave',
      destructive: true,
      onSelected: () => picked.add('leave'),
    ),
  ];

  testWidgets('iPhone: an iOS action sheet with Cancel', (tester) async {
    await tester.pumpWidget(
      _host(
        TargetPlatform.iOS,
        (context, _) =>
            showActionMenu(context, title: '#chat', actions: actions()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('#chat'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(picked, ['leave']);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, ['leave']);
  });

  testWidgets('Mac: right-click opens a context menu at the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TargetPlatform.macOS,
        (context, at) =>
            showActionMenu(context, actions: actions(), position: at),
      ),
    );
    await tester.tap(find.text('open'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<MenuAction>), findsNWidgets(2));
    expect(find.byType(BottomSheet), findsNothing);
    // Next to the pointer, not at the bottom of the window.
    final menuTop = tester.getTopLeft(find.text('Reply')).dy;
    expect(menuTop, lessThan(tester.getCenter(find.text('open')).dy + 60));
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(picked, ['reply']);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('${platform.name}: right-click opens a menu at the pointer', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          platform,
          (context, at) =>
              showActionMenu(context, actions: actions(), position: at),
        ),
      );
      await tester.tap(find.text('open'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<MenuAction>), findsNWidgets(2));
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(picked, ['leave']);
    });
  }

  test('desktop platforms', () {
    expect(isDesktopPlatform(TargetPlatform.macOS), isTrue);
    expect(isDesktopPlatform(TargetPlatform.windows), isTrue);
    expect(isDesktopPlatform(TargetPlatform.linux), isTrue);
    expect(isDesktopPlatform(TargetPlatform.iOS), isFalse);
    expect(isDesktopPlatform(TargetPlatform.android), isFalse);
  });

  testWidgets('Android: a Material bottom sheet', (tester) async {
    await tester.pumpWidget(
      _host(
        TargetPlatform.android,
        (context, _) => showActionMenu(context, actions: actions()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(find.widgetWithIcon(ListTile, Icons.reply), findsOneWidget);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(picked, ['reply']);
  });

  for (final (platform, cupertino) in [
    (TargetPlatform.iOS, true),
    (TargetPlatform.macOS, true),
    (TargetPlatform.android, false),
    (TargetPlatform.windows, false),
    (TargetPlatform.linux, false),
  ]) {
    testWidgets('confirm on ${platform.name}', (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host(platform, (context, _) async {
          result = await confirmAction(
            context,
            title: 'Delete saved history?',
            message: 'It cannot be undone.',
            confirmLabel: 'Delete',
            destructive: true,
          );
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byType(CupertinoAlertDialog),
        cupertino ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  }
}
