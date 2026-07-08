import 'package:flutter/material.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiry_detail_screen.dart';

class LeadNavigationService {
  static Route<void> leadDetailRoute(Map<String, dynamic> lead) {
    final leadId = (lead['id'] ?? '').toString();

    return MaterialPageRoute<void>(
      builder: (_) => _EnquiryLoader(leadId: leadId),
    );
  }
}

/// Async-loads the [Enquiry] by id, then renders [EnquiryDetailScreen].
/// Falls back to a simple loading indicator while the fetch is in flight and
/// pops silently if no matching enquiry is found (e.g. row was deleted).
class _EnquiryLoader extends StatefulWidget {
  const _EnquiryLoader({required this.leadId});

  final String leadId;

  @override
  State<_EnquiryLoader> createState() => _EnquiryLoaderState();
}

class _EnquiryLoaderState extends State<_EnquiryLoader> {
  late final Future<Enquiry?> _future;

  @override
  void initState() {
    super.initState();
    _future = EnquiriesService().fetchById(widget.leadId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Enquiry?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final enquiry = snapshot.data;
        if (enquiry == null) {
          // Pop after the frame so the route is already fully mounted.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return EnquiryDetailScreen(enquiry: enquiry);
      },
    );
  }
}
