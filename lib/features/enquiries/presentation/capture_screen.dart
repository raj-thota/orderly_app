import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/shared/widgets/app_primary_button.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../controller/capture_provider.dart';
import '../controller/enquiries_provider.dart';
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

  Future<void> _save() async {
    final controller = ref.read(captureControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await controller.save();
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      ref.read(enquiriesControllerProvider.notifier).load();
      messenger.showSnackBar(SnackBar(
        content: Text(result.kind == SaveKind.order
            ? 'Order created for ${result.customerName}'
            : 'Enquiry saved for ${result.customerName}'),
      ));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);
    final draft = state.draft;
    final controller = ref.read(captureControllerProvider.notifier);
    final hasContent = !draft.isEmpty || state.attachedProductId != null;

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
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasContent) ...[
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
          ],
        ],
      ),
    );
  }
}
