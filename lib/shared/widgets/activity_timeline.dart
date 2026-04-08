import 'package:flutter/material.dart';

class ActivityTimeline extends StatelessWidget {
  final List<dynamic>? activities;

  const ActivityTimeline({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    if (activities == null || activities!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          "No activity yet",
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final normalized = activities!
        .whereType<Map>()
        .map((activity) => Map<String, dynamic>.from(activity))
        .toList();

    final sorted = [...normalized]
      ..sort((a, b) => _parseTime(b["time"]).compareTo(_parseTime(a["time"])));

    return Column(
      children: sorted.map((activity) {
        return _timelineItem(activity);
      }).toList(),
    );
  }

  Widget _timelineItem(Map activity) {
    final type = (activity["type"] ?? "").toString();
    final time = _parseTime(activity["time"]);

    IconData icon;
    Color color;
    String title;

    switch (type) {
      case "created":
        icon = Icons.add;
        color = Colors.blue;
        title = "Lead created";
        break;

      case "follow_up":
        icon = Icons.schedule;
        color = Colors.orange;
        title = "Follow-up scheduled";
        break;

      case "done":
        icon = Icons.check;
        color = Colors.green;
        title = "Marked as done";
        break;
      case "updated":
        icon = Icons.edit_rounded;
        color = Colors.blueGrey;
        title = "Lead updated";
        break;
      case "order_status":
        icon = Icons.local_shipping_outlined;
        color = Colors.blue;
        title = "Order status updated";
        break;
      case "order_update":
        icon = Icons.inventory_2_outlined;
        color = Colors.deepPurple;
        title = "Order items updated";
        break;

      default:
        icon = Icons.info;
        color = Colors.grey;
        title = "Activity";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// ICON
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),

          const SizedBox(width: 12),

          /// TEXT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                if (activity["note"] != null)
                  Text(
                    activity["note"],
                    style: const TextStyle(color: Colors.grey),
                  ),

                const SizedBox(height: 4),

                Text(
                  _formatTime(time),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    return "${d.day}/${d.month} "
        "${d.hour.toString().padLeft(2, '0')}:"
        "${d.minute.toString().padLeft(2, '0')}";
  }

  DateTime _parseTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? "") ?? DateTime.now();
  }
}
