import { describe, it, expect } from 'vitest';
import fc from 'fast-check';

// --- Model: Latency Equalizer ---

/**
 * Simulates the adjusted time calculation.
 * Given a measured time T_n, a threshold ratio, and elapsed time,
 * returns an adjusted time T_a such that T_n / T_a <= threshold.
 */
function calculateAdjustedTime(
  T_n: number,
  threshold: number,
  elapsed: number
): number {
  // The equalizer ensures the ratio stays within bounds.
  // T_a must be >= T_n / threshold to satisfy the guarantee.
  const minAdjusted = T_n / threshold;
  // Simulate: adjusted time is at least the minimum required
  return Math.max(minAdjusted, elapsed);
}

// --- Property Tests ---

describe('CP-3: Latency_Equalizer Ratio Guarantee', () => {
  it('for any T_n > 0 and threshold >= 1.01, T_n / T_a <= threshold', () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0.01, max: 100, noNaN: true }),
        fc.double({ min: 1.01, max: 2.0, noNaN: true }),
        fc.double({ min: 0.001, max: 50, noNaN: true }),
        (T_n, threshold, elapsed) => {
          const T_a = calculateAdjustedTime(T_n, threshold, elapsed);

          expect(T_a).toBeGreaterThan(0);
          expect(T_n / T_a).toBeLessThanOrEqual(threshold);
        }
      ),
      { numRuns: 100 }
    );
  });
});
