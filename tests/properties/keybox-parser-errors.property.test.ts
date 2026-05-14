import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { invalidKeyboxXml, invalidPemKeyboxXml } from '../generators/index';

// --- Model: Keybox Parser Error Classification ---

type ErrorCode = 'INVALID_KEYBOX_SCHEMA' | 'INVALID_PEM_ENCODING';

interface ParseResult {
  success: boolean;
  errorCode?: ErrorCode;
}

function parseKeybox(xml: string): ParseResult {
  // Check for required structural elements
  const hasKeybox = /<Keybox[\s>]/.test(xml);
  const hasKey = /<Key[\s>]/.test(xml);
  const hasPrivateKey = /<PrivateKey[\s>]/.test(xml);
  const hasCertificateChain = /<CertificateChain[\s>]/.test(xml);

  if (!hasKeybox || !hasKey || !hasPrivateKey || !hasCertificateChain) {
    return { success: false, errorCode: 'INVALID_KEYBOX_SCHEMA' };
  }

  // Validate PEM encoding
  const pemBlocks = xml.match(
    /-----BEGIN [A-Z ]+-----\n([\s\S]*?)\n-----END [A-Z ]+-----/g
  );

  if (pemBlocks) {
    for (const block of pemBlocks) {
      const contentMatch = block.match(
        /-----BEGIN [A-Z ]+-----\n([\s\S]*?)\n-----END [A-Z ]+-----/
      );
      if (contentMatch) {
        const content = contentMatch[1].trim();
        // Check if content is valid base64
        if (!/^[A-Za-z0-9+/=\s]+$/.test(content)) {
          return { success: false, errorCode: 'INVALID_PEM_ENCODING' };
        }
      }
    }
  }

  return { success: true };
}

// --- Property Tests ---

describe('CP-11: Keybox Parser Error Classification', () => {
  it('XML missing required elements returns INVALID_KEYBOX_SCHEMA', () => {
    const missingElements = ['PrivateKey', 'CertificateChain', 'Keybox', 'Key'] as const;

    for (const element of missingElements) {
      fc.assert(
        fc.property(invalidKeyboxXml(element), (xml) => {
          const result = parseKeybox(xml);

          expect(result.success).toBe(false);
          expect(result.errorCode).toBe('INVALID_KEYBOX_SCHEMA');
        }),
        { numRuns: 100 }
      );
    }
  });

  it('XML with invalid PEM encoding returns INVALID_PEM_ENCODING', () => {
    fc.assert(
      fc.property(invalidPemKeyboxXml(), (xml) => {
        const result = parseKeybox(xml);

        expect(result.success).toBe(false);
        expect(result.errorCode).toBe('INVALID_PEM_ENCODING');
      }),
      { numRuns: 100 }
    );
  });
});
