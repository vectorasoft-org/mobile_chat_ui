import 'package:flutter/material.dart';

/// Theme configuration for the chat module
/// All colors are customizable via presets or direct instantiation
class ChatTheme {
  // ===== PRIMARY COLORS =====
  final Color primaryColor;
  final Color secondaryColor;

  // ===== MESSAGE STYLING =====
  final Color messageSentBackground;
  final Color messageSentText;
  final Color messageReceivedBackground;
  final Color messageReceivedText;
  final Color messageReceivedAvatarBackground;
  final Color messageSenderName;
  final Color messageTimestamp;
  final Color messageDeletedBackground;
  final Color messageDeletedText;

  // ===== INPUT AREA =====
  final Color inputBackground;
  final Color inputBorder;
  final Color inputBorderFocused;
  final Color inputText;
  final Color inputHint;
  final Color inputIcon;

  // ===== RECORDING / VOICE =====
  final Color recordButtonBackground;
  final Color recordButtonIconColor;
  final Color recordDeleteZoneBackground;
  final Color recordDeleteZoneIcon;
  final Color recordLabelNearZone;
  final Color recordLabelFarZone;
  final Color recordWaveformColor;
  final Color recordMeterBackground;

  // ===== VOLUME METER LEVELS =====
  final Color volumeLowColor; // Green
  final Color volumeMediumColor; // Yellow
  final Color volumeHighColor; // Red

  // ===== AUDIO PLAYER =====
  final Color audioPlayerSentBackground;
  final Color audioPlayerReceivedBackground;
  final Color audioPlayerIconColor;
  final Color audioPlayerSentProgressBar;
  final Color audioPlayerReceivedProgressBar;
  final Color audioPlayerSentTextColor;
  final Color audioPlayerReceivedTextColor;
  final Color audioPlayerProgressTrack;

  // ===== VIDEO PLAYER =====
  final Color videoControlBackground;
  final Color videoControlIcon;
  final Color videoProgressBar;
  final Color videoProgressTrack;
  final Color videoOverlay;

  // ===== UI ELEMENTS =====
  final Color dividerColor;
  final Color borderColor;
  final Color buttonBackground;
  final Color buttonIcon;
  final Color backgroundColor;

  // ===== TEXT & STATES =====
  final Color textPrimary;
  final Color textSecondary;
  final Color errorColor;
  final Color warningColor;
  final Color disabledColor;

  // ===== LEGACY (kept for backward compatibility) =====
  final Color greyTone;
  final Color videoSliderColor;

  const ChatTheme({
    required this.primaryColor,
    required this.secondaryColor,
    // Message styling
    this.messageSentBackground = const Color(0xFFEC1D27),
    this.messageSentText = Colors.white,
    this.messageReceivedBackground = const Color(0xFFF0F0F0),
    this.messageReceivedText = Colors.black87,
    this.messageReceivedAvatarBackground = const Color(0xFFE0E0E0),
    this.messageSenderName = const Color(0xFF666666),
    this.messageTimestamp = const Color(0xFF999999),
    this.messageDeletedBackground = const Color(0xFFF5F5F5),
    this.messageDeletedText = const Color(0xFF999999),
    // Input area
    this.inputBackground = Colors.white,
    this.inputBorder = const Color(0xFFDDDDDD),
    this.inputBorderFocused = const Color(0xFFEC1D27),
    this.inputText = Colors.black87,
    this.inputHint = const Color(0xFF999999),
    this.inputIcon = const Color(0xFF666666),
    // Recording / Voice
    this.recordButtonBackground = const Color(0xFFEC1D27),
    this.recordButtonIconColor = const Color(0xFFEC1D27),
    this.recordDeleteZoneBackground = const Color(0xFFFFEBEE),
    this.recordDeleteZoneIcon = const Color(0xFFEC1D27),
    this.recordLabelNearZone = const Color(0xFF999999),
    this.recordLabelFarZone = Colors.white,
    this.recordWaveformColor = const Color(0xFFEC1D27),
    this.recordMeterBackground = Colors.white,
    // Volume meter
    this.volumeLowColor = Colors.green,
    this.volumeMediumColor = const Color(0xFFFBC02D),
    this.volumeHighColor = Colors.red,
    // Audio player
    this.audioPlayerSentBackground = const Color(0xFFEC1D27),
    this.audioPlayerReceivedBackground = Colors.white,
    this.audioPlayerIconColor = const Color(0xFFEC1D27),
    this.audioPlayerSentProgressBar = Colors.white,
    this.audioPlayerReceivedProgressBar = const Color(0xFFEC1D27),
    this.audioPlayerSentTextColor = Colors.white,
    this.audioPlayerReceivedTextColor = Colors.black87,
    this.audioPlayerProgressTrack = const Color(0xCCBBBBBB),
    // Video player
    this.videoControlBackground = Colors.black87,
    this.videoControlIcon = Colors.white,
    this.videoProgressBar = const Color(0xFF0084FF),
    this.videoProgressTrack = const Color(0xFF999999),
    this.videoOverlay = const Color(0x88000000),
    // UI elements
    this.dividerColor = const Color(0xFFE0E0E0),
    this.borderColor = const Color(0xFFDDDDDD),
    this.buttonBackground = const Color(0xFFEC1D27),
    this.buttonIcon = const Color(0xFFEC1D27),
    this.backgroundColor = Colors.white,
    // Text & states
    this.textPrimary = Colors.black87,
    this.textSecondary = const Color(0xFF999999),
    this.errorColor = Colors.red,
    this.warningColor = const Color(0xFFFBC02D),
    this.disabledColor = const Color(0xFFBDBDBD),
    // Legacy
    this.greyTone = const Color(0xFF999999),
    this.videoSliderColor = const Color(0xFF0084FF),
  });

