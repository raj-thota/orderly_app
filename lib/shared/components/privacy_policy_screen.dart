import 'package:flutter/material.dart';
import '../../../shared/widgets/legal_widgets.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Privacy Policy")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          LegalTitle("Your Privacy Matters"),

          LegalPoint(
            "Closr collects only the information necessary to provide and improve the service.",
          ),
          LegalPoint(
            "We may collect basic account data such as your name and email.",
          ),
          LegalPoint(
            "Your data is securely stored using trusted infrastructure.",
          ),
          LegalPoint("We do NOT sell your personal data."),
          LegalPoint(
            "Your data is used only to improve product experience and support.",
          ),
          LegalPoint(
            "You can request deletion of your data anytime by contacting support.",
          ),

          SizedBox(height: 20),

          LegalTitle("Contact"),

          Text(
            "For privacy concerns:\nclosrsupport@gmail.com",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
