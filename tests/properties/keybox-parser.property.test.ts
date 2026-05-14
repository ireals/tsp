import { describe, it, expect } from 'vitest';
import fc from 'fast-check';
import { validKeyboxXml } from '../generators/index';

// --- Model: Keybox Parser ---

interface KeyboxData {
  algorithm: string;
  privateKey: string;
  certificates: string[];
}

function parse(xml: string): KeyboxData | null {
  const algorithmMatch = xml.match(/<Key\s+algorithm="([^"]+)">/);
  if (!algorithmMatch) return null;

  const privateKeyMatch = xml.match(
    /-----BEGIN EC PRIVATE KEY-----\n([\s\S]*?)\n-----END EC PRIVATE KEY-----/
  );
  if (!privateKeyMatch) return null;

  const certRegex = /-----BEGIN CERTIFICATE-----\n([\s\S]*?)\n-----END CERTIFICATE-----/g;
  const certificates: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = certRegex.exec(xml)) !== null) {
    certificates.push(match[1].trim());
  }

  return {
    algorithm: algorithmMatch[1],
    privateKey: privateKeyMatch[1].trim(),
    certificates,
  };
}

function print(data: KeyboxData): string {
  const certs = data.certificates
    .map(
      (cert) => `        <Certificate format="pem">
-----BEGIN CERTIFICATE-----
${cert}
-----END CERTIFICATE-----
        </Certificate>`
    )
    .join('\n');

  return `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="device_001">
    <Key algorithm="${data.algorithm}">
      <PrivateKey format="pem">
-----BEGIN EC PRIVATE KEY-----
${data.privateKey}
-----END EC PRIVATE KEY-----
      </PrivateKey>
      <CertificateChain>
        <NumberOfCertificates>${data.certificates.length}</NumberOfCertificates>
${certs}
      </CertificateChain>
    </Key>
  </Keybox>
</AndroidAttestation>`;
}

// --- Property Tests ---

describe('CP-1: Keybox Parser Round-Trip', () => {
  it('parse(print(parse(xml))) deep-equals parse(xml) for any valid keybox XML', () => {
    fc.assert(
      fc.property(validKeyboxXml(), (xml) => {
        const firstParse = parse(xml);
        expect(firstParse).not.toBeNull();

        const printed = print(firstParse!);
        const secondParse = parse(printed);

        expect(secondParse).toEqual(firstParse);
      }),
      { numRuns: 100 }
    );
  });
});
