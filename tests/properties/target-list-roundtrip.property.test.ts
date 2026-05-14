import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { targetList } from '../generators/index';

// --- Model: Target List Import/Export ---

function exportToText(list: string[]): string {
  const header = '# Target list - auto-generated\n';
  return header + list.join('\n') + '\n';
}

function importFromText(text: string): string[] {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'));
}

// --- Property Tests ---

describe('CP-7: Target_List Import/Export Round-Trip', () => {
  it('importFromText(exportToText(list)) equals original list as set', () => {
    fc.assert(
      fc.property(
        fc.integer({ min: 1, max: 15 }).chain((n) => targetList(n)),
        (list) => {
          const exported = exportToText(list);
          const imported = importFromText(exported);

          const originalSet = new Set(list);
          const importedSet = new Set(imported);

          expect(importedSet).toEqual(originalSet);
        }
      ),
      { numRuns: 100 }
    );
  });
});
