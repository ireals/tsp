import { describe, it, expect } from 'vitest';
import fc from 'fast-check';

// --- Model: Jitter Injection ---

/**
 * Generates a bounded random jitter value.
 * The jitter is clamped to [-stddev, +stddev].
 */
function generateJitter(stddev: number): number {
  // Simulate bounded jitter: random value in [-stddev, stddev]
  const raw = (Math.random() * 2 - 1) * stddev;
  // Clamp to ensure bounds guarantee
  return Math.max(-stddev, Math.min(stddev, raw));
}

// --- Property Tests ---

describe('CP-10: Jitter Injection Bounds', () => {
  it('for any stddev > 0, |generateJitter(stddev)| <= stddev', () => {
    fc.assert(
      fc.property(
        fc.double({ min: 0.001, max: 10.0, noNaN: true }),
        (stddev) => {
          const jitter = generateJitter(stddev);

          expect(Math.abs(jitter)).toBeLessThanOrEqual(stddev);
        }
      ),
      { numRuns: 100 }
    );
  });
});
