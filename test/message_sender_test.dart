// A received message says who sent it BEFORE its text: avatar and name on the
// first bubble of a run, the role as a chip when the room has roles, and
// nothing on the reader's own messages (Sam, 2026-11-10 - a driver's and a
// staff member's bubbles looked the same, the name trailing under the run).
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vs_chat_flutter/chat/config/chat_sender_roles.dart';
import 'package:vs_chat_flutter/chat/config/chat_theme.dart';
import 'package:vs_chat_flutter/chat/config/chat_theme_provider.dart';
import 'package:vs_chat_flutter/chat/message_bubble.dart';
import 'package:vs_chat_flutter/chat/models.dart';

void main() {
  Future<void> pumpBubble(
    WidgetTester tester, {
    MessageSender? sender,
    bool startsRun = true,
    bool seen = false,
    bool sending = false,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: ChatThemeProvider(
            theme: ChatTheme.houExpress(),
            child: Scaffold(
              body: MessageBubble(
                message: Message(
                  id: '1',
                  sender: 'driver-71',
                  text: 'Yes. let me try',
                  createdAt: DateTime(2026, 11, 10, 9, 5).toIso8601String(),
                  isSending: sending,
                ),
                isSelf: sender == null,
                startsRun: startsRun,
                sender: sender,
                seen: seen,
                onAttachmentTap: (_, _) async {},
                buildAttachmentWidget: (_, _, _) => const SizedBox(),
                onAttachmentLongPress: (_, _, _) {},
                onMessageLongPress: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  const pat = MessageSender(name: 'Pat', color: Color(0xFFB45309), role: 'Driver');

  testWidgets('name and role sit above the text, avatar beside it', (tester) async {
    await pumpBubble(tester, sender: pat);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('P'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Pat')).dy,
      lessThan(tester.getTopLeft(find.text('Yes. let me try')).dy),
    );
    expect(
      tester.getTopLeft(find.text('P')).dx,
      lessThan(tester.getTopLeft(find.text('Pat')).dx),
    );
  });

  testWidgets('a sender without a role shows no chip', (tester) async {
    await pumpBubble(
      tester,
      sender: const MessageSender(name: 'Pat', color: Color(0xFF2563EB)),
    );
    expect(find.text('Pat'), findsOneWidget);
    expect(find.text('Driver'), findsNothing);
  });

  testWidgets('later messages of a run keep the gutter, not the name', (tester) async {
    await pumpBubble(tester, sender: pat, startsRun: false);
    expect(find.text('Pat'), findsNothing);
    expect(find.text('P'), findsNothing);
    expect(tester.getTopLeft(find.text('Yes. let me try')).dx, greaterThan(28));
  });

  testWidgets('own messages carry no sender', (tester) async {
    await pumpBubble(tester);
    expect(find.text('Pat'), findsNothing);
  });

  // Same three states as the web widget: clock, one tick, two ticks.
  testWidgets('own message: clock while sending, one tick sent, two seen', (tester) async {
    await pumpBubble(tester, sending: true);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    await pumpBubble(tester);
    expect(find.byIcon(Icons.done), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    await pumpBubble(tester, seen: true);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
  });

  testWidgets('a received message shows its time and no tick', (tester) async {
    await pumpBubble(tester, sender: pat);
    expect(find.text('09:05'), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
  });

  test('roles colour by role when shown, by person when hidden', () {
    const roles = ChatSenderRoles(colors: {'driver': Color(0xFFB45309)});
    expect(roles.colorOf('driver-71', 'Driver'), const Color(0xFFB45309));
    expect(roles.colorOf('driver-71', 'driver'), roles.colorOf('driver-99', 'driver'));
    expect(roles.keyOf(null), '');
    const hidden = ChatSenderRoles.hidden();
    expect(hidden.keyOf('driver'), '');
    expect(hidden.colorOf('a-1', 'driver'), hidden.colorOf('a-1', null));
  });
}
