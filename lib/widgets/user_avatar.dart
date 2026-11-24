import 'package:cached_network_image/cached_network_image.dart';
import 'sample_a.dart';
import 'dart:io';
import 'package:flutter/material.dart';

class UserAvatar extends StatelessWidget {
  final String initials;
  final String? url;
  final File? file;
  final double size;
  const UserAvatar({
    super.key,
    required this.initials,
    this.url,
    this.file,
    this.size = 44,
  });
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: SampleA.pale,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * .35,
            fontWeight: FontWeight.bold,
            color: SampleA.primary,
          ),
        ),
      ),
    );
    final uri = Uri.tryParse(url ?? '');
    final valid =
        uri != null &&
        {'https', 'http'}.contains(uri.scheme) &&
        uri.host.isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: file != null
            ? Image.file(
                file!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : valid
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: (size * 2).round(),
                memCacheHeight: (size * 2).round(),
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}