  /// Factory constructor for houExpress default theme (red)
  factory ChatTheme.houExpress() {
    const primaryRed = Color(0xFFEC1D27);
    const lightGrey = Color(0xFFF0F0F0);
    return ChatTheme(
      primaryColor: primaryRed,
      secondaryColor: lightGrey,
      messageSentBackground: primaryRed,
      messageSentText: Colors.white,
      messageReceivedBackground: lightGrey,
      messageReceivedText: Colors.black87,
      recordButtonBackground: primaryRed,
      recordButtonIconColor: primaryRed,
      recordDeleteZoneIcon: primaryRed,
      audioPlayerSentBackground: primaryRed,
      audioPlayerIconColor: primaryRed,
      audioPlayerSentProgressBar: Colors.white,
      audioPlayerReceivedProgressBar: const Color(0xFFEC1D27),
      audioPlayerSentTextColor: Colors.white,
      audioPlayerReceivedTextColor: Colors.black87,
      inputBorderFocused: primaryRed,
      buttonBackground: primaryRed,
      buttonIcon: primaryRed,
      errorColor: primaryRed,
      recordLabelNearZone: const Color(0xFF999999),
      recordLabelFarZone: Colors.white,
      videoSliderColor: const Color(0xFF0084FF),
    );
  }

  /// Factory constructor for a blue theme
  factory ChatTheme.blue() {
    const primaryBlue = Color(0xFF0084FF);
    const lightGrey = Color(0xFFF0F0F0);
    return ChatTheme(
      primaryColor: primaryBlue,
      secondaryColor: lightGrey,
      messageSentBackground: primaryBlue,
      messageSentText: Colors.white,
      messageReceivedBackground: lightGrey,
      messageReceivedText: Colors.black87,
      recordButtonBackground: primaryBlue,
      recordButtonIconColor: primaryBlue,
      recordDeleteZoneIcon: primaryBlue,
      audioPlayerSentBackground: primaryBlue,
      audioPlayerIconColor: primaryBlue,
      audioPlayerSentProgressBar: Colors.white,
      audioPlayerReceivedProgressBar: primaryBlue,
      audioPlayerSentTextColor: Colors.white,
      audioPlayerReceivedTextColor: Colors.black87,
      inputBorderFocused: primaryBlue,
      buttonBackground: primaryBlue,
      buttonIcon: primaryBlue,
      errorColor: Colors.red,
      recordLabelNearZone: const Color(0xFF999999),
      recordLabelFarZone: Colors.white,
      videoSliderColor: primaryBlue,
    );
  }

