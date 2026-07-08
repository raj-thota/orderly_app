import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';

/// Bottom-sheet form to record a payment. Presentation only: [onSave] does the
/// work and returns true on success (the sheet then closes).
class RecordPaymentSheet extends StatefulWidget {
  const RecordPaymentSheet({super.key, required this.onSave});

  final Future<bool> Function(double amount, String method) onSave;

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _amountCtl = TextEditingController();
  String _method = 'upi';
  bool _busy = false;

  static const _methods = [('upi', 'UPI'), ('cash', 'Cash'), ('other', 'Other')];

  @override
  void dispose() {
    _amountCtl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtl.text.trim());

  Future<void> _save() async {
    final amount = _amount;
    if (amount == null || amount <= 0 || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.onSave(amount, _method);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not record payment. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = (_amount ?? 0) > 0 && !_busy;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Record payment',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _amountCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final (value, label) in _methods)
                ChoiceChip(
                  label: Text(label),
                  selected: _method == value,
                  onSelected: (_) => setState(() => _method = value),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Save',
            loading: _busy,
            onPressed: canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}
