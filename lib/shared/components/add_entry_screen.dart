import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../features/leads/controller/leads_controller.dart';

class AddEntryScreen extends ConsumerStatefulWidget {
  const AddEntryScreen({super.key});

  @override
  ConsumerState<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends ConsumerState<AddEntryScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final messageController = TextEditingController();

  final SpeechToText speech = SpeechToText();
  final FocusNode messageFocus = FocusNode();

  bool isListening = false;

  String aiSuggestion = "";
  String intent = "inquiry";
  DateTime? followUp;

  late AnimationController _micAnimController;
  late Animation<double> _micScale;

  final quickMessages = [
    {"text": "I want to order", "type": "🔥"},
    {"text": "Confirm order for tomorrow", "type": "🔥"},
    {"text": "Price?", "type": "⚡"},
    {"text": "Send details", "type": "⚡"},
    {"text": "Call tomorrow", "type": "⏳"},
    {"text": "Will confirm later", "type": "⏳"},
  ];

  @override
  void initState() {
    super.initState();

    phoneController.addListener(() => setState(() {}));
    messageController.addListener(() => setState(() {}));

    _micAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _micScale = Tween<double>(begin: 1, end: 1.2).animate(
      CurvedAnimation(parent: _micAnimController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      messageFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _micAnimController.dispose();
    messageFocus.dispose();
    super.dispose();
  }

  /// 🎤 VOICE INPUT
  Future<void> toggleListening() async {
    if (!isListening) {
      final available = await speech.initialize(
        onError: (e) {
          _showSnack("Mic error: ${e.errorMsg}", true);
        },
      );

      if (!available) {
        _showSnack("Microphone permission not granted", true);
        return;
      }

      setState(() => isListening = true);
      _micAnimController.repeat(reverse: true);

      speech.listen(
        onResult: (result) {
          final text = result.recognizedWords;

          messageController.text = text;
          messageController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );

          analyze(text);
        },
      );
    } else {
      speech.stop();
      _micAnimController.stop();
      _micAnimController.reset();

      setState(() => isListening = false);
    }
  }

  void analyze(String msg) {
    msg = msg.toLowerCase();

    followUp = null;

    if (msg.contains("order")) {
      intent = "order";
      aiSuggestion = "🔥 High intent • Close this quickly";
    } else if (msg.contains("price") || msg.contains("details")) {
      intent = "inquiry";
      aiSuggestion = "⚡ Share details fast";
    } else if (msg.contains("tomorrow")) {
      intent = "follow_up";
      followUp = DateTime.now().add(const Duration(days: 1));
      aiSuggestion = "⏳ Follow-up set for tomorrow";
    } else if (msg.contains("later")) {
      intent = "follow_up";
      aiSuggestion = "📅 Select follow-up date";
    } else {
      intent = "inquiry";
      aiSuggestion = "💬 Reply soon";
    }

    setState(() {});
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: followUp ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => followUp = picked);
    }
  }

  void goBack() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> save() async {
    if (!_formKey.currentState!.validate()) return;

    if (intent == "follow_up" && followUp == null) {
      _showSnack("Select follow-up date to avoid missing customer 📅", true);
      return;
    }

    final controller = ref.read(leadsControllerProvider.notifier);

    final status = intent == "order"
        ? "closed"
        : intent == "follow_up"
        ? "follow"
        : "new";

    final data = {
      "name": nameController.text.trim().isEmpty
          ? "Customer"
          : nameController.text.trim(),
      "phone": phoneController.text.trim(),
      "msg": messageController.text.trim(),
      "status": status,
      "intent": intent,
      "follow_up_date": followUp?.toIso8601String(),
      "created_at": DateTime.now().toIso8601String(),
    };

    try {
      await controller.addLead(data, []);

      if (!mounted) return;
      goBack();

      String message;
      if (intent == "order") {
        message =
            "🧾 Order created for ${data["name"]}\nNext: Start processing order";
      } else if (intent == "follow_up") {
        message =
            "⏳ Follow-up set on ${followUp!.day}/${followUp!.month}\nDon’t miss this customer";
      } else {
        message = "🚀 Lead added for ${data["name"]}\nNext: Send reply or call";
      }

      _showSnack(message, false);
    } catch (e) {
      _showSnack("Something failed ❌ Try again", true);
    }
  }

  void _showSnack(String text, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.black87,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isValid =
        phoneController.text.trim().length == 10 &&
        messageController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          /// HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF5B0EAF), Color(0xFF7B2FF7)],
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: goBack,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Quick Add",
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickMessages.map((item) {
                      return ActionChip(
                        label: Text("${item["type"]} ${item["text"]}"),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          messageController.text = item["text"]!;
                          analyze(item["text"]!);
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  _input(
                    nameController,
                    "Customer Name",
                    required: true,
                    keyboard: TextInputType.name,
                    hint: "Customer Name",
                  ),
                  _input(
                    phoneController,
                    "Customer Phone",
                    required: true,
                    keyboard: TextInputType.phone,
                    hint: "Enter 10-digit number",
                  ),

                  /// MESSAGE + MIC
                  Stack(
                    children: [
                      _input(
                        messageController,
                        "Customer Intent",
                        required: true,
                        maxLines: 5,
                        hint:
                            "Type, speak or select from quick messages(top)...",
                        onChanged: analyze,
                        focusNode: messageFocus,
                      ),

                      Positioned(
                        right: 5,
                        bottom: 20,
                        child: GestureDetector(
                          onTap: toggleListening,
                          child: AnimatedBuilder(
                            animation: _micScale,
                            builder: (_, child) {
                              return Transform.scale(
                                scale: isListening ? _micScale.value : 1,
                                child: child,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isListening
                                    ? Colors.red
                                    : Colors.deepPurple,
                                borderRadius: BorderRadius.circular(
                                  8,
                                ), // ✅ square style
                                boxShadow: [
                                  if (isListening)
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.6),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                              child: Icon(
                                isListening ? Icons.mic : Icons.mic_none,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (aiSuggestion.isNotEmpty)
                    _card(aiSuggestion, Colors.deepPurple),

                  if (intent == "follow_up")
                    GestureDetector(
                      onTap: pickDate,
                      child: _card(
                        followUp == null
                            ? "Select follow-up date 📅"
                            : "Follow-up: ${followUp!.day}/${followUp!.month}",
                        Colors.orange,
                      ),
                    ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: isValid ? save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      "Create",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _input(
    TextEditingController c,
    String label, {
    int maxLines = 1,
    bool required = false,
    TextInputType keyboard = TextInputType.text,
    Function(String)? onChanged,
    String? hint,
    FocusNode? focusNode,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        onChanged: onChanged,
        focusNode: focusNode,
        autovalidateMode:
            AutovalidateMode.onUserInteraction, // ✅ instant validation
        validator: required
            ? (v) {
                if (v == null || v.trim().isEmpty) {
                  return "$label is required";
                }

                if (label == "Phone" && v.trim().length != 10) {
                  return "Enter valid 10-digit phone";
                }

                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
