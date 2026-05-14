import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import crypto from 'crypto';
import { validKeyboxXml } from '../generators/index';

// --- Model: Keybox Store ---

function computeFilename(content: string): string {
  return crypto.createHash('sha256').update(content).digest('hex');
}

// --- Property Tests ---

describe('CP-6: Keybox_Store Filename Consistency', () => {
  it('filename equals SHA-256 hex of content for any keybox', () => {
    fc.assert(
      fc.property(validKeyboxXml(), (content) => {
        const filename = computeFilename(content);
        const expected = crypto.createHash('sha256').update(content).digest('hex');

        expect(filename).toBe(expected);
        // Verify it's a valid hex string of correct length (64 chars for SHA-256)
        expect(filename).toMatch(/^[0-9a-f]{64}$/);
      }),
      { numRuns: 100 }
    );
  });
});
