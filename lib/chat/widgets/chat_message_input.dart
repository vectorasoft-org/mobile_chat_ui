import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../config/chat_theme_provider.dart';
import '../services/chat_localizations.dart';

class ChatMessageInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTapOutside;

  const ChatMessageInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onTapOutside,
  });

  @override
  State<ChatMessageInput> createState() => _ChatMessageInputState();
}

class _ChatMessageInputState extends State<ChatMessageInput> {
  late FocusNode _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = widget.focusNode;
    _internalFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _internalFocusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return TextField(
      focusNode: widget.focusNode,
      controller: widget.controller,
      minLines: 1,
      maxLines: 5,
      style: TextStyle(fontSize: 16.sp, color: theme.inputText),
      onTapOutside: (_) => widget.onTapOutside(),
      decoration: InputDecoration(
        hintText: ChatLocalizations.inputHint(context),
        hintStyle: TextStyle(fontSize: 15.sp, color: theme.inputHint),
        filled: true,
        fillColor: theme.inputBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12.0,
          vertical: 19.85,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: theme.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: theme.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: theme.inputBorderFocused),
        ),
      ),
    );
  }
}
