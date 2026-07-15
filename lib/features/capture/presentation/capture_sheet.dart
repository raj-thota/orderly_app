import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
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
    _speech.listen(onResult: (r) {
      if (!mounted) return;
      _textCtrl.text = r.recognizedWords;
      ref
          .read(captureControllerProvider.notifier)
          .setText(r.recognizedWords);
    });
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _listening = false);
  }

  void _proceed() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ExtractionProgressScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);
    final hasContent = !state.draft.isEmpty ||
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
          if (_source == null) _SourcePicker(onTap: _pickSource),
          if (_source != null) ...[
            _InputArea(
              source: _source!,
              textCtrl: _textCtrl,
              listening: _listening,
              onTextChanged: _onTextChanged,
              onToggleVoice:
                  _listening ? _stopListening : () => _startListening(),
              screenshotBytes: state.screenshotBytes,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
              child: FilledButton(
                onPressed: hasContent ? _proceed : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Review & Confirm',
                    style: TextStyle(color: Colors.white)),
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
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            const Text('Add to My Work',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.onTap});
  final void Function(_CaptureSource) onTap;

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
            _SourceCard(source: src, icon: icon, label: label, onTap: onTap),
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
  });
  final _CaptureSource source;
  final IconData icon;
  final String label;
  final void Function(_CaptureSource) onTap;

  @override
  Widget build(BuildContext context) => InkWell(
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
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
            ],
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
            child: Text('Picking screenshot…',
                style: TextStyle(color: AppColors.textSecondary))),
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
                  icon: Icon(listening ? Icons.stop : Icons.mic,
                      color: AppColors.primary),
                  onPressed: onToggleVoice,
                ),
              ],
            ),
          TextField(
            controller: textCtrl,
            onChanged: (_) => onTextChanged(),
            maxLines: source == _CaptureSource.manual ? 4 : 6,
            autofocus: source == _CaptureSource.paste ||
                source == _CaptureSource.manual,
            decoration: InputDecoration(
              hintText: source == _CaptureSource.manual
                  ? 'Customer name, phone, what they want…'
                  : 'Paste WhatsApp chat here…',
              hintStyle:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 14),
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
