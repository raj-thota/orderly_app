import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 58,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(child: navItem(Icons.home_rounded, "Home", 0)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.people_alt_rounded, "Enquiries", 1)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.shopping_bag_rounded, "Orders", 2)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.storefront_rounded, "Catalog", 3)),
            const SizedBox(width: 8),
            Expanded(child: navItem(Icons.receipt_long_rounded, "Invoices", 4)),
          ],
        ),
      ),
    );
  }

  Widget navItem(IconData icon, String label, int index) {
    final isSelected = index == currentIndex;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isSelected ? null : () => onTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6C4ED9).withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF6C4ED9) : Colors.grey,
                size: 20,
              ),
              Flexible(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: isSelected
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6C4ED9),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
