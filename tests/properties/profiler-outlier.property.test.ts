import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { measurementArray } from '../generators/index';

// --- Model: Outlier Removal ---

function removeOutliers(measurements: number[]): number[] {
  const sorted = [...measurements].sort((a, b) => a - b);
  const n = sorted.length;
  const trimCount = Math.floor(n * 0.05);

  return sorted.slice(trimCount, n - trimCount);
}

// --- Property Tests ---

describe('CP-9: Outlier Removal Correctness', () => {
  it('result has correct size and all values are between 5th and 95th percentile', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 20, max: 200 }).chain((n) => measurementArray(n)),
        (measurements) => {
          const n = measurements.length;
          const trimCount = Math.floor(n * 0.05);
          const expectedSize = n - 2 * trimCount;

          const result = removeOutliers(measurements);

          // Result has correct size
          expect(result.length).toBe(expectedSize);

          // All values are within the 5th and 95th percentile of original
          const sorted = [...measurements].sort((a, b) => a - b);
          const lowerBound = sorted[trimCount];
          const upperBound = sorted[n - trimCount - 1];

          for (const value of result) {
            expect(value).toBeGreaterThanOrEqual(lowerBound);
            expect(value).toBeLessThanOrEqual(upperBound);
          }
        }
      ),
      { numRuns: 100 }
    );
  });
});
