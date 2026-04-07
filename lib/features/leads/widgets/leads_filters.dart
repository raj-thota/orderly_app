import 'package:flutter/material.dart';

class LeadsFilters extends StatelessWidget {
  final String? selected;
  final String sort;
  final Function(String?) onChange;
  final Function(String) onSort;

  const LeadsFilters({
    super.key,
    required this.selected,
    required this.sort,
    required this.onChange,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = selected != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chip("Today"),
          _chip("Overdue"),
          const Spacer(),

          /// ✨ ANIMATED CLEAR BUTTON
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  child: child,
                ),
              );
            },
            child: hasFilter
                ? Padding(
                    key: const ValueKey("clear"),
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => onChange(null),
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        children: const [
                          Icon(Icons.close, size: 16, color: Colors.red),
                          SizedBox(width: 4),
                          Text(
                            "Clear",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey("empty")),
          ),

          /// 🔥 SORT TOGGLE
          InkWell(
            onTap: () {
              onSort(sort == "Latest" ? "Oldest" : "Latest");
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Text(
                    sort,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.swap_vert, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final isActive = selected == label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          if (isActive) {
            onChange(null);
          } else {
            onChange(label);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.deepPurple : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.deepPurple.withValues(alpha: 0.25 * 255),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: isActive ? Colors.white : Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}