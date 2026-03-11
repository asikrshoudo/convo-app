import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/constants.dart';

/// Returns "Online", "Active 5m ago", "Active 2h ago", "Active yesterday",
/// "Active 2d ago" — max 2 days. Beyond that returns null (show nothing).
String? activeStatusText(bool isOnline, Timestamp? lastSeen) {
  if (isOnline) return 'Online';
  if (lastSeen == null) return null;

  final diff = DateTime.now().difference(lastSeen.toDate());

  if (diff.inMinutes < 1)  return 'Active just now';
  if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
  if (diff.inHours < 24)   return 'Active ${diff.inHours}h ago';
  if (diff.inHours < 48)   return 'Active yesterday';
  if (diff.inDays <= 2)    return 'Active ${diff.inDays}d ago';
  return null; // older than 2 days — show nothing
}

/// Small status row widget — reusable everywhere
Widget activeStatusWidget(bool isOnline, Timestamp? lastSeen, {double fontSize = 12}) {
  final text = activeStatusText(isOnline, lastSeen);
  if (text == null) return const SizedBox.shrink();

  final color = isOnline ? kGreen : Colors.grey;

  return Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 7, height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(text, style: TextStyle(color: color, fontSize: fontSize)),
  ]);
}
