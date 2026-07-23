import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/contacts_service.dart';
import 'package:orderly_app/features/subscription/controller/subscription_provider.dart';
import 'package:orderly_app/features/subscription/presentation/subscription_screen.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'extraction_progress_screen.dart';

enum _CaptureSource { paste, screenshot, voice, manual }

class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CaptureSheet(),
    );
  }

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  _CaptureSource? _source;
  final _textCtrl = TextEditingController();
  final _speech = SpeechToText();
  Timer? _debounce;
  bool _listening = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.stop();
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(captureControllerProvider.notifier).setText(_textCtrl.text);
    });
  }

  Future<void> _pickSource(_CaptureSource src) async {
    // AI capture (paste/screenshot/voice) is a Pro feature; manual entry is
    // always free. Gated users get sent to the paywall instead of a silent
    // AI run they can't pay for. Closes the capture monetization bypass.
    if (src != _CaptureSource.manual && !ref.read(aiAccessProvider)) {
      final navigator = Navigator.of(context);
      navigator.pop(); // close the capture sheet first
      navigator.push(
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
      return;
    }
    switch (src) {
      case _CaptureSource.paste:
        setState(() => _source = src);
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && data!.text!.isNotEmpty) {
          _textCtrl.text = data.text!;
          ref.read(captureControllerProvider.notifier).setText(data.text!);
        }
      case _CaptureSource.screenshot:
        await _pickScreenshot();
      case _CaptureSource.voice:
        setState(() => _source = src);
        await _startListening();
      case _CaptureSource.manual:
        setState(() => _source = src);
    }
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() => _source = _CaptureSource.screenshot);
    final bytes = await FlutterImageCompress.compressWithFile(
      file.path,
      quality: 70,
      format: CompressFormat.jpeg,
    );
    if (bytes == null || !mounted) return;
    ref
        .read(captureControllerProvider.notifier)
        .attachScreenshot(bytes, path: file.path);
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (!available || !mounted) return;
    setState(() => _listening = true);
    _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        _textCtrl.text = r.recognizedWords;
        ref.read(captureControllerProvider.notifier).setText(r.recognizedWords);
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _listening = false);
  }

  void _proceed() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ExtractionProgressScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);
    final hasContent =
        !state.draft.isEmpty ||
        state.screenshotBytes != null ||
        _textCtrl.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Handle(),
          _Header(),
          if (_source == null)
            _SourcePicker(
              onTap: _pickSource,
              gated: !ref.watch(aiAccessProvider),
            ),
          if (_source != null) ...[
            if (_source == _CaptureSource.manual)
              const _ManualForm()
            else
              _InputArea(
                source: _source!,
                textCtrl: _textCtrl,
                listening: _listening,
                onTextChanged: _onTextChanged,
                onToggleVoice: _listening
                    ? _stopListening
                    : () => _startListening(),
                screenshotBytes: state.screenshotBytes,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: FilledButton(
                onPressed: hasContent ? _proceed : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Review & Confirm',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    child: Row(
      children: [
        const Text(
          'Add to My Work',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.onTap, required this.gated});
  final void Function(_CaptureSource) onTap;
  final bool gated;

  @override
  Widget build(BuildContext context) {
    const sources = [
      (_CaptureSource.paste, Icons.content_paste_rounded, 'Paste Chat'),
      (_CaptureSource.screenshot, Icons.image_rounded, 'Screenshot'),
      (_CaptureSource.voice, Icons.mic_rounded, 'Voice Note'),
      (_CaptureSource.manual, Icons.edit_rounded, 'Manual Entry'),
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 2.2,
        children: [
          for (final (src, icon, label) in sources)
            _SourceCard(
              source: src,
              icon: icon,
              label: label,
              onTap: onTap,
              // Manual entry is free; AI sources show a Pro lock when gated.
              locked: gated && src != _CaptureSource.manual,
            ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.icon,
    required this.label,
    required this.onTap,
    this.locked = false,
  });
  final _CaptureSource source;
  final IconData icon;
  final String label;
  final void Function(_CaptureSource) onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: locked ? '$label, Pro feature' : label,
    child: InkWell(
      onTap: () => onTap(source),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.lock_outline,
                color: AppColors.textSecondary,
                size: 14,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Structured manual add: the user types the customer directly, so name and
/// phone are captured as fields (never inferred by the chat parser). Each field
/// feeds the shared [CaptureController] — name/phone become manual values the AI
/// refine cannot overwrite; the optional description still drives items/intent.
class _ManualForm extends ConsumerStatefulWidget {
  const _ManualForm();

  @override
  ConsumerState<_ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends ConsumerState<_ManualForm> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Timer? _descDebounce;

  @override
  void dispose() {
    _descDebounce?.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  CaptureController get _controller =>
      ref.read(captureControllerProvider.notifier);

  void _onDescChanged(String v) {
    // Debounce: the description drives an AI refine, so avoid firing per key.
    _descDebounce?.cancel();
    _descDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _controller.setText(v);
    });
  }

  Future<void> _pickContact() async {
    final messenger = ScaffoldMessenger.of(context);
    final ContactPick? pick;
    try {
      pick = await ref.read(contactsServiceProvider).pickContact();
    } on ContactPickException {
      // A real failure (permission denied / OS error) — tell the user instead
      // of leaving the icon looking dead.
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              "Couldn't open contacts. Allow Contacts access in Settings."),
        ),
      );
      return;
    }
    if (!mounted || pick == null) return; // user cancelled the picker
    // Returning from the picker restores focus to the autofocused name field,
    // popping the keyboard back over the now-filled form. Drop it so the user
    // sees the prefilled values.
    FocusScope.of(context).unfocus();
    if (pick.name != null) {
      _nameCtrl.text = pick.name!;
      _controller.setName(pick.name!);
    }
    if (pick.phone != null) {
      _phoneCtrl.text = pick.phone!;
      _controller.setPhone(pick.phone!);
    }
    if (pick.name == null && pick.phone == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That contact has no name or number')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            controller: _nameCtrl,
            hint: 'Customer name',
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: _controller.setName,
            // Contact picker lives inline on the right of the name field — one
            // line, no separate full-width button above it.
            suffixIcon: IconButton(
              tooltip: 'Pick from Contacts',
              icon: const Icon(Icons.contacts_outlined,
                  size: 20, color: AppColors.primary),
              onPressed: _pickContact,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Field(
            controller: _phoneCtrl,
            hint: 'Phone number',
            keyboardType: TextInputType.phone,
            onChanged: _controller.setPhone,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Field(
            controller: _descCtrl,
            hint: 'What they want (optional)',
            maxLines: 3,
            onChanged: _onDescChanged,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    keyboardType: keyboardType,
    maxLines: maxLines,
    autofocus: autofocus,
    textCapitalization: textCapitalization,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}

class _InputArea extends StatelessWidget {
  const _InputArea({
    required this.source,
    required this.textCtrl,
    required this.listening,
    required this.onTextChanged,
    required this.onToggleVoice,
    this.screenshotBytes,
  });

  final _CaptureSource source;
  final TextEditingController textCtrl;
  final bool listening;
  final VoidCallback onTextChanged;
  final VoidCallback onToggleVoice;
  final Object? screenshotBytes; // Uint8List

  @override
  Widget build(BuildContext context) {
    if (source == _CaptureSource.screenshot && screenshotBytes == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: Text(
            'Picking screenshot…',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source == _CaptureSource.voice)
            Row(
              children: [
                Icon(
                  listening ? Icons.mic : Icons.mic_off,
                  color: listening ? AppColors.danger : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  listening ? 'Listening…' : 'Tap mic to record',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    listening ? Icons.stop : Icons.mic,
                    color: AppColors.primary,
                  ),
                  onPressed: onToggleVoice,
                ),
              ],
            ),
          TextField(
            controller: textCtrl,
            onChanged: (_) => onTextChanged(),
            maxLines: 6,
            autofocus: source == _CaptureSource.paste,
            decoration: InputDecoration(
              hintText: 'Paste WhatsApp chat here…',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
