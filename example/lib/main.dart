import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vs_chat_flutter/vs_chat_flutter.dart';

/// vs_chat_flutter in VISITOR mode: a public app with NO backend of its own.
///
/// The app ships only chat-service's address and the app's PUBLISHABLE key
/// (from DMS: Chat Topics -> Website Chat). The widget asks nothing about who
/// the visitor is; this app's own "Tell us who you are" form shows the light
/// registration an app may add, whenever it likes, with VSChat.identify().
///
/// Run against a local chat-service:
///   flutter run --dart-define=CHAT_BASE=http://127.0.0.1:3010 --dart-define=CHAT_KEY=pk_...
const chatBase = String.fromEnvironment('CHAT_BASE', defaultValue: 'http://127.0.0.1:3010');
const chatKey = String.fromEnvironment('CHAT_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  VSChat.init(
    VSChatOptions.visitor(
      baseUrl: chatBase,
      key: chatKey,
      // Persistent: the visitor's id + secret must survive a restart.
      storage: SharedPreferencesAdapter(prefs),
      theme: ChatTheme.brand(const Color(0xFFEC1D27)),
      strings: const {
        'en': {'title': 'Chat with us'},
      },
    ),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  // The chat room sizes itself with flutter_screenutil: the app must wrap it.
  Widget build(BuildContext context) => ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, _) => MaterialApp(
          title: 'Example Shop',
          theme: ThemeData(colorSchemeSeed: const Color(0xFFEC1D27), useMaterial3: true),
          home: const HomePage(),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _name = TextEditingController();
  final _contact = TextEditingController();
  String _status = '';

  Future<void> _identify() async {
    final contact = _contact.text.trim();
    try {
      final labels = await VSChat.identify(
        name: _name.text,
        email: contact.contains('@') ? contact : null,
        phone: contact.contains('@') ? null : contact,
      );
      setState(() => _status = labels == null
          ? 'Kept for your first chat.'
          : 'Thanks - your chat now shows who you are.');
    } catch (e) {
      setState(() => _status = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Example Shop')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'A plain app with no backend. The Chat button below opens the widget: no sign-in, no form.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const VSChatWidget()))
                  .then((_) => setState(() {})),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat with us'),
            ),
            const SizedBox(height: 32),
            const Text('Tell us who you are (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'This app decides whether and when to ask. The widget never does.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 8),
            TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Phone or email')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _identify, child: const Text('Use this for my chat')),
            if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status)),
            const SizedBox(height: 24),
            Text('Visitor: ${VSChat.visitorId ?? '(none yet)'}',
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ],
        ),
      );
}
