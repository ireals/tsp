import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { packageName, targetList } from '../generators/index';

// --- Model: TargetList as Set<string> ---

function add(list: Set<string>, pkg: string): Set<string> {
  const result = new Set(list);
  result.add(pkg);
  return result;
}

// --- Property Tests ---

describe('CP-2: Target_List Set Invariant', () => {
  it('after add: size is original or original+1, and package is in result', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 1, max: 10 }).chain((n) => targetList(n)),
        packageName(),
        (list, pkg) => {
          const originalSet = new Set(list);
          const originalSize = originalSet.size;

          const result = add(originalSet, pkg);

          // Size is either the same (if pkg was already present) or +1
          expect(result.size).toBeGreaterThanOrEqual(originalSize);
          expect(result.size).toBeLessThanOrEqual(originalSize + 1);

          // Package is in the result
          expect(result.has(pkg)).toBe(true);
        }
      ),
      { numRuns: 100 }
    );
  });
});
