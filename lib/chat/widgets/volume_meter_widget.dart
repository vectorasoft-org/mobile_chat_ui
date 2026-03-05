import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../config/chat_theme.dart';
import '../config/chat_theme_provider.dart';

class VolumeMeterWidget extends StatefulWidget {
  final Stream<double> volumeStream;
  final String timerText;
  final int maxDurationSeconds;

  const VolumeMeterWidget({
    super.key,
    required this.volumeStream,
    required this.timerText,
    required this.maxDurationSeconds,
  });

  @override
  State<VolumeMeterWidget> createState() => _VolumeMeterWidgetState();
}

class _VolumeMeterWidgetState extends State<VolumeMeterWidget> {
  double _currentLevel = 0.0;

  @override
  void initState() {
    super.initState();
    widget.volumeStream.listen((level) {
      if (mounted) {
        setState(() {
          _currentLevel = level.clamp(0.0, 1.0);
        });
      }
    });
  }

  Color _getLevelColor(double level, ChatTheme theme) {
    if (level < 0.7) {
      return theme.volumeLowColor;
    } else if (level < 0.85) {
      return theme.volumeMediumColor;
    } else {
      return theme.volumeHighColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.inputBackground,
        border: Border.all(color: theme.borderColor, width: 1.w),
        borderRadius: BorderRadius.circular(8.r),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12.0,

        // intentionally shit looking number to make the height consistent with input
        vertical: 14.2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Timer display
          Text(
            widget.timerText,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: theme.textSecondary,
            ),
          ),
          SizedBox(height: 2.h),
          // Horizontal volume meter bar
          Container(
            height: 16.h,
            decoration: BoxDecoration(
              color: theme.recordMeterBackground,
              borderRadius: BorderRadius.circular(4.r),
            ),
            padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.h),
            child: Row(
              children: List.generate(
                20,
                (index) {
                  final barLevel = (index + 1) / 20;
                  final isActive = _currentLevel >= barLevel;
                  final color = isActive
                      ? _getLevelColor(barLevel, theme)
                      : const Color(0xFFE0E0E0);

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 0.5.w),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(1.r),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
