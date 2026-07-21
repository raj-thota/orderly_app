import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orderly_app/core/services/event_service.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/capture_provider.dart';
import '../widgets/draft_card.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({
    super.key,
    this.productId,
    this.productName,
    this.productIsUnique = false,
    this.productPrice = 0,
  });

  /// When set, the capture starts with this product attached (product-first
  /// enquiry from the catalog).
  final String? productId;
  final String? productName;
  final bool productIsUnique;
  final double productPrice;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _text = TextEditingController();
  final _speech = SpeechToText();
  Timer? _debounce;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
    if (widget.productId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(captureControllerProvider.notifier).attachProduct(
              id: widget.productId!,
              name: widget.productName ?? 'Piece',
              isUnique: widget.productIsUnique,
              price: widget.productPrice,
            );
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.stop();
    _text.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(captureControllerProvider.notifier).setText(_text.text);
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _text.text = text;
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      onStatus: (status) {
        if (mounted && status != 'listening') {
          setState(() => _listening = false);
        }
      },
    );
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone not available')),
      );
      return;
    }
    setState(() => _listening = true);
    _speech.listen(onResult: (r) => _text.text = r.recognizedWords);
  }

  Future<void> _editField({
    required String title,
    required String initial,
    required void Function(String value) onSubmit,
    TextInputType keyboard = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
            controller: controller, keyboardType: keyboard, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) onSubmit(value);
  }

  Future<void> _pickFollowUp() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final controller = ref.read(captureControllerProvider.notifier);
    final draft = ref.read(captureControllerProvider).draft;
    controller.editDraft(
        draft.copyWith(followUpDate: picked, intent: 'follow_up'));
  }

  Future<void> _attachScreenshot() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final compressed = await FlutterImageCompress.compressWithFile(
      picked.path,
      minWidth: 1280,
      minHeight: 1280,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    final bytes = compressed ?? await picked.readAsBytes();
    if (!mounted) return;
    ref.read(captureControllerProvider.notifier).attachScreenshot(
          Uint8List.fromList(bytes),
          path: picked.path,
        );
  }

  Future<void> _sendQuote() async {
    final profile = ref.read(businessProfileProvider).valueOrNull;
    final products =
        ref.read(productsControllerProvider).valueOrNull ?? const [];
    final controller = ref.read(captureControllerProvider.notifier);
    final draft = ref.read(captureControllerProvider).draft;

    final quote = controller.buildQuotation(
      businessName: profile?.name ?? 'My Shop',
      upiId: profile?.upiId,
      upiName: profile?.upiName,
      products: products,
    );

    final messenger = ScaffoldMessenger.of(context);
    final send = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Quotation preview',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(quote.message),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(
              label: 'Share on WhatsApp',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );

    if (send != true || !mounted) return;

    final phone = draft.phone;
    final validPhone =
        phone != null && RegExp(r'^[6-9]\d{9}$').hasMatch(phone);
    final waBase =
        validPhone ? 'https://wa.me/91$phone' : 'https://wa.me/';
    final uri = Uri.parse('$waBase?text=${Uri.encodeComponent(quote.message)}');

    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    if (!launched) {
      // Never record a quote_sent activity when WhatsApp did not open.
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
      return;
    }

    try {
      final result = await controller.save(quoteText: quote.message);
      if (!mounted) return;
      refreshAfterCapture(ref);
      ref.read(eventServiceProvider).track(
          result.kind == SaveKind.order ? 'order_created' : 'enquiry_created');
      if (Navigator.canPop(context)) Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Quote shared and enquiry saved')),
      );
    } catch (e) {
      debugPrint('capture save failed after quote: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Shared, but could not save. Try again.')),
      );
    }
  }

  Future<void> _save() async {
    final controller = ref.read(captureControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await controller.save();
      if (!mounted) return;
      // One shared refresh (enquiries, orders, work items) + follow-up
      // reminders, run while `ref` is still mounted, before we pop.
      refreshAfterCapture(ref);
      ref.read(eventServiceProvider).track(
          result.kind == SaveKind.order ? 'order_created' : 'enquiry_created');
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(result.kind == SaveKind.order
            ? 'Order created for ${result.customerName}'
            : 'Enquiry saved for ${result.customerName}'),
      ));
    } catch (e) {
      debugPrint('capture save failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);
    final draft = state.draft;
    final controller = ref.read(captureControllerProvider.notifier);
    // Warm the providers the quote action reads so they are loaded on tap.
    ref.watch(businessProfileProvider);
    ref.watch(productsControllerProvider);
    final hasContent = !draft.isEmpty ||
        state.attachedProductId != null ||
        state.screenshotBytes != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Capture')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            key: const Key('capture-input'),
            controller: _text,
            maxLines: 6,
            autofocus: true,
            decoration: InputDecoration(
              hintText:
                  'Paste the WhatsApp chat, speak, or type what the customer wants…',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste'),
              ),
              TextButton.icon(
                onPressed: _toggleMic,
                icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                    size: 18,
                    color: _listening ? AppColors.danger : null),
                label: Text(_listening ? 'Stop' : 'Speak'),
              ),
              TextButton.icon(
                onPressed: _attachScreenshot,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Screenshot'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasContent) ...[
            if (state.screenshotBytes != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.memory(
                      state.screenshotBytes!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: controller.clearScreenshot,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            DraftCard(
              draft: draft,
              attachedProductName: state.attachedProductName,
              highlightedFields: state.aiHighlight,
              onEditName: () => _editField(
                title: 'Customer name',
                initial: draft.name ?? '',
                onSubmit: (v) => controller.setName(v),
              ),
              onEditPhone: () => _editField(
                title: 'Phone',
                initial: draft.phone ?? '',
                keyboard: TextInputType.phone,
                onSubmit: (v) => controller.setPhone(v),
              ),
              onEditFollowUp: _pickFollowUp,
              onRemoveItem: (i) => controller.removeItem(i),
            ),
            if (state.aiRefining)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: AppSpacing.sm),
                    Text('AI refining…',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(
              label: draft.type == 'order' && draft.items.isNotEmpty
                  ? 'Create order'
                  : 'Save enquiry',
              loading: state.saving,
              onPressed: _save,
            ),
            if (draft.items.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _sendQuote,
                icon: const Icon(Icons.request_quote_outlined, size: 18),
                label: const Text('Send quote'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
