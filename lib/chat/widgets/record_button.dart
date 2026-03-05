import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../config/chat_theme_provider.dart';
import '../controllers/recording_controller.dart';

typedef RecordingCompleteCallback =
    Future<void> Function(
      String filePath,
      int durationMilliseconds,
    );

class RecordButton extends StatefulWidget {
  final RecordingController recordingController;
  final RecordingCompleteCallback onRecordingComplete;
  final VoidCallback onRecordingStart;
  final VoidCallback onRecordingCancel;
  final Future<bool> Function() requestPermission;
  final Future<bool> Function() hasPermission;
  final int maxDurationSeconds;
  final double deleteZoneThreshold;
  final Stream<double> Function() getVolumeStream;

  const RecordButton({
    super.key,
    required this.recordingController,
    required this.onRecordingComplete,
    required this.onRecordingStart,
    required this.onRecordingCancel,
    required this.requestPermission,
    required this.hasPermission,
    this.maxDurationSeconds = 180,
    this.deleteZoneThreshold = 32.0,
    required this.getVolumeStream,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  late Offset _buttonPosition;
  bool _inDeleteZone = false;
  String? _currentFilePath;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateButtonDimensions();
    });
  }

  void _updateButtonDimensions() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final topLeft = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      // Store the center of the button
      _buttonPosition = topLeft + Offset(size.width / 2, size.height / 2);
    }
  }

  bool _isInDeleteZone(Offset pointerPosition) {
    final distance = (pointerPosition - _buttonPosition).distance;
    return distance > widget.deleteZoneThreshold;
  }

  Future<void> _startRecording() async {
    try {
      // Report to controller that button was pressed
      widget.recordingController.onPointerDown();

      final hasPermission = await widget.hasPermission();
      if (!hasPermission) {
        final granted = await widget.requestPermission();
        if (!granted) {
          widget.recordingController.cancel();
          return;
        }
      }

      // Create temp file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (DateTime.now().microsecond % 10000).toString();
      _currentFilePath =
          '${tempDir.path}/voice_recording_${timestamp}_$random.ogg';

      // Store path in controller
      widget.recordingController.setRecordingPath(_currentFilePath!);

      // Start recording with Opus codec (OGG format)
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: 128000,
          sampleRate: 48000,
        ),
        path: _currentFilePath!,
      );

      _recordingStartTime = DateTime.now();
      _isRecording = true;
      _inDeleteZone = false;

      setState(() {});
      widget.onRecordingStart();
    } catch (e) {
      // Log error silently
      widget.recordingController.cancel();
    }
  }

  Future<void> _stopRecording({required bool shouldSend}) async {
    if (!_isRecording) return;

    try {
      final recordedPath = await _audioRecorder.stop();

      if (recordedPath != null) {
        _currentFilePath = recordedPath;
      }

      if (!mounted) return;

      // Calculate duration from recording start and stop time
      final recordingDuration = DateTime.now().difference(_recordingStartTime!);
      final durationMilliseconds = recordingDuration.inMilliseconds;

      // Report to controller that button was released
      widget.recordingController.onPointerUp(
        nearButton: shouldSend,
      );

      // Check minimum duration (0.5 seconds = 500 milliseconds)
      if (durationMilliseconds < 500) {
        // Show simple toast notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Recording too short (min 0.5s)'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
            backgroundColor: Colors.grey[800],
          ),
        );
        // Delete temp file
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        widget.recordingController.cancel();
        // Reset UI state by calling cancel callback
        if (mounted) {
          setState(() {
            _isRecording = false;
            _inDeleteZone = false;
          });
        }
        widget.onRecordingCancel();
        return;
      }

      // Update state to stop recording
      if (mounted) {
        setState(() {
          _isRecording = false;
          _inDeleteZone = false;
        });
      }

      if (shouldSend) {
        // Send recording with duration in milliseconds
        await widget.onRecordingComplete(
          _currentFilePath!,
          durationMilliseconds,
        );
      } else {
        // Cancel recording - no toast notification
        // Delete temp file
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        widget.onRecordingCancel();
      }
    } catch (e) {
      // Log error silently
      widget.recordingController.cancel();
      // Ensure we stop recording even on error
      if (mounted) {
        setState(() {
          _isRecording = false;
          _inDeleteZone = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return Padding(
      padding: EdgeInsets.all(8.w),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) async {
          _updateButtonDimensions();
          await _startRecording();
        },
        onTapUp: (details) async {
          if (_isRecording && mounted) {
            await _stopRecording(shouldSend: false);
          }
        },
        onVerticalDragStart: (details) async {
          if (!_isRecording) {
            _updateButtonDimensions();
            await _startRecording();
          }
        },
        onVerticalDragUpdate: (details) {
          if (_isRecording && mounted) {
            final inDeleteZone = _isInDeleteZone(details.globalPosition);
            if (inDeleteZone != _inDeleteZone) {
              setState(() {
                _inDeleteZone = inDeleteZone;
              });

              if (inDeleteZone) {
                HapticFeedback.mediumImpact();
              }
            }
          }
        },
        onVerticalDragEnd: (details) async {
          if (_isRecording && mounted) {
            await _stopRecording(shouldSend: !_inDeleteZone);
          }
        },
        onVerticalDragCancel: () async {
          if (_isRecording && mounted) {
            await _stopRecording(shouldSend: false);
          }
        },
        child: SizedBox(
          width: 50.w,
          height: 50.h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.mic,
                  size: 24.sp,
                  color: theme.recordButtonIconColor,
                ),
              ),
              // Label positioned above button
              if (_isRecording)
                Positioned(
                  top: -36.h,
                  left: 50.w / 2 - 40.w,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color: _inDeleteZone
                          ? theme.recordDeleteZoneIcon
                          : theme.disabledColor,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(
                      _inDeleteZone ? 'Release to cancel' : 'Slide to cancel',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
