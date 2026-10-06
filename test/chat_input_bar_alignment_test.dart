// The composer bar's controls must share one horizontal centre line: the `+`,
// the capsule field and the mic (Sam, 2026-10-06 - the mic sat ~8pt high,
// lifted by a Padding around RecordButtonV2 in a bottom-aligned Row).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vs_chat_flutter/chat/config/chat_logger.dart';
import 'package:vs_chat_flutter/chat/config/chat_theme.dart';
import 'package:vs_chat_flutter/chat/config/chat_theme_provider.dart';
import 'package:vs_chat_flutter/chat/controllers/recording_controller.dart';
import 'package:vs_chat_flutter/chat/widgets/chat_input_actions.dart';
import 'package:vs_chat_flutter/chat/widgets/chat_input_bar.dart';
import 'package:vs_chat_flutter/chat/widgets/chat_input_content.dart';
import 'package:vs_chat_flutter/chat/widgets/record_button_v2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The mic owns an audio recorder; at rest it only needs the plugin to answer.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
  });

  Future<void> pumpBar(WidgetTester tester, {String hint = ''}) async {
    final logger = ConsoleLogger();
    // A phone, as the bar is used (390 x 844 logical, 3x).
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
              body: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ChatInputBar(
                    isRecording: false,
                    recordingController: RecordingController(logger: logger),
                    textController: TextEditingController(text: hint),
                    focusNode: FocusNode(),
                    volumeStream: const Stream.empty(),
                    timerText: '',
                    onPickFile: () {},
                    onPickImage: () {},
                    onTakePhoto: () {},
                    onPickLocation: () {},
                    onTextFocusOut: () {},
                    recordCallbacks: RecordButtonCallbacks(
                      onRecordingComplete: (_, _) {},
                      onRecordingStart: () {},
                      onRecordingCancel: () {},
                    ),
                    getVolumeStream: () => const Stream.empty(),
                    hasPermission: () async => true,
                    requestPermission: () async => true,
                    logger: logger,
                    onSendMessage: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double centreY(WidgetTester tester, Finder f) => tester.getCenter(f).dy;

  testWidgets('+, field and mic share one centre line', (tester) async {
    await pumpBar(tester);
    final plus = centreY(tester, find.byType(ChatInputActions));
    final field = centreY(tester, find.byType(TextField));
    final mic = centreY(tester, find.byType(RecordButtonV2));
    expect((mic - plus).abs(), lessThan(1.0), reason: 'mic $mic vs + $plus');
    expect((field - plus).abs(), lessThan(1.0), reason: 'field $field vs + $plus');
    // The mic is the 6%-larger glyph.
    final micIcon = tester.widget<Icon>(find.descendant(of: find.byType(RecordButtonV2), matching: find.byIcon(Icons.mic)));
    expect(micIcon.size, closeTo(ChatInputMetrics.icon * 1.06, 0.001));
  });

  testWidgets('send button sits on the same line once there is text', (tester) async {
    await pumpBar(tester, hint: 'សួស្តី');
    final plus = centreY(tester, find.byType(ChatInputActions));
    final send = centreY(tester, find.byType(ChatInputSendButton));
    expect((send - plus).abs(), lessThan(1.0), reason: 'send $send vs + $plus');
  });
}
