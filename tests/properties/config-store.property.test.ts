import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { configObject } from '../generators/index';

// --- Model: Configuration Store ---

function writeConfig(config: object): string {
  return JSON.stringify(config, null, 2);
}

// --- Property Tests ---

describe('CP-4: Configuration_Store Idempotence', () => {
  it('writeConfig(config) === writeConfig(JSON.parse(writeConfig(config))) for any valid config', () => {
    fc.assert(
      fc.property(configObject(), (config) => {
        const firstWrite = writeConfig(config);
        const parsed = JSON.parse(firstWrite);
        const secondWrite = writeConfig(parsed);

        expect(secondWrite).toBe(firstWrite);
      }),
      { numRuns: 100 }
    );
  });
});