  /// Factory constructor for a green theme
  factory ChatTheme.green() {
    const primaryGreen = Color(0xFF34A853);
    const lightGrey = Color(0xFFF0F0F0);
    return ChatTheme(
      primaryColor: primaryGreen,
      secondaryColor: lightGrey,
      messageSentBackground: primaryGreen,
      messageSentText: Colors.white,
      messageReceivedBackground: lightGrey,
      messageReceivedText: Colors.black87,
      recordButtonBackground: primaryGreen,
      recordButtonIconColor: primaryGreen,
      recordDeleteZoneIcon: primaryGreen,
      audioPlayerSentBackground: primaryGreen,
      audioPlayerIconColor: primaryGreen,
      audioPlayerSentProgressBar: Colors.white,
      audioPlayerReceivedProgressBar: primaryGreen,
      audioPlayerSentTextColor: Colors.white,
      audioPlayerReceivedTextColor: Colors.black87,
      inputBorderFocused: primaryGreen,
      buttonBackground: primaryGreen,
      buttonIcon: primaryGreen,
      errorColor: Colors.red,
      videoSliderColor: primaryGreen,
      recordLabelNearZone: const Color(0xFF999999),
      recordLabelFarZone: Colors.white,
    );
  }

  /// Create a copy of this theme with potentially updated properties
  ChatTheme copyWith({
    Color? primaryColor,
    Color? secondaryColor,
    Color? messageSentBackground,
    Color? messageSentText,
    Color? messageReceivedBackground,
    Color? messageReceivedText,
    Color? messageReceivedAvatarBackground,
    Color? messageSenderName,
    Color? messageTimestamp,
    Color? messageDeletedBackground,
    Color? messageDeletedText,
    Color? inputBackground,
    Color? inputBorder,
    Color? inputBorderFocused,
    Color? inputText,
    Color? inputHint,
    Color? inputIcon,
    Color? recordButtonBackground,
    Color? recordButtonIconColor,
    Color? recordDeleteZoneBackground,
    Color? recordDeleteZoneIcon,
    Color? recordWaveformColor,
    Color? recordMeterBackground,
    Color? volumeLowColor,
    Color? volumeMediumColor,
    Color? volumeHighColor,
    Color? audioPlayerSentBackground,
    Color? audioPlayerReceivedBackground,
    Color? audioPlayerIconColor,
    Color? audioPlayerSentProgressBar,
    Color? audioPlayerReceivedProgressBar,
    Color? audioPlayerSentTextColor,
    Color? audioPlayerReceivedTextColor,
    Color? audioPlayerProgressTrack,
    Color? videoControlBackground,
    Color? videoControlIcon,
    Color? videoProgressBar,
    Color? videoProgressTrack,
    Color? videoOverlay,
    Color? dividerColor,
    Color? borderColor,
    Color? buttonBackground,
    Color? buttonIcon,
    Color? backgroundColor,
    Color? textPrimary,
    Color? textSecondary,
    Color? errorColor,
    Color? warningColor,
    Color? disabledColor,
    Color? greyTone,
    Color? videoSliderColor,
  }) {
    return ChatTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      messageSentBackground:
          messageSentBackground ?? this.messageSentBackground,
      messageSentText: messageSentText ?? this.messageSentText,
      messageReceivedBackground:
          messageReceivedBackground ?? this.messageReceivedBackground,
      messageReceivedText: messageReceivedText ?? this.messageReceivedText,
      messageReceivedAvatarBackground:
          messageReceivedAvatarBackground ??
          this.messageReceivedAvatarBackground,
      messageSenderName: messageSenderName ?? this.messageSenderName,
      messageTimestamp: messageTimestamp ?? this.messageTimestamp,
      messageDeletedBackground:
          messageDeletedBackground ?? this.messageDeletedBackground,
      messageDeletedText: messageDeletedText ?? this.messageDeletedText,
      inputBackground: inputBackground ?? this.inputBackground,
      inputBorder: inputBorder ?? this.inputBorder,
      inputBorderFocused: inputBorderFocused ?? this.inputBorderFocused,
      inputText: inputText ?? this.inputText,
      inputHint: inputHint ?? this.inputHint,
      inputIcon: inputIcon ?? this.inputIcon,
      recordButtonBackground:
          recordButtonBackground ?? this.recordButtonBackground,
      recordButtonIconColor:
          recordButtonIconColor ?? this.recordButtonIconColor,
      recordDeleteZoneBackground:
          recordDeleteZoneBackground ?? this.recordDeleteZoneBackground,
      recordDeleteZoneIcon: recordDeleteZoneIcon ?? this.recordDeleteZoneIcon,
      recordWaveformColor: recordWaveformColor ?? this.recordWaveformColor,
      recordMeterBackground:
          recordMeterBackground ?? this.recordMeterBackground,
      volumeLowColor: volumeLowColor ?? this.volumeLowColor,
      volumeMediumColor: volumeMediumColor ?? this.volumeMediumColor,
      volumeHighColor: volumeHighColor ?? this.volumeHighColor,
      audioPlayerSentBackground:
          audioPlayerSentBackground ?? this.audioPlayerSentBackground,
      audioPlayerReceivedBackground:
          audioPlayerReceivedBackground ?? this.audioPlayerReceivedBackground,
      audioPlayerIconColor: audioPlayerIconColor ?? this.audioPlayerIconColor,
      audioPlayerSentProgressBar:
          audioPlayerSentProgressBar ?? this.audioPlayerSentProgressBar,
      audioPlayerReceivedProgressBar:
          audioPlayerReceivedProgressBar ?? this.audioPlayerReceivedProgressBar,
      audioPlayerSentTextColor:
          audioPlayerSentTextColor ?? this.audioPlayerSentTextColor,
      audioPlayerReceivedTextColor:
          audioPlayerReceivedTextColor ?? this.audioPlayerReceivedTextColor,
      videoControlBackground:
          videoControlBackground ?? this.videoControlBackground,
      videoControlIcon: videoControlIcon ?? this.videoControlIcon,
      videoProgressBar: videoProgressBar ?? this.videoProgressBar,
      videoProgressTrack: videoProgressTrack ?? this.videoProgressTrack,
      videoOverlay: videoOverlay ?? this.videoOverlay,
      dividerColor: dividerColor ?? this.dividerColor,
      borderColor: borderColor ?? this.borderColor,
      buttonBackground: buttonBackground ?? this.buttonBackground,
      buttonIcon: buttonIcon ?? this.buttonIcon,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      errorColor: errorColor ?? this.errorColor,
      warningColor: warningColor ?? this.warningColor,
      disabledColor: disabledColor ?? this.disabledColor,
      greyTone: greyTone ?? this.greyTone,
      videoSliderColor: videoSliderColor ?? this.videoSliderColor,
    );
  }

  /// Get a theme-aware white color by blending with primary color
  Color getThemeAwareWhite({double blendStrength = 0.05}) {
    return Color.lerp(Colors.white, primaryColor, blendStrength) ??
        Colors.white;
  }

  /// Get a theme-aware grey color by blending with primary color
  /// [greyShade] is the base grey (e.g., 200, 300, 600)
  Color getThemeAwareGrey(int greyShade, {double blendStrength = 0.03}) {
    final baseGrey = Colors.grey[greyShade] ?? Colors.grey;
    return Color.lerp(baseGrey, primaryColor, blendStrength) ?? baseGrey;
  }

  /// Get a theme-aware divider color
  Color getThemeAwareDividerColor() {
    return getThemeAwareGrey(300, blendStrength: 0.08);
  }

  /// Get a theme-aware secondary text color
  Color getThemeAwareSecondaryText() {
    return getThemeAwareGrey(600, blendStrength: 0.05);
  }

  /// Get a theme-aware message background color (for received messages)
  /// Slightly more tinted than scaffold background
  Color getThemeAwareMessageBackground() {
    return Color.lerp(Colors.white, primaryColor, 0.13) ?? Colors.white;
  }

  /// Get a theme-aware attachment background color (for content inside messages)
  /// More tinted than message background
  Color getThemeAwareAttachmentBackground() {
    return Color.lerp(Colors.white, primaryColor, 0.18) ?? Colors.white;
  }
}
