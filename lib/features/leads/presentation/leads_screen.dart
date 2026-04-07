// 🔥 FULL UPDATED FILE

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/utils/lead_ai.dart';
import 'package:orderly_app/shared/components/add_entry_screen.dart';
import '../controller/leads_controller.dart';
import '../widgets/leads_search_bar.dart';
import '../widgets/leads_filters.dart';
import '../widgets/leads_tabs.dart';
import '../widgets/leads_list.dart';

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  int selectedTab = 0;
  String search = "";
  String? filter;
  String sort = "Latest";

  final tabs = ["New", "Follow-ups", "Hot 🔥"];

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(leadsControllerProvider.notifier).loadLeads();
    });
  }

  bool _isHotLead(Map<String, dynamic> lead) {
    final msg = (lead["msg"] ?? "").toString().toLowerCase();
    final intent = (lead["intent"] ?? "").toString().toLowerCase();

    return intent == "high" ||
        msg.contains("price") ||
        msg.contains("buy") ||
        msg.contains("order") ||
        msg.contains("cost");
  }

  /// 🔥 SAFE DATE PARSER (VERY IMPORTANT)
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final allLeads = ref.watch(leadsControllerProvider);

    final leads = allLeads.where((l) => l["status"] != "closed").toList();

    final filtered = leads.where((lead) {
      /// 🔥 TAB FILTER
      if (selectedTab == 0 &&
          (lead["status"] ?? "").toString().toLowerCase() != "new") {
        return false;
      }
      if (selectedTab == 1 &&
          (lead["status"] ?? "").toString().toLowerCase() != "follow") {
        return false;
      }
      if (selectedTab == 2 && !_isHotLead(lead)) {
        return false;
      }

      /// 🔍 SEARCH
      if (search.isNotEmpty) {
        final text = (lead["name"].toString() + lead["msg"].toString())
            .toLowerCase();
        if (!text.contains(search)) return false;
      }

      /// 📅 FILTERS (FIXED)
      final followUpDate = _parseDate(lead["follow_up_date"]);

      if (filter == "Today") {
        if (followUpDate == null) return false;

        final now = DateTime.now();

        if (!(followUpDate.day == now.day &&
            followUpDate.month == now.month &&
            followUpDate.year == now.year)) {
          return false;
        }
      }

      if (filter == "Overdue") {
        if (followUpDate == null) return false;

        if (!followUpDate.isBefore(DateTime.now())) return false;
      }

      return true;
    }).toList();

    /// 🔥 SMART SORT (FIXED)
    final sorted = [...filtered];
    sorted.sort((a, b) {
      final aScore = getLeadScore({
        ...a,
        "date": _parseDate(a["follow_up_date"]),
        "created_at": _parseDate(a["created_at"]),
      });

      final bScore = getLeadScore({
        ...b,
        "date": _parseDate(b["follow_up_date"]),
        "created_at": _parseDate(b["created_at"]),
      });

      return bScore.compareTo(aScore);
    });

    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Leads",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          LeadsSearchBar(
            onChanged: (val) => setState(() => search = val.toLowerCase()),
          ),

          const SizedBox(height: 10),

          LeadsFilters(
            selected: filter,
            sort: sort,
            onChange: (val) => setState(() => filter = val),
            onSort: (val) => setState(() => sort = val),
          ),

          const SizedBox(height: 10),

          LeadsTabs(
            tabs: tabs,
            selectedIndex: selectedTab,
            onChange: (i) => setState(() => selectedTab = i),
            getCount: (i) {
              if (i == 0) {
                return leads.where((l) => l["status"] == "new").length;
              }
              if (i == 1) {
                return leads.where((l) => l["status"] == "follow").length;
              }
              return leads.where((l) => _isHotLead(l)).length;
            },
          ),

          const SizedBox(height: 10),

          Expanded(
            child: LeadsList(
              leads: sorted,
              onDone: (lead) {
                ref.read(leadsControllerProvider.notifier).markDone(lead);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("${lead["name"]} converted to order 📦"),
                  ),
                );
              },
              onFollowUp: (lead, note, date) async {
                await ref
                    .read(leadsControllerProvider.notifier)
                    .followUp(lead, note, date);
              },
              onEdit: (lead) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEntryScreen(initialData: lead),
                  ),
                );
              },
              onDelete: (lead) => _delete(context, lead),
            ),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, Map<String, dynamic> lead) {
    final index = ref.read(leadsControllerProvider).indexOf(lead);

    ref.read(leadsControllerProvider.notifier).deleteLead(lead);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Deleted"),
        action: SnackBarAction(
          label: "Undo",
          onPressed: () {
            ref.read(leadsControllerProvider.notifier).restoreLead(index, lead);
          },
        ),
      ),
    );
  }
}
