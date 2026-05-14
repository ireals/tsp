import { describe, it, expect } from 'vitest';
import fc from 'fast-check';

// --- Model: Shell Bridge ---

const WHITELIST = ['getConfig', 'setConfig', 'getStatus', 'listKeyboxes', 'getTargets'] as const;

interface SuccessResponse {
  status: 0;
  data: unknown;
}

interface ErrorResponse {
  status: number;
  message: string;
}

type ShellResponse = SuccessResponse | ErrorResponse;

function createResponse(command: string): ShellResponse {
  if (WHITELIST.includes(command as typeof WHITELIST[number])) {
    return { status: 0, data: {} };
  }
  return { status: 1, message: `Unknown command: ${command}` };
}

// --- Property Tests ---

describe('CP-5: Shell_Bridge Response Structure', () => {
  it('response has numeric status; status===0 implies data; status!==0 implies message', () => {
    const commandGen = fc.oneof(
      fc.string({ minLength: 0, maxLength: 50 }),
      fc.constantFrom(...WHITELIST)
    );

    fc.assert(
      fc.property(commandGen, (command) => {
        const response = createResponse(command);

        // Status is always numeric
        expect(typeof response.status).toBe('number');

        if (response.status === 0) {
          // Success implies 'data' is present
          expect('data' in response).toBe(true);
        } else {
          // Non-zero status implies 'message' is present
          expect('message' in response).toBe(true);
        }
      }),
      { numRuns: 100 }
    );
  });
});
