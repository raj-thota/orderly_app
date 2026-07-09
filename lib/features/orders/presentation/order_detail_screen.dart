import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/shared/widgets/app_card.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/payments/controller/payments_provider.dart';
import 'package:orderly_app/features/payments/data/upi.dart';
import 'package:orderly_app/features/payments/widgets/record_payment_sheet.dart';
import 'package:orderly_app/features/payments/widgets/upi_collect_sheet.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_share_screen.dart';

import '../controller/orders_provider.dart';
import '../data/order.dart';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final Order order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _busy = false;

  static const _flow = ['pending', 'packed', 'shipped', 'delivered'];
  static final _mobileRe = RegExp(r'^[6-9]\d{9}$');

  /// wa.me link for an Indian mobile; falls back to a bare wa.me when the
  /// stored number is not a clean 10-digit mobile.
  String _waLink(String? phone) => phone != null && _mobileRe.hasMatch(phone)
      ? 'https://wa.me/91$phone'
      : 'https://wa.me/';

  Order get _live => ref
          .watch(ordersControllerProvider)
          .valueOrNull
          ?.where((o) => o.id == widget.order.id)
          .firstOrNull ??
      widget.order;

  Future<void> _openUri(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the app')));
    }
  }

  Future<void> _advance(Order order) async {
    if (_busy) return;
    final next = nextOrderStatus(order.status);
    if (next == null) return;

    String? courier;
    String? tracking;
    if (next == 'shipped') {
      final result = await _askCourier();
      if (result == null) return;
      courier = result.$1;
      tracking = result.$2;
    } else if (next == 'delivered') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Mark as delivered?'),
          content: const Text(
              'This closes the order. A booked unique piece will be marked sold.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ordersControllerProvider.notifier).advanceTo(
            order,
            next,
            courier: courier,
            trackingNo: tracking,
          );
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Marked as $next')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not update. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns (courier, tracking) or null if cancelled/incomplete. The dialog
  /// body owns its controllers so they're disposed with the route (disposing
  /// them on future-completion rebuilds the exiting fields on a dead controller).
  Future<(String, String)?> _askCourier() {
    return showDialog<(String, String)?>(
      context: context,
      builder: (_) => const _ShippingDialog(),
    );
  }

  Future<void> _shareTracking(Order order) async {
    final msg =
        'Hi ${order.customerName ?? 'there'}, your order #${order.orderNumber ?? ''} '
        'has shipped via ${order.courier ?? ''}. Tracking: ${order.trackingNo ?? ''}.';
    final base = _waLink(order.customerPhone);
    await _openUri(Uri.parse('$base?text=${Uri.encodeComponent(msg)}'));
  }

  Future<void> _recordPayment(Order order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordPaymentSheet(
        onSave: (amount, method) => ref
            .read(paymentsControllerProvider.notifier)
            .recordPayment(order.id!, amount, method),
      ),
    );
  }

  Future<void> _collectUpi(Order order, String vpa, String? vpaName) async {
    final uri = buildUpiUri(
      vpa: vpa,
      name: vpaName,
      amount: order.dues,
      note: order.orderNumber != null ? 'Order #${order.orderNumber}' : 'Order',
    );
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => UpiCollectSheet(
        amount: order.dues,
        upiUri: uri,
        vpa: vpa,
        vpaName: vpaName,
        onShareWhatsApp: () {
          Navigator.of(context).pop();
          final msg = 'Payment request'
              '${order.orderNumber != null ? ' for order #${order.orderNumber}' : ''}: '
              '${Money.inr(order.dues)}\n$uri';
          _openUri(Uri.parse('${_waLink(order.customerPhone)}'
              '?text=${Uri.encodeComponent(msg)}'));
        },
      ),
    );
  }

  Widget _amountRow(String label, double value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(Money.inr(value),
            style: const TextStyle(color: AppColors.textPrimary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _live;
    final next = nextOrderStatus(order.status);
    final phone = order.customerPhone;
    final upiId = ref.watch(businessProfileProvider).valueOrNull?.upiId;
    final upiName = ref.watch(businessProfileProvider).valueOrNull?.upiName;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(order.orderNumber != null
            ? '#${order.orderNumber} · ${order.customerName ?? 'Order'}'
            : (order.customerName ?? 'Order')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Status stepper.
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in _flow)
                  Expanded(
                    child: Column(
                      children: [
                        Icon(
                          _flow.indexOf(order.status) >= _flow.indexOf(s)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: _flow.indexOf(order.status) >= _flow.indexOf(s)
                              ? AppColors.primary
                              : AppColors.border,
                        ),
                        const SizedBox(height: 4),
                        Text(s,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (phone != null && phone.isNotEmpty)
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openUri(Uri.parse(_waLink(phone))),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openUri(Uri.parse(
                          'tel:${phone.replaceAll(RegExp(r'\D'), '')}')),
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const Text('Call'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          // Items.
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final it in order.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${it.qty} × ${it.name}',
                              style:
                                  const TextStyle(color: AppColors.textPrimary)),
                        ),
                        Text(Money.inr(it.lineTotal),
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(Money.inr(order.grandTotal),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    StatusPill(status: order.status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Payment.
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _amountRow('Total', order.grandTotal),
                const SizedBox(height: AppSpacing.xs),
                _amountRow('Paid', order.paidTotal),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dues',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(Money.inr(order.dues),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(status: order.paymentStatus),
                ),
                if (order.dues > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _recordPayment(order),
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Record payment'),
                        ),
                      ),
                      if (upiId != null && upiId.isNotEmpty) ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _collectUpi(order, upiId, upiName),
                            icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                            label: const Text('Collect via UPI'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => InvoiceShareScreen(order: order)),
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Share invoice'),
          ),
          if (order.courier != null && order.courier!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${order.courier} · ${order.trackingNo ?? ''}',
                      style: const TextStyle(color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _shareTracking(order),
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Share tracking'),
                  ),
                ],
              ),
            ),
          ] else if (order.status == 'shipped') ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => _shareTracking(order),
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: const Text('Share tracking'),
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Mark as $next',
              loading: _busy,
              onPressed: () => _advance(order),
            ),
          ],
        ],
      ),
    );
  }
}

/// Courier + tracking capture. A StatefulWidget so its controllers live and die
/// with the dialog route (avoids "used after disposed" during the exit animation).
class _ShippingDialog extends StatefulWidget {
  const _ShippingDialog();

  @override
  State<_ShippingDialog> createState() => _ShippingDialogState();
}

class _ShippingDialogState extends State<_ShippingDialog> {
  final _courierCtl = TextEditingController();
  final _trackingCtl = TextEditingController();

  @override
  void dispose() {
    _courierCtl.dispose();
    _trackingCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Shipping details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _courierCtl,
            decoration: const InputDecoration(labelText: 'Courier'),
          ),
          TextField(
            controller: _trackingCtl,
            decoration: const InputDecoration(labelText: 'Tracking number'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final c = _courierCtl.text.trim();
            final t = _trackingCtl.text.trim();
            if (c.isEmpty || t.isEmpty) return; // both required
            Navigator.pop(context, (c, t));
          },
          child: const Text('Ship'),
        ),
      ],
    );
  }
}
