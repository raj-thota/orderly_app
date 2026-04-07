import 'package:flutter/material.dart';
import '../../../shared/widgets/legal_widgets.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Terms of Service")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          LegalTitle("Usage Terms"),

          LegalPoint(
              "Closr helps manage leads and customer interactions."),
          LegalPoint(
              "You agree to use the app responsibly."),
          LegalPoint(
              "Closr does not guarantee business results."),
          LegalPoint(
              "We are not responsible for decisions made using this app."),
          LegalPoint(
              "Features and terms may change over time."),
          LegalPoint(
              "Continued use means acceptance of updated terms."),

          SizedBox(height: 20),

          LegalTitle("Contact"),

          Text(
            "For questions:\nclosrsupport@gmail.com",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}