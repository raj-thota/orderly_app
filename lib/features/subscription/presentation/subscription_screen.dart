import 'package:flutter/material.dart';

class SubscriptionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Upgrade")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Go Pro 🚀",
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),

            SizedBox(height: 20),

            feature("WhatsApp integration"),
            feature("Auto lead detection"),
            feature("AI chat analysis"),
            feature("Smart reminders"),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {},
              child: Text("Upgrade Now"),
            )
          ],
        ),
      ),
    );
  }

  Widget feature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.check, color: Colors.green),
          SizedBox(width: 10),
          Text(text),
        ],
      ),
    );
  }
}