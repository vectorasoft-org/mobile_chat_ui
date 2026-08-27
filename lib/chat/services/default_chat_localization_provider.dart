import 'package:flutter/widgets.dart';
import 'package:vs_chat_flutter/chat/services/localization_provider.dart';

class DefaultChatLocalizationProvider implements ChatLocalizationProvider {
  @override
  String getString(String key, BuildContext context) {
    return key;
  }
}
