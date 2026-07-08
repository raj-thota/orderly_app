import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/core/theme/app_spacing.dart';

import '../controller/enquiries_provider.dart';
import '../data/enquiry.dart';
import '../widgets/enquiry_card.dart';
import 'enquiry_detail_screen.dart';

class EnquiriesScreen extends ConsumerStatefulWidget {
  const EnquiriesScreen({super.key});

  @override
  ConsumerState<EnquiriesScreen> createState() => _EnquiriesScreenState();
}

class _EnquiriesScreenState extends ConsumerState<EnquiriesScreen> {
  String _search = '';

  static const _bucketOrder = [
    (EnquiryBucket.overdue, 'Overdue'),
    (EnquiryBucket.today, 'Today'),
    (EnquiryBucket.upcoming, 'Upcoming'),
    (EnquiryBucket.fresh, 'New'),
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(enquiriesControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text(
                'Enquiries',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                key: const Key('enquiry-search'),
                onChanged: (v) =>
                    setState(() => _search = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search customers or messages',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load enquiries'),
                      TextButton(
                        onPressed: () => ref
                            .read(enquiriesControllerProvider.notifier)
                            .load(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (all) {
                  final filtered = _search.isEmpty
                      ? all
                      : all.where((e) {
                          final hay =
                              '${e.customerName ?? ''} ${e.message ?? ''}'
                                  .toLowerCase();
                          return hay.contains(_search);
                        }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No enquiries yet.\nTap + to capture your first one.'
                            : 'No matches for "$_search".',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  final now = DateTime.now();
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(enquiriesControllerProvider.notifier).load(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.md, AppSpacing.lg, 96),
                      children: [
                        for (final (bucket, label) in _bucketOrder)
                          ..._section(label,
                              [for (final e in filtered) if (e.bucket(now) == bucket) e]),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String label, List<Enquiry> items) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(
            top: AppSpacing.md, bottom: AppSpacing.sm),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary),
        ),
      ),
      for (final e in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: EnquiryCard(
            enquiry: e,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EnquiryDetailScreen(enquiry: e)),
            ),
          ),
        ),
    ];
  }
}
