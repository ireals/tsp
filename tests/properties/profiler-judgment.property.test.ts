import { describe, it, expect } from 'vitest';
import fc from 'fast-check';

// --- Model: Profiler Judgment ---

type Judgment = 'Positive' | 'Negative';

function judge(ratio: number, threshold: number): Judgment {
  return ratio > threshold ? 'Positive' : 'Negative';
}

// --- Property Tests ---

describe('CP-8: Profiler Judgment Correctness', () => {
  it('judgment is "Positive" iff ratio > threshold', () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0.5, max: 3.0, noNaN: true }),
        fc.double({ min: 1.01, max: 2.0, noNaN: true }),
        (ratio, threshold) => {
          const result = judge(ratio, threshold);

          if (ratio > threshold) {
            expect(result).toBe('Positive');
          } else {
            expect(result).toBe('Negative');
          }
        }
      ),
      { numRuns: 100 }
    );
  });
});
