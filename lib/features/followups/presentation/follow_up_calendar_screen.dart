import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';
import 'package:orderly_app/features/followups/controller/follow_up_calendar_provider.dart';
import 'package:orderly_app/features/followups/data/follow_up.dart';

const _dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class FollowUpCalendarScreen extends ConsumerStatefulWidget {
  const FollowUpCalendarScreen({super.key});

  @override
  ConsumerState<FollowUpCalendarScreen> createState() =>
      _FollowUpCalendarScreenState();
}

class _FollowUpCalendarScreenState
    extends ConsumerState<FollowUpCalendarScreen> {
  int _selectedDayIndex = 0; // 0=Mon … 6=Sun within current weekStart

  @override
  void initState() {
    super.initState();
    // Select today's day within the week by default.
    final now = DateTime.now();
    _selectedDayIndex = (now.weekday - 1).clamp(0, 6);
  }

  DateTime _dayAt(DateTime weekStart, int index) =>
      weekStart.add(Duration(days: index));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(followUpCalendarProvider);
    final weekStart = state.weekStart;
    final selectedDay = _dayAt(weekStart, _selectedDayIndex);
    final dayItems = state.followUpsForDay(selectedDay);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Follow-up Calendar'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (state.loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: Column(
        children: [
          _WeekHeader(
            weekStart: weekStart,
            selectedIndex: _selectedDayIndex,
            onDayTap: (i) => setState(() => _selectedDayIndex = i),
            onPrev: () => ref.read(followUpCalendarProvider.notifier).prevWeek(),
            onNext: () => ref.read(followUpCalendarProvider.notifier).nextWeek(),
          ),
          const Divider(height: 1),
          Expanded(
            child: dayItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_available_rounded,
                            size: 48, color: AppColors.textSecondary),
                        SizedBox(height: AppSpacing.md),
                        Text('No follow-ups for this day',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: dayItems.length,
                    separatorBuilder: (context, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _FollowUpCard(
                      followUp: dayItems[i],
                      onDone: () => ref
                          .read(followUpCalendarProvider.notifier)
                          .markDone(dayItems[i].id),
                      onSkip: () => ref
                          .read(followUpCalendarProvider.notifier)
                          .markSkipped(dayItems[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.weekStart,
    required this.selectedIndex,
    required this.onDayTap,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime weekStart;
  final int selectedIndex;
  final void Function(int) onDayTap;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final monthLabel =
        '${_monthAbbr[weekStart.month - 1]} ${weekStart.year}';
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: onPrev,
                color: AppColors.textPrimary,
              ),
              Text(monthLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onNext,
                color: AppColors.textPrimary,
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(child: _DayCell(
                  abbr: _dayAbbr[i],
                  day: weekStart.add(Duration(days: i)).day,
                  selected: i == selectedIndex,
                  onTap: () => onDayTap(i),
                )),
            ],
          ),
        ],
      ),
    );
  }

  static const _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.abbr,
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final String abbr;
  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: selected
            ? BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Column(
          children: [
            Text(abbr,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text('$day',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w400,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({
    required this.followUp,
    required this.onDone,
    required this.onSkip,
  });

  final FollowUp followUp;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withAlpha(20),
            child: Text(
              (followUp.customerName ?? '?').characters.first.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  followUp.customerName ?? 'Customer',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                if (followUp.note != null)
                  Text(followUp.note!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                Text(
                  _kindLabel(followUp.kind),
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            children: [
              FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Done',
                    style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Skip',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _kindLabel(String kind) {
    switch (kind) {
      case 'payment':
        return 'Payment follow-up';
      case 'reply':
        return 'Reply follow-up';
      default:
        return 'General follow-up';
    }
  }
}
