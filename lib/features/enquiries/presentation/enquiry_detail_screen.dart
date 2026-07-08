import 'package:flutter/material.dart';

import '../data/enquiry.dart';

class EnquiryDetailScreen extends StatelessWidget {
  const EnquiryDetailScreen({super.key, required this.enquiry});
  final Enquiry enquiry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(enquiry.customerName ?? 'Enquiry')));
  }
}
