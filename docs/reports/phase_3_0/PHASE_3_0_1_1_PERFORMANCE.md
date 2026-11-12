# PHASE 3.0.1.1: PERFORMANCE, LATENCY & RESOURCE REGRESSION AUDIT

Date: 2026-11-01  
Environment: macOS (Darwin 24.3.0, Apple Silicon)  
Benchmark Suite: [`test/phase_3_0_1_1_performance_regression_test.dart`](file:///Users/davindalana/Documents/Project/Digital%20Books/test/phase_3_0_1_1_performance_regression_test.dart)  
Stress Target: *Bicara Itu Ada Seninya* (64 MB Scanned Book, 255 pages)  

---

## 1. Executive Summary

Phase 3.0.1.1 added adaptive gutter gradient pre-sampling, quadratic highlight compression, and edge-preserving clamping. This audit measures the computational overhead to ensure no performance regressions were introduced to the reading engine.

All metrics comfortably passed their respective budgets. The adaptive gutter detection adds less than **0.4 ms** per page, and overall full-page render and enhancement executes at **23.4 ms/page** (well under the 60 ms/page target).

---

## 2. Benchmark Results & Metric Comparison

### 2.1 Latency Measurements
| Performance Benchmark | Measured Value | Standard Target | Status |
| :--- | :--- | :--- | :--- |
| **Cold Document Open (64 MB PDF)** | **59 ms – 72 ms** | $\le 100\text{ ms}$ | **PASS** |
| **Gentle Mode S-Curve Enhance (7.5 MB raw buffer)** | **30 ms – 34 ms** | $\le 50\text{ ms}$ | **PASS** |
| **Balanced Mode S-Curve Enhance (7.5 MB raw buffer)** | **23 ms – 28 ms** | $\le 50\text{ ms}$ | **PASS** |
| **Strong Mode S-Curve Enhance (7.5 MB raw buffer)** | **12 ms – 13 ms** | $\le 50\text{ ms}$ | **PASS** |
| **Adaptive Gutter Sampling Overhead (40 rows)** | **0.38 ms** | $\le 1.0\text{ ms}$ | **PASS** |
| **Full Pipeline (PDFium Render + Adaptive Gutter + Enhance)** | **23.4 ms – 26.5 ms/page** | $\le 60\text{ ms/page}$ | **PASS** |

### 2.2 Memory Footprint (Process RSS Delta)
| Scenario | Baseline RSS | Peak RSS | Delta | Memory Budget | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **64 MB PDF Open + 8 Enhanced Spreads** | 242.1 MB | 350.2 MB | **+108.1 MB** | $\le 150.0\text{ MB}$ | **PASS** |

### 2.3 CPU & Frame Scheduling
- **Quiescent Reading CPU**: **0.0%** (zero active tickers or dirty repaints when stationary).
- **Active 3D Page Curl Transition**: Smooth **60 FPS** on standard displays, delivering frames consistently within the 16.6 ms frame budget.

---

## 3. Regression Comparison vs Phase 3.0.1

| Metric | Phase 3.0.1 Baseline | Phase 3.0.1.1 (Current) | Variance | Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Cold Open Latency** | 26 ms (warm disk) | 59 ms (cold disk) | +33 ms | Well within 100 ms budget |
| **Full Page Pipeline Latency** | 22.8 ms/page | 23.4 ms/page | **+0.6 ms** | Negligible (~2.6% delta) |
| **Strong Mode Latency** | 18 ms | 12 ms | **-6 ms** | Faster due to optimized stencil |
| **RSS Memory Delta** | +59.4 MB (5 pages) | +108.1 MB (8 pages) | Scaled linearly | Bounded by 24-page LRU |

---

## 4. Verdict

**STATUS: PASS**.  
The enhancements introduce no performance regressions. Latencies and memory remain strictly within budget on heavy 64 MB scanned PDF files.
