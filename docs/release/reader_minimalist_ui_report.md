# Digital Books — Minimalist Apple Books-Inspired Reader UI Report

**Phase:** Reader Minimalist UI Refinement<br/>
**Date:** 2026-11-12<br/>
**Author:** Senior macOS Flutter UI Engineer & Product Designer<br/>
**Status:** PASS<br/>

---

## 1. Executive Summary

This milestone completely transforms Digital Books' reading environment from a dashboard-style reader into a minimalist, content-focused, and immersive reading experience inspired by **Apple Books on macOS**.

Key architectural and UX achievements:
1. **Unified macOS Title Bar Integration:** Eliminated the bulky floating top card. Integrated the reader top controls with the native macOS window title bar via `titlebarAppearsTransparent = true` and `styleMask.insert(.fullSizeContentView)`. Top chrome now spans the full window width at a slim 44.0 dp height with a translucent frosted glass backdrop (`BackdropFilter` with blur $\sigma = 20.0$), a 0.5 dp hairline divider, and guaranteed traffic-light clearance ($\ge 80.0\text{dp}$ on macOS).
2. **Slim Flush Bottom Reading Bar:** Replaced the oversized floating bottom card (~80 dp) with a flush, single-row 32.0 dp bar. It integrates a compact page counter (e.g., `Page 1 of 180`), a delicate 2.5 dp slider scrubber with a 4.5 dp thumb, and percentage indicator, maximizing vertical reading space.
3. **Auto-Hide & Edge Hover State Machine:** The controls automatically glide offscreen after 3.2 seconds of inactivity (`top: -100.0`, `bottom: -100.0`, `opacity: 0.0`, `ignoring: true`). Hovering within 56 dp of the top or 48 dp of the bottom smoothly reveals the chrome. Hovering directly over the bars pauses the timer; tapping the reading canvas toggles controls; active modal dialogs/sheets (TOC, Search, Appearance, Annotations) pause auto-hide entirely.
4. **Hover Navigation Chevrons:** Left and right desktop page-turn chevrons now have a resting opacity of 0.0, completely removing visual clutter from the book margins. They fade in smoothly (200 ms) when the cursor hovers within the outer margin zones and fade out on exit.
5. **Zero Layout Shift:** Content positioning is completely decoupled from control visibility. Hiding and showing controls never causes reflow, jumping, or re-pagination of the book.

---

## 2. Problem Statement & Root Cause Analysis

Prior to this refinement:
1. **Top Obstruction:** The previous top toolbar was a floating rounded card (~60 dp tall with 16 dp margins) positioned over the top of the canvas. In Book Mode and Original PDF, this card physically obscured chapter openers, page headers, or the initial lines of text unless excessive inner padding was applied.
2. **Bottom Space Consumption:** The bottom control panel was an ~80 dp multi-element container taking up substantial vertical space. On laptops and standard desktop windows, this severely compressed the reading viewport, forcing fewer lines of text per page and increasing page turns.
3. **Margin Clutter:** Floating navigation chevrons were permanently rendered in both left and right margins with solid/semi-translucent discs. While convenient, their constant presence distracted from the prose and broke immersion.
4. **Window Decoupling:** The macOS window displayed a standard gray or opaque title bar above the Flutter view, and Flutter drew a second toolbar beneath it, creating an awkward double-header aesthetic inconsistent with modern macOS applications like Apple Books, Safari, or Notes.

---

## 3. Design & Architecture Philosophy

### A. Immersive Canvas First
The book content is the sovereign element of the interface. When reading, chrome should vanish completely. The full window height ($100\%$) is dedicated to the page canvas, with top and bottom bars floating non-destructively above the canvas in an overlay stack.

### B. Translucent Frosted Glass Materials
Both the top and bottom bars utilize dynamic theme-adaptive frosted glass:
- **Light Theme:** `Colors.white.withAlpha(210)` with blur $\sigma = 20.0$, subtle hairline border `Colors.black.withAlpha(18)`.
- **Sepia Theme:** `Color(0xFFFBF0D9).withAlpha(220)` with blur $\sigma = 20.0$, hairline border `Color(0xFF5B4636).withAlpha(25)`.
- **Dark/Black Theme:** `Colors.black.withAlpha(195)` with blur $\sigma = 20.0$, hairline border `Colors.white.withAlpha(25)`.

### C. macOS Window Integration
By modifying `MainFlutterWindow.swift` in `macos/Runner/`:
```swift
self.titlebarAppearsTransparent = true
self.titleVisibility = .hidden
self.styleMask.insert(.fullSizeContentView)
self.isMovableByWindowBackground = true
```
Flutter renders continuously from the absolute top of the physical display window ($y = 0$). Window dragging is enabled natively via `isMovableByWindowBackground` and Flutter's unified top bar.

---

## 4. Component Breakdown & Geometry

### A. Unified Top Title Bar
- **Dimensions:** Width $100\%$ full span, Height $44.0\text{dp}$.
- **macOS Traffic Light Clearance:** On `TargetPlatform.macOS`, the leading element has `leftPadding: 80.0 dp`, guaranteeing that the native macOS Close, Minimize, and Zoom traffic light buttons ($x \approx 0..72\text{dp}$) never overlap the Back button or title. On iOS, Android, and Web, compact padding ($8.0\text{dp}$) is applied.
- **Center Hierarchy:** Book title is rendered in high-legibility medium weight ($13.5\text{pt}$), centered horizontally with truncation. Chapter title/subtitle is rendered underneath in secondary color ($11\text{pt}$).
- **Action Cluster:** Compact, unbordered icon buttons ($32 \times 32\text{dp}$, icon size $18\text{dp}$):
  - TOC (`reader_toc_button`)
  - In-Book Search (`reader_search_button`)
  - Appearance / Typography Settings (`reader_appearance_button`)
  - Annotations & Notes (`reader_annotations_button`)
  - Bookmark toggle (`reader_bookmark_button`)
  - Enhancement toggle (`reader_enhancement_toggle`, scanned mode)
  - Book/PDF mode segmented pill (`_ModePillButton`)

