import 'package:flutter/material.dart';

class LeadsTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final Function(int) onChange;
  final Function(int) getCount;

  const LeadsTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChange,
    required this.getCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment(
                -1 + (2 * selectedIndex / (tabs.length - 1)),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / tabs.length,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            Row(
              children: List.generate(tabs.length, (index) {
                final isSelected = index == selectedIndex;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChange(index),
                    child: Center(
                      child: Text(
                        "${tabs[index]} (${getCount(index)})",
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
