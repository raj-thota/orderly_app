import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import '../controller/business_profile_provider.dart';
import '../data/business_profile.dart';

class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key, this.onDone});

  /// Called after a successful save (e.g. to navigate into the app).
  final VoidCallback? onDone;

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _upiId = TextEditingController();
  final _upiName = TextEditingController();
  final _gstin = TextEditingController();
  final _gstRate = TextEditingController();
  String _template = 'classic';
  bool _seededTemplate = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _upiId, _upiName, _gstin, _gstRate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = BusinessProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      upiId: _upiId.text.trim().isEmpty ? null : _upiId.text.trim(),
      upiName: _upiName.text.trim().isEmpty ? null : _upiName.text.trim(),
      gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
      defaultGstRate: double.tryParse(_gstRate.text.trim()) ?? 0,
      invoiceTemplate: _template,
    );

    try {
      await ref.read(businessProfileServiceProvider).upsert(profile);
      ref.invalidate(businessProfileProvider);
      if (!mounted) return;
      widget.onDone?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Seed the template from the saved profile once it resolves, so re-saving
    // setup can't silently revert a chosen template back to 'classic'.
    final existingTemplate =
        ref.watch(businessProfileProvider).valueOrNull?.invoiceTemplate;
    if (!_seededTemplate && existingTemplate != null) {
      _template = existingTemplate;
      _seededTemplate = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Set up your business')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Tell customers who they are buying from. This appears on your receipts.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            _field(_name, 'Business name', required: true),
            _field(_phone, 'Phone (WhatsApp)', keyboard: TextInputType.phone),
            _field(_address, 'Address', maxLines: 2),
            const SizedBox(height: AppSpacing.sm),
            const Text('Payments', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            _field(_upiId, 'UPI ID (e.g. name@bank)'),
            _field(_upiName, 'Name on UPI'),
            const SizedBox(height: AppSpacing.sm),
            const Text('Tax (optional)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Add a GSTIN only if you are GST-registered. Leave blank for a plain receipt.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            _field(_gstin, 'GSTIN'),
            _field(_gstRate, 'Default GST %', keyboard: TextInputType.number),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _template,
              decoration: InputDecoration(
                labelText: 'Invoice template',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 'classic', child: Text('Classic')),
                DropdownMenuItem(value: 'minimal', child: Text('Minimal')),
                DropdownMenuItem(value: 'boutique', child: Text('Boutique')),
              ],
              onChanged: (v) => setState(() => _template = v ?? 'classic'),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: 'Save & continue',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
            : null,
      ),
    );
  }
}
