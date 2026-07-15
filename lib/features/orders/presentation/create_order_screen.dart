import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/orders/controller/create_order_provider.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.onCreated,
    this.leadId,
  });

  final String customerId;
  final String customerName;
  final String? leadId;
  final void Function(String orderId)? onCreated;

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  late final (String, String) _key;
  final _notesCtl = TextEditingController();
  final _discountCtl = TextEditingController(text: '0');
  final _shippingCtl = TextEditingController(text: '0');
  DateTime? _expectedDate;

  @override
  void initState() {
    super.initState();
    _key = (widget.customerId, widget.customerName);
  }

  @override
  void dispose() {
    _notesCtl.dispose();
    _discountCtl.dispose();
    _shippingCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final n = ref.read(createOrderProvider(_key).notifier);
    n.setDiscount(double.tryParse(_discountCtl.text) ?? 0);
    n.setShippingFee(double.tryParse(_shippingCtl.text) ?? 0);
    n.setNotes(_notesCtl.text.trim().isEmpty ? null : _notesCtl.text.trim());
    n.setExpectedDate(_expectedDate);
    final orderId = await n.submit();
    if (!mounted) return;
    if (orderId != null) {
      ref.read(ordersControllerProvider.notifier).load();
      if (widget.onCreated != null) {
        widget.onCreated!(orderId);
      } else {
        navigator.pop(orderId);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Order created')));
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not create order. Try again.')));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _expectedDate = picked);
      ref.read(createOrderProvider(_key).notifier).setExpectedDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createOrderProvider(_key));
    final draft = state.draft;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Order'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Customer
          _Section(
            title: 'Customer',
            child: Text(
              widget.customerName,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Items
          _Section(
            title: 'Items',
            trailing: TextButton.icon(
              onPressed: () => _addItemDialog(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Item'),
            ),
            child: draft.items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text('No items added yet.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < draft.items.length; i++)
                        _ItemRow(
                          key: Key('item_row_$i'),
                          item: draft.items[i],
                          onRemove: () => ref
                              .read(createOrderProvider(_key).notifier)
                              .removeItem(i),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Pricing
          _Section(
            title: 'Pricing',
            child: Column(
              children: [
                _NumField(
                    label: 'Discount (₹)', controller: _discountCtl),
                const SizedBox(height: AppSpacing.sm),
                _NumField(
                    label: 'Shipping fee (₹)', controller: _shippingCtl),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal',
                        style: TextStyle(color: AppColors.textSecondary)),
                    Text(Money.inr(draft.subtotal),
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary)),
                    Text(
                      Money.inr(draft.grandTotal),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Expected date + notes
          _Section(
            title: 'Details',
            child: Column(
              children: [
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Expected delivery date',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(
                      _expectedDate != null
                          ? '${_expectedDate!.day}/${_expectedDate!.month}/${_expectedDate!.year}'
                          : 'Optional',
                      style: TextStyle(
                          color: _expectedDate != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _notesCtl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('create_order_submit'),
              onPressed: (draft.canSubmit && !state.submitting) ? _submit : null,
              child: state.submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Create Order',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _addItemDialog(BuildContext context) {
    final nameCtl = TextEditingController();
    final priceCtl = TextEditingController();
    final qtyCtl = TextEditingController(text: '1');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtl,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: priceCtl,
                    decoration: const InputDecoration(labelText: 'Unit price ₹'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              if (name.isEmpty) return;
              final qty = int.tryParse(qtyCtl.text) ?? 1;
              final price = double.tryParse(priceCtl.text) ?? 0;
              ref.read(createOrderProvider(_key).notifier).addItem(
                    CreateOrderItem(name: name, qty: qty, unitPrice: price),
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({super.key, required this.item, required this.onRemove});
  final CreateOrderItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.qty} × ${item.name}',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
          Text(Money.inr(item.lineTotal),
              style: const TextStyle(color: AppColors.textSecondary)),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.textSecondary,
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
    );
  }
}
