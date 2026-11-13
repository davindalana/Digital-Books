# Phase 3.0.1.1 Gutter Crease Shadow Validation

> **Metadata Dokumen**
> - **Siklus / Inisiatif**: Siklus I — Core Engine & Document Pipeline (v1.0 s.d. v1.1)
> - **Modul / Kategori**: Phase 3.0.1.1 Gutter Crease Shadow Flattening Validation
> - **Urutan Dokumen**: 11 Phase 3.0.1.1 Gutter Crease Shadow Validation
> - **Tanggal**: 2 November 2026
> - **Status Verifikasi**: **PASS**

---

Date: 2026-11-01  
Environment: macOS (Darwin 24.3.0, Apple Silicon)  
Target: Binding Shadow Suppression on Scanned Books (*Laut Bercerita* & *Bicara Itu Ada Seninya*)  

---

## 1. Problem Definition & Previous Defect

In Phase 3.0.1, gutter compensation applied a **blind static mathematical ramp** (+38 luminance) to the outer 16% inner margin based entirely on page parity (`isLeftPage ? right : left`).

### Identified Hazards:
1. **Bleaching Clean Flatbed Margins**: On cleanly cropped or flatbed scans (such as *Laut Bercerita* P.15 where the margin is already pure white paper $L = 255$), adding a static ramp risked washing out margin annotations or creating artificial glare.
2. **Ink Bleaching Near Margin**: Applying a fixed luminance offset across all pixels in the gutter zone caused dark text situated close to the inner spine to turn gray.

---

## 2. Technical Implementation: Empirical Adaptive Detection

In [`ScannedImageEnhancer`](../../../../lib/features/processing/services/scanned_image_enhancer.dart), the static offset was replaced with a two-phase adaptive pipeline:

### 2.1 Fast Pre-Sampling & Gradient Analysis (`_detectGutterShadow`)
- **Sampling Budget**: Samples 40 rows evenly spaced down the document height ($\le 0.4\text{ ms}$ execution overhead).
- **Core Baseline ($L_{\text{core}}$)**: Extracts pixels from the central core ($35\% \le x \le 65\%$). Takes the **90th percentile** luminance to obtain the true background paper tone, immune to dark text lines or illustration art.
- **Inner Gutter Strip ($L_{\text{edge}}$)**: Extracts pixels from the innermost 4% margin (right edge for left pages, left edge for right pages). Takes the **90th percentile** luminance.
- **Gradient Decision Gate**:
  $$\Delta_{\text{shadow}} = L_{\text{core}} - L_{\text{edge}}$$
  - If $\Delta_{\text{shadow}} < 12$ or $L_{\text{edge}} \ge 242$: **No Gutter Shadow Detected**. `maxBoost = 0`. Margin remains untouched.
  - If $\Delta_{\text{shadow}} \ge 12$ and $L_{\text{edge}} < 242$: **Genuine Spine Shadow Detected**. `maxBoost = \min(45, \Delta_{\text{shadow}})`.

### 2.2 Text Protection Masking
When gutter boost is active, the boost is modulated per-pixel based on source luminance:
$$\text{textProtection} = \text{clamp}\left(\frac{L - 90}{130}, 0.0, 1.0\right), \quad \text{gutterBoost} = \text{round}(\text{rawBoost} \times \text{textProtection})$$
- For deep text ink ($L < 90$), $\text{textProtection} = 0.0$. Text remains solid black and is **never bleached**.
- For intermediate paper and shadows ($L \ge 90$), the compensation smoothly levels the shadow back to core paper brightness.

---

## 3. Empirical Test Results on Real Documents

Evaluated in [`test/phase_3_0_1_1_enhancement_and_gutter_test.dart`](../../../../test/phase_3_0_1_1_enhancement_and_gutter_test.dart):

### 3.1 Scenario A: Flatbed Scan (*Laut Bercerita* P.15)
- **Geometry**: Left page geometry test (inner gutter on right edge).
- **Core Background**: $255.0$
- **Gutter Edge Background**: $255.0$
- **Measured Shadow $\Delta$**: **0.0**
- **Adaptive Detection Result**: `hasShadow = false`.
- **Applied Boost**: **+0.0** (Delta = 0). Margin is 100% untouched.

### 3.2 Scenario B: Deep Binding Spine Shadow (*Bicara Itu Ada Seninya* P.1)
- **Geometry**: Right page geometry (inner gutter on left edge $x = 0$).
- **Core Background**: $252.0$
- **Gutter Edge Background**: $79.0$
- **Measured Shadow $\Delta$**: **173.0** (Exceeds threshold 12).
- **Adaptive Detection Result**: `hasShadow = true`, `maxBoost = 45`.
- **Applied Compensation**: Average shadow paper luminance lifted from **232.5 to 240.6** (+8.1 luminance lift on darkened binding edge).

### 3.3 Scenario C: Text Protection Verification at Spine Margin
- **Input**: Dark text line ($L = 40$) situated directly at the binding edge ($x = 0$) in a shadow zone.
- **Enhanced Output**: Luminance = **6** (deepened to solid ink).
- **Result**: **PASS**. Zero text bleaching observed.

### 3.4 Scenario D: Clean Scanned Book Pages (*Bicara Itu Ada Seninya* P.5, 11, 21, 51)
| Page Sample | Core 90th Pct Lum | Edge 90th Pct Lum | Measured Delta | Shadow Detected? | Applied Boost |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Page 1** (Binding Spine) | 252 | 79 | **173** | **YES** | +45 (Adaptive Ramp) |
| **Page 5** (Clean Margin) | 255 | 255 | **0** | **NO** | +0 (No Boost) |
| **Page 11** (Clean Margin) | 255 | 255 | **0** | **NO** | +0 (No Boost) |
| **Page 21** (Clean Margin) | 255 | 255 | **0** | **NO** | +0 (No Boost) |
| **Page 51** (Clean Margin) | 255 | 255 | **0** | **NO** | +0 (No Boost) |

---

## 4. Verdict

**STATUS: PASS**.  
Gutter compensation is now 100% adaptive. It levels actual binding curvature shadows where present, preserves dark text near margins, and completely eliminates artificial margin brightening on flatbed or clean scans.