### B. Slim Bottom Progress Bar
- **Dimensions:** Width $100\%$ full span, Height $32.0\text{dp}$, flush at $y = \text{height} - 32\text{dp}$.
- **Scrubber Slider:** Custom `SliderThemeData` with `trackHeight: 2.5 dp`, `thumbShape: RoundSliderThumbShape(enabledThumbRadius: 4.5 dp)`, and `overlayShape: RoundSliderOverlayShape(overlayRadius: 10.0 dp)`.
- **Typography:** Page indicator (`Page X of Y`) and percentage (`Z%`) rendered in $11.0\text{pt}$ tabular-friendly typography.

### C. Edge Hover & Auto-Hide State Machine
- **Inactivity Timer:** 3.2 seconds.
- **Offscreen Positioning:**
  - Top Bar: `AnimatedPositioned(top: _showControls ? 0.0 : -100.0, duration: 250ms)`.
  - Bottom Bar: `AnimatedPositioned(bottom: _showControls ? 0.0 : -100.0, duration: 250ms)`.
  - Wrapped in `AnimatedOpacity(opacity: _showControls ? 1.0 : 0.0)` and `IgnorePointer(ignoring: !_showControls)`.
- **Edge Reveal Zones:**
  - Mouse near top edge ($y \le 56.0\text{dp}$) reveals chrome.
  - Mouse near bottom edge ($y \ge \text{height} - 48.0\text{dp}$) reveals chrome.
- **Direct Hover Pause:** Hovering over the top or bottom bar (`_isTopHovered` or `_isBottomHovered`) cancels the timer, keeping controls visible indefinitely while interacting.
- **Modal Safety:** Opening Appearance, TOC, Search, or Annotations sets `_isModalActive = true`, preventing premature auto-hide. Upon closing, the timer resets cleanly.

### D. Hover Chevrons (Reflowable & Original PDF)
- **Resting Opacity:** `0.0`.
- **Hover Detection:** Outer margin zones ($15\%$ on reflowable, $56\text{dp}$ on PDF reader) detect cursor entry.
- **Animation:** `AnimatedOpacity(duration: Duration(milliseconds: 200), opacity: _isHovering ? 1.0 : 0.0)`.
- **Non-interfering:** Wrapped in `IgnorePointer(ignoring: !_isHovering)` when invisible.

---

## 5. Files Changed

| File | Type | Changes |
|---|---|---|
| `macos/Runner/MainFlutterWindow.swift` | Native macOS | Configured transparent title bar, hidden title, `.fullSizeContentView`, and window movable by background. |
| `lib/features/reader/presentation/screens/reading_screen.dart` | Presentation | Integrated unified 44dp macOS title bar; integrated flush 32dp bottom bar; implemented edge-hover detection, 3.2s auto-hide, modal freeze, and smooth animated translations. |
| `lib/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart` | Presentation | Wrapped desktop left/right chevrons in `AnimatedOpacity` and `MouseRegion` with 0.0 resting opacity and hover activation. |
| `lib/features/reader/presentation/widgets/original_pdf_reader.dart` | Presentation | Refactored `_FloatingNavArrowState` with 0.0 resting opacity and hover activation in 56dp margin zones. |
| `test/reader_minimalist_ui_test.dart` | Test (New) | Comprehensive 7-test suite validating title bar geometry, bottom bar flush layout, auto-hide timer, edge hover, canvas tap, chevron hover-reveal, and multi-theme rendering. |

---

## 6. Verification & Test Evidence

### A. Dedicated Minimalist UI Suite
Ran `flutter test test/reader_minimalist_ui_test.dart`:
```
00:01 +1: 1. Unified Top Bar spans full width with macOS traffic light clearance
00:02 +2: 2. Slim Bottom Bar sits flush at window bottom with 32dp height
00:02 +3: 3. Auto-Hide Timer smoothly hides controls after 3.2s of inactivity
00:02 +4: 4. Edge hover smoothly reveals respective controls when hidden
00:02 +5: 5. Tapping reading canvas toggles controls visibility
00:02 +6: 6. Paginated Reflowable Reader chevrons are invisible until edge hover
00:02 +7: 7. Unified Top & Bottom Bar styling across Light, Sepia, and Dark themes
00:02 +7: All tests passed!
```

### B. Core Reader Regression Suites
- `test/reader_typography_refinement_test.dart`: **8/8 passed**.
- `test/phase_2_9_reader_ux_test.dart`: **5/5 passed**.
- `test/reading_screen_cross_platform_test.dart`: **4/4 passed**.
- `test/phase_3_5_navigation_and_lifecycle_stress_test.dart`: **120-cycle stress test passed** with 0 unhandled exceptions.

### C. Static Analysis & Build Verification
- `flutter analyze`: **0 issues found** (Clean).
- `git diff --check`: **Clean** (No trailing whitespace or formatting defects).
- `flutter build macos --debug`: **Built successfully**.

---

## 7. Acceptance Verdict

**Verdict:** **PASS**

All requirements for the Minimalist Apple Books-Inspired Reading Experience have been fully satisfied. The interface eliminates visual clutter, restores full reading canvas immersion, integrates seamlessly with macOS window chrome, and maintains 100% test compatibility across all platforms.
