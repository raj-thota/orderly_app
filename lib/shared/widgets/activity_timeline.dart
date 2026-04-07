import 'package:flutter/material.dart';

class ActivityTimeline extends StatelessWidget {
  final List<dynamic>? activities;

  const ActivityTimeline({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    if (activities == null || activities!.isEmpty) {
      return const Text("No activity yet");
    }

    final sorted = [...activities!]
      ..sort((a, b) =>
          (b["time"] as DateTime).compareTo(a["time"]));

    return Column(
      children: sorted.map((activity) {
        return _timelineItem(activity);
      }).toList(),
    );
  }

  Widget _timelineItem(Map activity) {
    final type = activity["type"];
    final time = activity["time"] as DateTime;

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
              color: color.withValues(alpha: 0.15 * 255),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (activity["note"] != null)
                  Text(
                    activity["note"],
                    style: const TextStyle(color: Colors.grey),
                  ),

                const SizedBox(height: 4),

                Text(
                  _formatTime(time),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) {
    return "${d.day}/${d.month} ${d.hour}:${d.minute}";
  }
}