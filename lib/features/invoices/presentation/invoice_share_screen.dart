import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:printing/printing.dart';

import '../controller/invoice_provider.dart';
import '../data/invoice_data.dart';
import '../pdf/invoice_pdf.dart';

class InvoiceShareScreen extends ConsumerStatefulWidget {
  const InvoiceShareScreen({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<InvoiceShareScreen> createState() => _InvoiceShareScreenState();
}

class _InvoiceShareScreenState extends ConsumerState<InvoiceShareScreen> {
  InvoiceTemplate? _template;
  bool _preparing = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_prepare);
  }

  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _failed = false;
    });
    final number =
        await ref.read(invoiceControllerProvider.notifier).prepare(widget.order);
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _failed = number == null;
    });
  }

  Order get _live => ref
          .watch(ordersControllerProvider)
          .valueOrNull
          ?.where((o) => o.id == widget.order.id)
          .firstOrNull ??
      widget.order;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(businessProfileProvider).valueOrNull;
    final template = _template ?? invoiceTemplateFromKey(profile?.invoiceTemplate);
    final order = _live;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(order.invoiceNumber != null
            ? 'Invoice ${order.invoiceNumber}'
            : 'Invoice'),
      ),
      body: _preparing
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not prepare the invoice'),
                      TextButton(onPressed: _prepare, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        children: [
                          for (final t in InvoiceTemplate.values)
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: AppSpacing.sm),
                              child: ChoiceChip(
                                label: Text(invoiceTemplateLabel(t)),
                                selected: template == t,
                                onSelected: (_) =>
                                    setState(() => _template = t),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PdfPreview(
                        key: ValueKey(template),
                        build: (format) => buildInvoicePdf(
                          InvoiceData.fromOrder(order, profile),
                          template,
                        ),
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                      ),
                    ),
                  ],
                ),
    );
  }
}
