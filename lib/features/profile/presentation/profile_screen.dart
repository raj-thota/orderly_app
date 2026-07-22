import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/auth/controller/user_provider.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_asset_service.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/invoices/presentation/invoice_settings_screen.dart';
import 'package:orderly_app/shared/widgets/app_screen_header.dart';
import 'package:orderly_app/shared/widgets/settings_tile.dart';

enum ProfileAnchor { payment }

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.scrollTo});
  final ProfileAnchor? scrollTo;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _paymentKey = GlobalKey();
  final _controllers = <String, TextEditingController>{};
  String? _editingField;
  bool _saving = false;
  BusinessProfile? _seeded;

  TextEditingController _ctl(String key, String initial) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(BusinessProfile Function(BusinessProfile) edit) async {
    final current = _seeded;
    if (current == null) return;
    setState(() => _saving = true);
    try {
      final service = ref.read(businessProfileServiceProvider);
      await service.upsert(edit(current));
      ref.invalidate(businessProfileProvider);
      ref.invalidate(businessSensitiveProvider);
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      setState(() {
        _editingField = null;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved ✅')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not save. Try again.')));
    }
  }

  Future<void> _uploadLogo() async {
    final url = await BusinessAssetService().pickAndUpload(kind: 'logo');
    if (url == null) return;
    await _save((p) => p.copyWith(logoUrl: url));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessProfileProvider);
    // Bank account number + PAN are encrypted at rest; read them back through
    // the owner-scoped RPC rather than the plain profile row.
    final sensitive = ref.watch(businessSensitiveProvider).value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appScreenHeader('Business Profile'),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load profile')),
        data: (profile) {
          final base = profile ?? const BusinessProfile(name: 'Your Business');
          // bank/PAN come back null from the plain select (encrypted at rest);
          // merge the decrypted values so edits to ANY field re-send the real
          // ones instead of relying on the trigger's null-preserves behaviour.
          final p = base.copyWith(
            pan: sensitive?.pan,
            bankAccountNumber: sensitive?.bankAccountNumber,
          );
          _seeded = p;
          if (widget.scrollTo == ProfileAnchor.payment) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = _paymentKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(ctx,
                    duration: const Duration(milliseconds: 300));
              }
            });
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            child: Column(
            children: [
              _header(p),
              _sectionCard('Business Information', [
                _field(p, 'business_name', 'Business Name', p.name,
                    (v) => (c) => c.copyWith(name: v)),
                _field(p, 'owner_name', 'Owner Name', p.ownerName ?? '',
                    (v) => (c) => c.copyWith(ownerName: v)),
                _field(p, 'phone', 'Phone', p.phone ?? '',
                    (v) => (c) => c.copyWith(phone: v),
                    keyboardType: TextInputType.phone),
                _field(p, 'email', 'Email', p.email ?? '',
                    (v) => (c) => c.copyWith(email: v),
                    keyboardType: TextInputType.emailAddress),
                _field(p, 'address', 'Address', p.address ?? '',
                    (v) => (c) => c.copyWith(address: v)),
                _field(p, 'city', 'City', p.city ?? '',
                    (v) => (c) => c.copyWith(city: v)),
                _field(p, 'state', 'State', p.state ?? '',
                    (v) => (c) => c.copyWith(state: v)),
                _field(p, 'pincode', 'Pincode', p.pincode ?? '',
                    (v) => (c) => c.copyWith(pincode: v),
                    keyboardType: TextInputType.number),
              ]),
              _sectionCard('Business Identity', [
                _field(p, 'gstin', 'GST Number (optional)', p.gstin ?? '',
                    (v) => (c) => c.copyWith(gstin: v)),
                _field(p, 'pan', 'PAN (optional)', p.pan ?? '',
                    (v) => (c) => c.copyWith(pan: v)),
                _field(p, 'business_type', 'Business Type', p.businessType ?? '',
                    (v) => (c) => c.copyWith(businessType: v)),
                ListTile(
                  leading: const Icon(Icons.image_rounded, color: AppColors.primary),
                  title: const Text('Business Logo'),
                  subtitle: Text(p.logoUrl == null ? 'Not set' : 'Uploaded'),
                  trailing: TextButton(
                      onPressed: _saving ? null : _uploadLogo,
                      child: const Text('Upload')),
                ),
              ]),
              Container(key: _paymentKey),
              _sectionCard('Payment Details', [
                _field(p, 'upi_id', 'UPI ID', p.upiId ?? '',
                    (v) => (c) => c.copyWith(upiId: v)),
                _field(p, 'upi_name', 'UPI Name', p.upiName ?? '',
                    (v) => (c) => c.copyWith(upiName: v)),
                _field(p, 'bank_account_name', 'Bank Account Name (optional)',
                    p.bankAccountName ?? '',
                    (v) => (c) => c.copyWith(bankAccountName: v)),
                _field(p, 'bank_account_number', 'Bank Account Number (optional)',
                    p.bankAccountNumber ?? '',
                    (v) => (c) => c.copyWith(bankAccountNumber: v),
                    keyboardType: TextInputType.number),
                _field(p, 'bank_ifsc', 'IFSC (optional)', p.bankIfsc ?? '',
                    (v) => (c) => c.copyWith(bankIfsc: v)),
                if ((p.upiId ?? '').isNotEmpty) _qr(p),
              ]),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: SettingsTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Invoice Settings',
                  subtitle: 'Prefix, tax, footer, logo',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen())),
                ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BusinessProfile p) {
    final meta = ref.watch(userProfileProvider).value;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _saving ? null : _uploadLogo,
            child: CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.surfaceMuted,
              backgroundImage: p.logoUrl != null ? NetworkImage(p.logoUrl!) : null,
              child: p.logoUrl == null
                  ? const Icon(Icons.storefront_rounded, color: AppColors.primary)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(meta?['email'] ?? p.email ?? '',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                top: AppSpacing.lg, bottom: AppSpacing.sm, left: AppSpacing.xs),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BusinessProfile p,
    String key,
    String label,
    String value,
    BusinessProfile Function(BusinessProfile) Function(String) editFactory, {
    TextInputType? keyboardType,
  }) {
    final editing = _editingField == key;
    final controller = _ctl(key, value);
    if (!editing) controller.text = value;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: editing
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType,
                    decoration: InputDecoration(
                        isDense: true, border: InputBorder.none, labelText: label),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(value.isEmpty ? 'Not set' : value,
                          style: const TextStyle(fontSize: 15)),
                    ],
                  ),
          ),
          _saving && editing
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  tooltip: editing ? 'Save' : 'Edit',
                  icon: Icon(editing ? Icons.check_rounded : Icons.edit_outlined,
                      size: 18, color: AppColors.primary),
                  onPressed: () {
                    if (editing) {
                      _save(editFactory(controller.text.trim()));
                    } else {
                      setState(() => _editingField = key);
                    }
                  },
                ),
        ],
      ),
    );
  }

  Widget _qr(BusinessProfile p) {
    final uri =
        'upi://pay?pa=${p.upiId}&pn=${Uri.encodeComponent(p.upiName ?? p.name)}';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const Text('UPI QR Preview',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          QrImageView(
            key: const Key('upi-qr'),
            data: uri,
            size: 140,
            backgroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
