import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_asset_service.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';

class InvoiceSettingsScreen extends ConsumerStatefulWidget {
  const InvoiceSettingsScreen({super.key});
  @override
  ConsumerState<InvoiceSettingsScreen> createState() => _State();
}

class _State extends ConsumerState<InvoiceSettingsScreen> {
  final _prefix = TextEditingController();
  final _startNo = TextEditingController();
  final _tax = TextEditingController();
  final _currency = TextEditingController();
  final _terms = TextEditingController();
  final _footer = TextEditingController();
  bool _gst = false;
  bool _saving = false;
  bool _seeded = false;

  @override
  void dispose() {
    for (final c in [_prefix, _startNo, _tax, _currency, _terms, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(BusinessProfile p) {
    if (_seeded) return;
    _prefix.text = p.invoicePrefix;
    _startNo.text = p.nextInvoiceNumber.toString();
    _tax.text = p.defaultGstRate.toString();
    _currency.text = p.currency;
    _terms.text = p.paymentTerms ?? '';
    _footer.text = p.invoiceFooter ?? '';
    _gst = p.gstEnabled;
    _seeded = true;
  }

  Future<void> _save(BusinessProfile p) async {
    setState(() => _saving = true);
    try {
      final service = ref.read(businessProfileServiceProvider);
      await service.upsert(p.copyWith(
        defaultGstRate: double.tryParse(_tax.text) ?? p.defaultGstRate,
        currency:
            _currency.text.trim().isEmpty ? p.currency : _currency.text.trim(),
        paymentTerms: _terms.text.trim(),
        invoiceFooter: _footer.text.trim(),
        gstEnabled: _gst,
      ));
      await service.updateInvoiceNumbering(
        prefix:
            _prefix.text.trim().isEmpty ? null : _prefix.text.trim(),
        nextNumber: int.tryParse(_startNo.text.trim()),
      );
      ref.invalidate(businessProfileProvider);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice settings saved ✅')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(businessProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('Invoice Settings'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load settings')),
        data: (profile) {
          final p = profile ?? const BusinessProfile(name: 'Your Business');
          _seed(p);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              _text('Invoice Prefix', _prefix),
              _text('Starting Invoice Number', _startNo,
                  keyboardType: TextInputType.number),
              SwitchListTile(
                title: const Text('GST Enabled'),
                value: _gst,
                activeTrackColor: AppColors.primary,
                onChanged: (v) => setState(() => _gst = v),
              ),
              _text('Default Tax (%)', _tax,
                  keyboardType: TextInputType.number),
              _text('Currency', _currency),
              _text('Payment Terms', _terms),
              _text('Notes / Footer', _footer, maxLines: 3),
              const SizedBox(height: AppSpacing.lg),
              _uploadRow('Logo', 'logo'),
              _uploadRow('Signature', 'signature'),
              const SizedBox(height: AppSpacing.xl),
              const Text('Preview',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              InvoiceSettingsPreview(
                prefix: _prefix.text,
                number:
                    int.tryParse(_startNo.text) ?? p.nextInvoiceNumber,
                currency: _currency.text,
                taxPct: double.tryParse(_tax.text) ?? 0,
                gstEnabled: _gst,
                footer: _footer.text,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(p),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _text(
    String label,
    TextEditingController c, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _uploadRow(String label, String kind) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.upload_file_rounded, color: AppColors.primary),
      title: Text('$label Upload'),
      trailing: TextButton(
        onPressed: _saving
            ? null
            : () async {
                final url =
                    await BusinessAssetService().pickAndUpload(kind: kind);
                if (url == null || !mounted) return;
                final p = ref.read(businessProfileProvider).value ??
                    const BusinessProfile(name: 'Your Business');
                await _save(kind == 'logo'
                    ? p.copyWith(logoUrl: url)
                    : p.copyWith(signatureUrl: url));
              },
        child: const Text('Upload'),
      ),
    );
  }
}

class InvoiceSettingsPreview extends StatelessWidget {
  const InvoiceSettingsPreview({
    super.key,
    required this.prefix,
    required this.number,
    required this.currency,
    required this.taxPct,
    required this.gstEnabled,
    required this.footer,
  });

  final String prefix;
  final int number;
  final String currency;
  final double taxPct;
  final bool gstEnabled;
  final String footer;

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
          Text('$prefix$number',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          Text('Currency: $currency',
              style: const TextStyle(color: AppColors.textSecondary)),
          if (gstEnabled)
            Text(
                'GST @ ${taxPct.toStringAsFixed(taxPct % 1 == 0 ? 0 : 2)}%',
                style: const TextStyle(color: AppColors.textSecondary)),
          if (footer.trim().isNotEmpty) ...[
            const Divider(height: AppSpacing.xl),
            Text(footer,
                style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
