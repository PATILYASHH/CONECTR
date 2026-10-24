import 'package:flutter/material.dart';

/// A username's first letter in a circle.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.username, this.radius});

  final String? username;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final name = username ?? '';
    return CircleAvatar(
      radius: radius,
      child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
    );
  }
}
