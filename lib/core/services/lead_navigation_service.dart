import 'package:flutter/material.dart';

import 'package:orderly_app/shared/components/entry_detail_screen.dart';

class LeadNavigationService {
  static Route<void> leadDetailRoute(Map<String, dynamic> lead) {
    final normalizedLead = <String, dynamic>{
      ...lead,
      if (lead["id"] != null) "id": lead["id"].toString(),
    };

    return MaterialPageRoute<void>(
      builder: (_) => EntryDetailScreen(entry: normalizedLead),
    );
  }
}
