import fc from 'fast-check';

/**
 * Generates a random base64-like string to simulate PEM content.
 */
function pemContent(): fc.Arbitrary<string> {
  return fc
    .array(
      fc.integer({ min: 0, max: 255 }),
      { minLength: 64, maxLength: 256 }
    )
    .map((bytes) => {
      const base64 = Buffer.from(bytes).toString('base64');
      // Split into 64-char lines
      return base64.replace(/(.{64})/g, '$1\n').trim();
    });
}

/**
 * Generates structurally valid keybox XML strings with random PEM-like content.
 */
export function validKeyboxXml(): fc.Arbitrary<string> {
  return fc
    .tuple(pemContent(), pemContent(), pemContent())
    .map(([privateKey, cert1, cert2]) => {
      return `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="device_001">
    <Key algorithm="ecdsa">
      <PrivateKey format="pem">
-----BEGIN EC PRIVATE KEY-----
${privateKey}
-----END EC PRIVATE KEY-----
      </PrivateKey>
      <CertificateChain>
        <NumberOfCertificates>2</NumberOfCertificates>
        <Certificate format="pem">
-----BEGIN CERTIFICATE-----
${cert1}
-----END CERTIFICATE-----
        </Certificate>
        <Certificate format="pem">
-----BEGIN CERTIFICATE-----
${cert2}
-----END CERTIFICATE-----
        </Certificate>
      </CertificateChain>
    </Key>
  </Keybox>
</AndroidAttestation>`;
    });
}

/**
 * Generates XML missing a specified element to test validation.
 */
export function invalidKeyboxXml(
  missingElement: 'PrivateKey' | 'CertificateChain' | 'Keybox' | 'Key'
): fc.Arbitrary<string> {
  return pemContent().map((content) => {
    const fullXml: Record<string, string> = {
      PrivateKey: `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="device_001">
    <Key algorithm="ecdsa">
      <CertificateChain>
        <NumberOfCertificates>1</NumberOfCertificates>
        <Certificate format="pem">
-----BEGIN CERTIFICATE-----
${content}
-----END CERTIFICATE-----
        </Certificate>
      </CertificateChain>
    </Key>
  </Keybox>
</AndroidAttestation>`,
      CertificateChain: `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="device_001">
    <Key algorithm="ecdsa">
      <PrivateKey format="pem">
-----BEGIN EC PRIVATE KEY-----
${content}
-----END EC PRIVATE KEY-----
      </PrivateKey>
    </Key>
  </Keybox>
</AndroidAttestation>`,
      Keybox: `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>0</NumberOfKeyboxes>
</AndroidAttestation>`,
      Key: `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="device_001">
  </Keybox>
</AndroidAttestation>`,
    };

    return fullXml[missingElement];
  });
}

/**
 * Generates XML with invalid PEM encoding (corrupted base64).
 */
export function invalidPemKeyboxXml(): fc.Arbitrary<string> {
  return fc
    .string({ minLength: 20, maxLength: 100 })
    .filter((s) => !(/^[A-Za-z0-9+/=\n]+$/.test(s)))
    .map((invalidContent) => {
      return `<?xml version="1.0"?>
<AndroidAttestation>
  <NumberOfKeyboxes>1</NumberOfKeyboxes>
  <Keybox DeviceID="device_001">
    <Key algorithm="ecdsa">
      <PrivateKey format="pem">
-----BEGIN EC PRIVATE KEY-----
${invalidContent}
-----END EC PRIVATE KEY-----
      </PrivateKey>
      <CertificateChain>
        <NumberOfCertificates>1</NumberOfCertificates>
        <Certificate format="pem">
-----BEGIN CERTIFICATE-----
${invalidContent}
-----END CERTIFICATE-----
        </Certificate>
      </CertificateChain>
    </Key>
  </Keybox>
</AndroidAttestation>`;
    });
}

/**
 * Generates valid Android package names (e.g., "com.example.app123").
 */
export function packageName(): fc.Arbitrary<string> {
  const segment = fc
    .tuple(
      fc.char().filter((c) => /[a-z]/.test(c)),
      fc.stringOf(
        fc.char().filter((c) => /[a-z0-9]/.test(c)),
        { minLength: 1, maxLength: 10 }
      )
    )
    .map(([first, rest]) => first + rest);

  return fc
    .tuple(segment, segment, segment)
    .map(([a, b, c]) => `${a}.${b}.${c}`);
}

/**
 * Generates valid config objects with all fields populated.
 */
export function configObject(): fc.Arbitrary<{
  equalizerEnabled: boolean;
  detectionThreshold: number;
  referenceProfile: { mean: number; stddev: number };
  hasProfile: boolean;
  activeKeyboxId: string;
  targetList: string[];
}> {
  return fc.record({
    equalizerEnabled: fc.boolean(),
    detectionThreshold: fc.double({ min: 0.5, max: 2.0, noNaN: true }),
    referenceProfile: fc.record({
      mean: fc.double({ min: 0.1, max: 10.0, noNaN: true }),
      stddev: fc.double({ min: 0.01, max: 1.0, noNaN: true }),
    }),
    hasProfile: fc.boolean(),
    activeKeyboxId: fc
      .hexaString({ minLength: 8, maxLength: 16 })
      .map((s) => `keybox_${s}`),
    targetList: fc.array(packageName(), { minLength: 1, maxLength: 10 }),
  });
}

/**
 * Generates arrays of n positive float measurements (simulating timing data).
 */
export function measurementArray(n: number): fc.Arbitrary<number[]> {
  return fc.array(
    fc.double({ min: 0.001, max: 100.0, noNaN: true }),
    { minLength: n, maxLength: n }
  );
}

/**
 * Generates arrays of n unique package names.
 */
export function targetList(n: number): fc.Arbitrary<string[]> {
  return fc
    .uniqueArray(packageName(), { minLength: n, maxLength: n })
    .filter((arr) => arr.length === n);
}
