import 'package:flutter/material.dart';

class ChatTile extends StatelessWidget {
  final String name;
  final String msg;
  final String status;

  const ChatTile(this.name, this.msg, this.status);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 6),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4)
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey.shade200,
            child: Text(name[0]),
          ),

          SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text(msg,
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),

          Text(
            status,
            style: TextStyle(
              color: status == "Order"
                  ? Colors.green
                  : Colors.orange,
            ),
          )
        ],
      ),
    );
  }
}