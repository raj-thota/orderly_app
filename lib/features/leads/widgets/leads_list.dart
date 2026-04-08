import 'package:flutter/material.dart';
import 'package:orderly_app/features/leads/widgets/lead_card.dart';
import 'package:orderly_app/features/leads/widgets/leads_empty_state.dart';
import 'package:orderly_app/shared/components/add_entry_screen.dart';

class LeadsList extends StatelessWidget {
  final List<Map<String, dynamic>> leads;
  final Function(Map<String, dynamic>) onDone;
  final Function(Map<String, dynamic>, String, DateTime) onFollowUp;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onDelete;

  const LeadsList({
    super.key,
    required this.leads,
    required this.onDone,
    required this.onFollowUp,
    required this.onEdit,
    required this.onDelete,
  });

  DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (leads.isEmpty) {
      return LeadsEmptyState(
        onAdd: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const AddEntryScreen(),
          );
        },
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },

      /// 🔥 KEY IS IMPORTANT (forces animation)
      child: ListView.builder(
        key: ValueKey(leads.length.toString() + leads.hashCode.toString()),
        padding: const EdgeInsets.all(16),
        itemCount: leads.length,
        itemBuilder: (context, index) {
          final lead = leads[index];

          final followUpDate = parseDate(lead["follow_up_date"]);

          final isOverdue =
              (lead["status"] ?? "").toString().toLowerCase() == "follow" &&
              followUpDate != null &&
              followUpDate.isBefore(DateTime.now());

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: LeadCard(
              id: lead["id"]?.toString() ?? "",
              name: lead["name"] ?? "",
              message: lead["msg"] ?? "",
              phone: lead["phone"] ?? "",
              intent: lead["intent"],
              date: followUpDate,
              status: lead["status"],
              createdAt: parseDate(lead["created_at"]),
              isOverdue: isOverdue,
              onFollowUp: (note, date) => onFollowUp(lead, note, date),
              onDone: () => onDone(lead),
              onEdit: () => onEdit(lead),
              onDelete: () => onDelete(lead),
            ),
          );
        },
      ),
    );
  }
}
