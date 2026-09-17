import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/profile_image.dart';
import '../config/chat_config.dart';
import '../config/chat_service_listener.dart';
import '../config/chat_theme.dart';
import '../services/chat_localizations.dart';
import '../services/chat_service.dart';
import '../services/audio_cache_service.dart';

class ChatChannelInfoPage extends StatefulWidget {
  final String channelId;
  final ChatService chatService;
  final ChatConfig chatConfig;

  const ChatChannelInfoPage({
    super.key,
    required this.channelId,
    required this.chatService,
    required this.chatConfig,
  });

  @override
  State<ChatChannelInfoPage> createState() => _ChatChannelInfoPageState();
}

class _ChatChannelInfoPageState extends State<ChatChannelInfoPage> {
  late final ChatService _chatService = widget.chatService;
  late final ChatConfig _chatConfig = widget.chatConfig;
  late final ChatServiceListener _serviceListener;

  ChatConfig get chatConfig => _chatConfig;

  String _channelName = 'Loading...';
  String _currentUserName = 'Unknown';
  String _currentUserCode = 'Unknown ID';
  String? _userAvatarUrl;

  @override
  void initState() {
    super.initState();
    // Initialize from cached service data (loaded once in ChatPage)
    _channelName = _chatService.getCachedChannelName();
    _currentUserCode = _chatService.getCachedUserCode();
    _currentUserName = _chatService.getCachedUserName();
    _userAvatarUrl = _chatService.getCachedUserAvatarUrl();

    _serviceListener = _ChatChannelInfoServiceListener(
      handleThemeChanged: (_) {
        if (mounted) {
          setState(() {});
        }
      },
      handleChannelNameChanged: (channelName) {
        if (mounted) {
          setState(() {
            _channelName = channelName;
          });
        }
      },
      handleUserDataChanged:
          ({
            required String userName,
            required String userCode,
            required String? userAvatarUrl,
          }) {
            if (mounted) {
              setState(() {
                _currentUserName = userName;
                _currentUserCode = userCode;
                _userAvatarUrl = userAvatarUrl;
              });
            }
          },
    );
    _chatService.addListener(_serviceListener);

    // Load theme after first frame to avoid build errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedTheme();
    });
  }

  @override
  void dispose() {
    _chatService.removeListener(_serviceListener);
    super.dispose();
  }

  void _loadSavedTheme() {
    try {
      final themeJson = _chatConfig.storage.getString(_chatConfig.themeKey);
      if (themeJson != null && themeJson.isNotEmpty) {
        final themeData = jsonDecode(themeJson) as Map<String, dynamic>;
        final color = themeData['color'] as String?;

        ChatTheme theme;
        switch (color) {
          case 'blue':
            theme = ChatTheme.blue();
            break;
          case 'green':
            theme = ChatTheme.green();
            break;
          case 'red':
          default:
            theme = ChatTheme.houExpress();
        }

        _chatService.setSelectedTheme(theme);
      }
    } catch (e) {
      _chatConfig.logger.e('Error loading saved theme: $e');
    }
  }

  Future<void> _showThemeSelector() async {
    String selectedTheme = 'red';
    final currentColor = _chatService.getSelectedTheme().primaryColor;
    if (currentColor == const Color(0xFF0084FF)) {
      selectedTheme = 'blue';
    } else if (currentColor == const Color(0xFF34A853)) {
      selectedTheme = 'green';
    }

    await showDialog<ChatTheme>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(ChatLocalizations.chatThemeDialogTitle(context)),
              content: RadioGroup<String>(
                groupValue: selectedTheme,
                onChanged: (value) {
                  setState(() {
                    selectedTheme = value ?? 'red';
                  });
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          selectedTheme = 'red';
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Radio<String>(value: 'red'),
                            const SizedBox(width: 12),
                            const CircleAvatar(
                              radius: 10,
                              backgroundColor: Color(0xFFEC1D27),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                ChatLocalizations.chatThemeRed(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          selectedTheme = 'blue';
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Radio<String>(value: 'blue'),
                            const SizedBox(width: 12),
                            const CircleAvatar(
                              radius: 10,
                              backgroundColor: Color(0xFF0084FF),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                ChatLocalizations.chatThemeBlue(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          selectedTheme = 'green';
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Radio<String>(value: 'green'),
                            const SizedBox(width: 12),
                            const CircleAvatar(
                              radius: 10,
                              backgroundColor: Color(0xFF34A853),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                ChatLocalizations.chatThemeGreen(context),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(ChatLocalizations.cancelButton(context)),
                ),
                TextButton(
                  onPressed: () {
                    ChatTheme theme;
                    switch (selectedTheme) {
                      case 'red':
                        theme = ChatTheme.houExpress();
                        break;
                      case 'blue':
                        theme = ChatTheme.blue();
                        break;
                      case 'green':
                        theme = ChatTheme.green();
                        break;
                      default:
                        theme = ChatTheme.houExpress();
                    }
                    // Store the selected theme in the service
                    _chatService.setSelectedTheme(theme);

                    // Persist theme to storage
                    try {
                      final themeData = jsonEncode({'color': selectedTheme});
                      _chatConfig.storage.setString(
                        _chatConfig.themeKey,
                        themeData,
                      );
                    } catch (e) {
                      _chatConfig.logger.e('Error saving theme: $e');
                    }

                    Navigator.pop(context);
                  },
                  child: Text(ChatLocalizations.applyButton(context)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Clear audio cache and downloaded files
  Future<void> _clearCacheAndDownloads() async {
    try {
      _chatConfig.logger.i('Starting cache and downloads cleanup...');

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(ChatLocalizations.clearCacheDialogTitle(context)),
            content: Text(ChatLocalizations.clearCacheDialogContent(context)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(ChatLocalizations.cancelButton(context)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  ChatLocalizations.clearButton(context),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        _chatConfig.logger.d('Cache cleanup cancelled by user');
        return;
      }

      // Clear audio playback cache
      try {
        await AudioCacheService(logger: _chatConfig.logger).clearAllCache();
        _chatConfig.logger.i('Audio cache cleared successfully');
      } catch (e) {
        _chatConfig.logger.e('Error clearing audio cache: $e');
      }

      // Clear downloaded files
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null && await downloadsDir.exists()) {
          final files = downloadsDir.listSync();
          int deletedCount = 0;

          for (final file in files) {
            // Only delete files that match our naming convention (have prefixes or original patterns)
            if (file is File) {
              final fileName = file.path.split(Platform.pathSeparator).last;
              // Delete files that start with our prefixes or are sanitized filenames
              if (fileName.startsWith('image_') ||
                  fileName.startsWith('video_') ||
                  fileName.startsWith('audio_') ||
                  fileName.startsWith('file_')) {
                try {
                  await file.delete();
                  deletedCount++;
                  _chatConfig.logger.d('Deleted: $fileName');
                } catch (e) {
                  _chatConfig.logger.e('Error deleting $fileName: $e');
                }
              }
            }
          }
          _chatConfig.logger.i('Deleted $deletedCount downloaded files');
        }
      } catch (e) {
        _chatConfig.logger.e('Error clearing downloaded files: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ChatLocalizations.cacheClaredMessage(context)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _chatConfig.logger.e('Error in cache cleanup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ChatLocalizations.clearCacheErrorPrefix(context)}$e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: AppBar(
          title: Text(
            ChatLocalizations.channelInfoTitle(context),
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: _chatService.getSelectedTheme().primaryColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                Navigator.pop(context, _chatService.getSelectedTheme()),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Channel Header Section
            Padding(
              padding: EdgeInsets.all(16.w),
              child: _buildHeaderSection(),
            ),
            SizedBox(height: 8.h),

            // Divider (full width)
            Container(
              height: 2,
              color: _chatService.getSelectedTheme().primaryColor,
            ),
            SizedBox(height: 8.h),

            // User Profile Card Section
            Padding(padding: EdgeInsets.all(16.w), child: _buildProfileCard()),
            SizedBox(height: 8.h),

            // Divider (full width)
            Container(
              height: 2,
              color: _chatService.getSelectedTheme().primaryColor,
            ),
            SizedBox(height: 4.h),

            // Actions Section (full width)
            _buildActionsSection(),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Channel title
        Text(
          _channelName,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8.h),
        // Channel ID
        Text(
          widget.channelId,
          style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    // Theme is now reactive
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar
        Center(
          child: _userAvatarUrl != null && _userAvatarUrl!.isNotEmpty
              ? ProfileImage(
                  imageUrl: _userAvatarUrl!,
                  width: 80.w,
                  height: 80.w,
                  chatConfig: chatConfig,
                )
              : CircleAvatar(
                  radius: 40.w,
                  backgroundColor: _chatService
                      .getSelectedTheme()
                      .primaryColor
                      .withValues(alpha: 0.1),
                  child: Icon(
                    Icons.person,
                    size: 40.sp,
                    color: _chatService.getSelectedTheme().primaryColor,
                  ),
                ),
        ),
        SizedBox(height: 16.h),
        // Username and code
        Text(
          _currentUserName,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4.h),
        Text(
          '${ChatLocalizations.userId(context)}: @$_currentUserCode',
          style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionsSection() {
    // Theme is now reactive
    return Card(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.palette,
              color: _chatService.getSelectedTheme().primaryColor,
            ),
            title: Text(
              ChatLocalizations.changeThemeMenuItem(context),
              style: TextStyle(fontSize: 16.sp),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showThemeSelector,
          ),
          Divider(height: 0.5, color: Colors.grey[300]),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: _chatService.getSelectedTheme().primaryColor,
            ),
            title: Text(
              ChatLocalizations.clearCacheMenuTitle(context),
              style: TextStyle(fontSize: 16.sp),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _clearCacheAndDownloads,
          ),
        ],
      ),
    );
  }
}

class _ChatChannelInfoServiceListener extends NoOpChatServiceListener {
  final void Function(ChatTheme theme) handleThemeChanged;
  final void Function(String channelName) handleChannelNameChanged;
  final void Function({
    required String userName,
    required String userCode,
    required String? userAvatarUrl,
  })
  handleUserDataChanged;

  _ChatChannelInfoServiceListener({
    required this.handleThemeChanged,
    required this.handleChannelNameChanged,
    required this.handleUserDataChanged,
  });

  @override
  void onThemeChanged(ChatTheme theme) => handleThemeChanged(theme);

  @override
  void onChannelNameChanged(String channelName) =>
      handleChannelNameChanged(channelName);

  @override
  void onUserDataChanged({
    required String userName,
    required String userCode,
    required String? userAvatarUrl,
  }) => handleUserDataChanged(
    userName: userName,
    userCode: userCode,
    userAvatarUrl: userAvatarUrl,
  );
}
