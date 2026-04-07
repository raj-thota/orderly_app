import 'package:flutter/material.dart';

class ActionTile extends StatelessWidget {
  final String text;
  final Color color;

  const ActionTile(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
  color: color.withValues(alpha: 0.08 * 255),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: color.withValues(alpha: 0.3 * 255)),
),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1 * 255),
            child: Icon(Icons.notifications, color: color),
          ),
          SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}