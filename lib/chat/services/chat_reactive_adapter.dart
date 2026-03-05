import '../config/chat_theme.dart';
import '../models.dart';
import 'chat_service.dart';

abstract class ChatReactiveAdapter {
  ChatService get chatService;

  Stream<ChatTheme> get themeStream;
  ChatTheme get currentTheme;

  Stream<List<Message>> get messagesStream;
  List<Message> get currentMessages;
}
