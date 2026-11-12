import 'package:flutter/material.dart';

/// A native macOS Apple Books-style horizontal carousel shelf.
/// Features:
/// - Smooth horizontal scrolling.
/// - Edge fade gradient indicators on left/right when scrollable content extends beyond viewport.
/// - Frosted circular navigation buttons on left/right that appear smoothly on hover.
class HorizontalBookShelf extends StatefulWidget {
  final String title;
  final Widget? action;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double itemSpacing;

  const HorizontalBookShelf({
    super.key,
    required this.title,
    this.action,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 270,
    this.itemSpacing = 18,
  });

  @override
  State<HorizontalBookShelf> createState() => _HorizontalBookShelfState();
}

class _HorizontalBookShelfState extends State<HorizontalBookShelf> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(HorizontalBookShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;
    final canLeft = offset > 4.0;
    final canRight = offset < maxScroll - 4.0;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgGradientColor = isDark
        ? const Color(0xFF131315)
        : const Color(0xFFF9F9FB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shelf Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.action != null) ...[
              const SizedBox(width: 8),
              widget.action!,
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Shelf Viewport with Edge Fade & Hover Arrows
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Scrollable items
                ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, index) =>
                      SizedBox(width: widget.itemSpacing),
                  itemBuilder: widget.itemBuilder,
                ),

                // Left Edge Fade Gradient
                if (_canScrollLeft)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 36,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              bgGradientColor,
                              bgGradientColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Right Edge Fade Gradient
                if (_canScrollRight)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 36,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              bgGradientColor,
                              bgGradientColor.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Left Arrow Button
                if (_canScrollLeft)
                  Positioned(
                    left: 4,
                    top: 0,
                    bottom: 50,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: _buildScrollButton(
                          icon: Icons.chevron_left_rounded,
                          tooltip: 'Geser ke kiri',
                          onPressed: () => _scroll(-280),
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                // Right Arrow Button
                if (_canScrollRight)
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 50,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: _buildScrollButton(
                          icon: Icons.chevron_right_rounded,
                          tooltip: 'Geser ke kanan',
                          onPressed: () => _scroll(280),
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScrollButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withAlpha(200)
                  : Colors.white.withAlpha(235),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(30)
                    : Colors.black.withAlpha(25),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 80 : 30),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 22,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
