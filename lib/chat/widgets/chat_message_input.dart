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
    final focused = widget.focusNode.hasFocus;
    // A capsule, not a box: the field reads as one soft surface on the bar and
    // keeps the same rhythm as the controls beside it.
    OutlineInputBorder capsule(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      focusNode: widget.focusNode,
      controller: widget.controller,
      minLines: 1,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      cursorColor: theme.primaryColor,
      cursorWidth: 1.6,
      cursorRadius: const Radius.circular(2),
      style: TextStyle(fontSize: 15.sp, height: 1.35, color: theme.inputText),
      onTapOutside: (_) => widget.onTapOutside(),
      decoration: InputDecoration(
        isDense: true,
        hintText: ChatLocalizations.inputHint(context),
        hintStyle:
            TextStyle(fontSize: 15.sp, height: 1.35, color: theme.inputHint),
        filled: true,
        fillColor: focused ? theme.inputBarBackground : theme.inputFieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 11.0,
        ),
        border: capsule(Colors.transparent, 1),
        enabledBorder: capsule(Colors.transparent, 1),
        focusedBorder: capsule(theme.inputBorderFocused, 1.5),
      ),
    );
  }
}
