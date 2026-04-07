class LeadsSorter {
  static List<Map<String, dynamic>> sort(List<Map<String, dynamic>> leads) {
    leads.sort((a, b) {
      final p1 = _priority(a);
      final p2 = _priority(b);

      if (p1 != p2) return p1.compareTo(p2);

      final t1 = a["created_at"] ?? DateTime.now();
      final t2 = b["created_at"] ?? DateTime.now();

      return (t2 as DateTime).compareTo(t1 as DateTime);
    });

    return leads;
  }

  static int _priority(Map<String, dynamic> lead) {
    final status = lead["status"];
    final date = lead["follow_up_date"];

    if (status == "follow" && date != null) {
      final now = DateTime.now();
      final d = date as DateTime;

      if (d.isBefore(_startOfDay(now))) return 1; // 🔴 overdue
      if (_isSameDay(d, now)) return 2; // 🟠 today
      return 3; // 🔵 upcoming
    }

    if (status == "new") return 4;
    return 5; // closed
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.day == b.day && a.month == b.month && a.year == b.year;
  }

  static DateTime _startOfDay(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }
}
