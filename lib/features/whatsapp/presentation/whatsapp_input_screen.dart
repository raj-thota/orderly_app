import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../core/utils/message_parser.dart';
import '../../leads/controller/leads_controller.dart';

class WhatsAppInputScreen extends ConsumerStatefulWidget {
  const WhatsAppInputScreen({super.key});

  @override
  ConsumerState<WhatsAppInputScreen> createState() =>
      _WhatsAppInputScreenState();
}

class _WhatsAppInputScreenState extends ConsumerState<WhatsAppInputScreen> {
  final TextEditingController controller = TextEditingController();
  final SpeechToText speech = SpeechToText();

  Map<String, dynamic>? parsed;
  bool isAnalyzing = false;
  bool isListening = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = controller.text.trim();

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (text.isEmpty) {
      setState(() {
        parsed = null;
        isAnalyzing = false;
      });
      return;
    }

    setState(() => isAnalyzing = true);

    _debounce = Timer(const Duration(milliseconds: 500), () {
      final result = MessageParser.parse(text);

      setState(() {
        parsed = result;
        isAnalyzing = false;
      });
    });
  }

  Future<void> toggleListening() async {
    if (!isListening) {
      final available = await speech.initialize();

      if (available) {
        setState(() => isListening = true);

        speech.listen(
          onResult: (result) {
            controller.text = result.recognizedWords;
            controller.selection = TextSelection.fromPosition(
              TextPosition(offset: controller.text.length),
            );
          },
        );
      }
    } else {
      speech.stop();
      setState(() => isListening = false);
    }
  }

  void processMessage() {
    if (parsed == null) return;

    final notifier = ref.read(leadsControllerProvider.notifier);

    final lead = {
      "name": parsed!["name"] ?? "Customer",
      "msg": controller.text.trim(),
      "phone": "",
      "status": _mapStatus(parsed!),
      "follow_up_date": parsed!["date"],
      "intent": parsed!["intent"],
      "created_at": DateTime.now().toIso8601String(),
    };

    notifier.addLead(lead, parsed!["items"] ?? []);

    Navigator.pop(context);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Entry created 🚀")));
  }

  String _mapStatus(Map<String, dynamic> parsed) {
    if (parsed["type"] == "order") return "closed";
    if (parsed["type"] == "follow_up") return "follow";
    return "new";
  }

  String getInsight() {
    if (parsed == null) return "";

    final type = parsed!["type"];

    if (type == "order") return "🔥 Ready to order";
    if (type == "follow_up") return "⏳ Needs follow-up";
    return "💬 General inquiry";
  }

  String getAction() {
    final msg = controller.text.toLowerCase();

    if (msg.contains("price")) return "Send pricing details";
    if (msg.contains("order")) return "Confirm order";
    if (msg.contains("tomorrow")) return "Schedule follow-up";
    return "Reply quickly";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          /// 🔥 HEADER WITH BACK BUTTON
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 50, 16, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple, Colors.deepPurple],
              ),
            ),
            child: Row(
              children: [
                /// BACK BUTTON
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),

                const SizedBox(width: 12),

                const Text(
                  "Ask Trudy",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          /// BODY
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                /// ✍️ INPUT
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: "Paste or speak message...",
                            border: InputBorder.none,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      /// 🎤 MIC
                      GestureDetector(
                        onTap: toggleListening,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isListening ? Colors.red : Colors.deepPurple,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.deepPurple.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            isListening ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                /// 🧠 THINKING
                if (isAnalyzing)
                  Row(
                    children: const [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text("Trudy is thinking..."),
                    ],
                  ),

                /// RESULT
                if (!isAnalyzing && parsed != null) ...[
                  const SizedBox(height: 20),

                  /// AI CARD
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// BADGE
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            parsed!["type"] == "order"
                                ? "🔥 Hot Lead"
                                : parsed!["type"] == "follow_up"
                                ? "⏳ Follow-up"
                                : "💬 Inquiry",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          getInsight(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          "👉 ${getAction()}",
                          style: TextStyle(color: Colors.grey.shade700),
                        ),

                        const SizedBox(height: 14),
                        Divider(color: Colors.grey.shade300),

                        const SizedBox(height: 10),

                        _row("Customer", parsed!["name"]),
                        _row("Type", parsed!["type"]),
                        _row("Intent", parsed!["intent"]),

                        if (parsed!["date"] != null)
                          _row("Follow-up", parsed!["date"].toString()),

                        const SizedBox(height: 10),

                        if ((parsed!["items"] ?? []).isNotEmpty)
                          ...parsed!["items"].map<Widget>((i) {
                            return Text(
                              "• ${i["name"]} x${i["qty"]} ₹${i["price"]}",
                            );
                          }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// CTA
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6A1B9A), Color(0xFF8E24AA)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: processMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        "Create Entry",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? "-",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
