import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:url_launcher/url_launcher.dart';

/// Seam for tests: the sheet launches share URIs through this.
typedef QuoteUrlLauncher = Future<bool> Function(Uri uri);

/// Immutable seed for the share sheet. The sheet owns the editable copy of
/// [message]; the seed is never mutated.
class QuoteShareRequest {
  const QuoteShareRequest({
    required this.message,
    this.customerPhone,
    this.customerEmail,
    this.businessName,
  });

  final String message;
  final String? customerPhone;
  final String? customerEmail;
  final String? businessName;
}

/// Shows the quotation share sheet. Returns the (possibly edited) quote text
/// when it was delivered through a channel — WhatsApp opened, email composer
/// opened, or copied to clipboard — and null when the user dismissed without
/// sharing. Callers must only record a quote_sent activity on a non-null
/// result.
Future<String?> showQuoteShareSheet(
  BuildContext context,
  QuoteShareRequest request, {
  QuoteUrlLauncher? launcher,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _QuoteShareSheetBody(
        request: request,
        launcher: launcher ??
            (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
      ),
    ),
  );
}

class _QuoteShareSheetBody extends StatefulWidget {
  const _QuoteShareSheetBody({required this.request, required this.launcher});

  final QuoteShareRequest request;
  final QuoteUrlLauncher launcher;

  @override
  State<_QuoteShareSheetBody> createState() => _QuoteShareSheetBodyState();
}

class _QuoteShareSheetBodyState extends State<_QuoteShareSheetBody> {
  late final TextEditingController _text =
      TextEditingController(text: widget.request.message);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 10-digit Indian mobile extracted from the raw phone, or null.
  String? get _waDigits {
    final raw = widget.request.customerPhone;
    if (raw == null) return null;
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    return RegExp(r'^[6-9]\d{9}$').hasMatch(digits) ? digits : null;
  }

  bool get _hasEmail => (widget.request.customerEmail ?? '').isNotEmpty;

  Future<void> _launch(Uri uri, String failMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _text.text.trim();
    bool launched = false;
    try {
      launched = await widget.launcher(uri);
    } catch (_) {}
    if (!mounted) return;
    if (!launched) {
      messenger.showSnackBar(SnackBar(content: Text(failMessage)));
      return;
    }
    Navigator.pop(context, text);
  }

  Future<void> _shareWhatsApp() async {
    final digits = _waDigits;
    final base = digits != null ? 'https://wa.me/91$digits' : 'https://wa.me/';
    final uri =
        Uri.parse('$base?text=${Uri.encodeComponent(_text.text.trim())}');
    await _launch(uri, 'Could not open WhatsApp');
  }

  Future<void> _shareEmail() async {
    final business = widget.request.businessName;
    final subject = business == null || business.isEmpty
        ? 'Quotation'
        : 'Quotation from $business';
    // Uri() encodes the address as a path segment, so a crafted email like
    // "a@x.com?cc=..." cannot inject extra mailto headers. Query is built with
    // encodeComponent (not queryParameters) so spaces become %20, not '+',
    // which some mail clients would show literally.
    final uri = Uri(
      scheme: 'mailto',
      path: widget.request.customerEmail,
      query: 'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(_text.text.trim())}',
    );
    await _launch(uri, 'No email app found. Use Copy instead.');
  }

  Future<void> _copy() async {
    final text = _text.text.trim();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Send quotation',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: TextField(
              controller: _text,
              maxLines: 10,
              minLines: 4,
              style: const TextStyle(fontSize: 13, height: 1.5),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                helperText: 'Edit the message before sending if needed',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  // No/invalid phone falls back to wa.me/ which opens the
                  // WhatsApp chat picker with the text prefilled (same as the
                  // legacy capture flow), so the button is always usable.
                  onPressed: _shareWhatsApp,
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _hasEmail ? _shareEmail : null,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('Email'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
