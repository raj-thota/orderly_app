import 'package:flutter/material.dart';

class LeadTile extends StatelessWidget {
  final String name;
  final String msg;
  final String status;

  const LeadTile(this.name, this.msg, this.status);

  @override
  Widget build(BuildContext context) {
    Color color;

    switch (status) {
      case "Follow-up":
        color = Colors.red;
        break;
      case "New":
        color = Colors.green;
        break;
      default:
        color = Colors.orange;
    }

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 5),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold)),
                Text(msg),
              ]),
          Text(status, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}