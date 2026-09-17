import '../../constant/color.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/chat_config.dart';

class ProfileImage extends StatefulWidget {
  const ProfileImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.chatConfig,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final ChatConfig? chatConfig;

  @override
  State<ProfileImage> createState() => _ProfileImageState();
}

class _ProfileImageState extends State<ProfileImage> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kMainPrimaryColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(50),
          child: CachedNetworkImage(
            width: widget.width,
            height: widget.height,
            imageUrl: widget.imageUrl,
            httpHeaders: widget.chatConfig?.httpAuthHeaders() ?? const {},
            imageBuilder: (context, imageProvider) => Container(
              decoration: BoxDecoration(
                image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
              ),
            ),
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => CircleAvatar(
              child: Image.asset(
                'assets/images/avatar.jpg',
                fit: BoxFit.cover,
                width: widget.width,
                height: widget.height,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
