import 'package:flutter/material.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.body,
    required this.direction,
    this.isAiSend = false,
    this.sentAt,
  });

  final String body;
  final String direction; // 'inbound' | 'outbound'
  final bool isAiSend;
  final DateTime? sentAt;

  bool get _isInbound => direction == 'inbound';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            _isInbound ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_isInbound) const SizedBox(width: 48),
          Flexible(
            child: Column(
              crossAxisAlignment: _isInbound
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                if (isAiSend)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.auto_awesome_rounded,
                            size: 12, color: AppColors.primary),
                        SizedBox(width: 3),
                        Text(
                          'AI drafted',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _isInbound
                        ? AppColors.surface
                        : isAiSend
                            ? AppColors.aiSurface
                            : AppColors.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(_isInbound ? 4 : 16),
                      bottomRight: Radius.circular(_isInbound ? 16 : 4),
                    ),
                    border: _isInbound
                        ? Border.all(color: AppColors.border)
                        : null,
                  ),
                  child: Text(
                    body,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isInbound
                          ? AppColors.textPrimary
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isInbound) const SizedBox(width: 48),
        ],
      ),
    );
  }
}
