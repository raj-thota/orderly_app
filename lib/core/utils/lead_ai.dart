int getLeadScore(Map<String, dynamic> lead) {
  int score = 0;

  final msg = (lead["msg"] ?? "").toString().toLowerCase();
  final intent = (lead["intent"] ?? "").toString();

  if (intent == "high") score += 50;

  if (msg.contains("price") || msg.contains("cost")) score += 20;
  if (msg.contains("buy") || msg.contains("order")) score += 30;

  /// 🔥 FIXED DATE PARSE
  final rawDate = lead["follow_up_date"];
  final date = rawDate is DateTime
      ? rawDate
      : DateTime.tryParse(rawDate?.toString() ?? "");

  if (lead["status"] == "follow" && date != null) {
    if (date.isBefore(DateTime.now())) score += 25;
  }

  final rawCreated = lead["created_at"];
  final created = rawCreated is DateTime
      ? rawCreated
      : DateTime.tryParse(rawCreated?.toString() ?? "");

  if (created != null) {
    if (DateTime.now().difference(created).inHours < 2) {
      score += 15;
    }
  }

  return score;
}

/// 🔥 PRIORITY LABEL
String getPriorityLabel(int score) {
  if (score > 70) return "🔥 Hot";
  if (score > 40) return "⚡ Warm";
  return "🧊 Cold";
}

/// 💡 AI SUGGESTION
String getSuggestion(Map<String, dynamic> lead) {
  final msg = (lead["msg"] ?? "").toString().toLowerCase();

  if (msg.contains("price")) return "Send price now";
  if (msg.contains("order")) return "Confirm order";
  if (msg.contains("interested")) return "Close this lead";
  return "Follow up now";
}