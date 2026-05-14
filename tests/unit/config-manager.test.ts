import { describe, it, expect } from 'vitest';

// Default config schema matching module/config/config.json
const DEFAULT_CONFIG = {
  schemaVersion: 1,
  activeKeyboxId: '',
  targetList: [] as string[],
  detectionThreshold: 1.1,
  sampleCount: 500,
  latencyEqualizerEnabled: true,
  logLevel: 'INFO',
  referenceProfile: null as string | null,
  keyboxMetadata: [] as Record<string, unknown>[],
};

type Config = typeof DEFAULT_CONFIG;

/**
 * Migrate config from one schema version to another.
 * Models the shell script logic in config_manager.sh:
 * - fromVersion === 0 means no schema version found (legacy/empty config)
 * - Adds all missing fields from defaults
 * - Preserves existing valid values
 * - Sets schemaVersion to toVersion after migration
 */
function migrateConfig(
  oldConfig: Partial<Config>,
  fromVersion: number,
  toVersion: number
): Config {
  if (fromVersion === 0) {
    // No schema version: merge defaults with any existing values
    const migrated = { ...DEFAULT_CONFIG, ...oldConfig };
    migrated.schemaVersion = toVersion;
    return migrated;
  }

  // Incremental migration: fill in missing fields from defaults
  const migrated = { ...DEFAULT_CONFIG };
  for (const key of Object.keys(oldConfig) as (keyof Config)[]) {
    if (oldConfig[key] !== undefined) {
      (migrated as Record<string, unknown>)[key] = oldConfig[key];
    }
  }
  migrated.schemaVersion = toVersion;
  return migrated;
}

/**
 * Create a backup copy of the config (deep clone).
 * Models the `cp -f` backup in config_manager.sh config_migrate().
 */
function createBackup(config: Config): Config {
  return JSON.parse(JSON.stringify(config));
}

describe('Config Manager - Schema Migration', () => {
  it('should add missing fields when migrating from v0 to v1', () => {
    const oldConfig: Partial<Config> = {
      activeKeyboxId: 'key-123',
      logLevel: 'DEBUG',
    };

    const migrated = migrateConfig(oldConfig, 0, 1);

    // Missing fields should be filled from defaults
    expect(migrated.detectionThreshold).toBe(1.1);
    expect(migrated.sampleCount).toBe(500);
    expect(migrated.latencyEqualizerEnabled).toBe(true);
    expect(migrated.targetList).toEqual([]);
    expect(migrated.referenceProfile).toBeNull();
    expect(migrated.keyboxMetadata).toEqual([]);
  });

  it('should preserve existing values during migration', () => {
    const oldConfig: Partial<Config> = {
      activeKeyboxId: 'my-keybox',
      detectionThreshold: 1.5,
      sampleCount: 1000,
      logLevel: 'WARN',
      latencyEqualizerEnabled: false,
    };

    const migrated = migrateConfig(oldConfig, 0, 1);

    expect(migrated.activeKeyboxId).toBe('my-keybox');
    expect(migrated.detectionThreshold).toBe(1.5);
    expect(migrated.sampleCount).toBe(1000);
    expect(migrated.logLevel).toBe('WARN');
    expect(migrated.latencyEqualizerEnabled).toBe(false);
  });

  it('should create backup before migration', () => {
    const originalConfig: Config = {
      ...DEFAULT_CONFIG,
      activeKeyboxId: 'backup-test',
      sampleCount: 2000,
    };

    const backup = createBackup(originalConfig);

    // Backup should be a separate copy
    expect(backup).toEqual(originalConfig);
    expect(backup).not.toBe(originalConfig);

    // Modifying original should not affect backup
    originalConfig.activeKeyboxId = 'modified';
    expect(backup.activeKeyboxId).toBe('backup-test');
  });

  it('should return defaults for completely empty config', () => {
    const emptyConfig: Partial<Config> = {};

    const migrated = migrateConfig(emptyConfig, 0, 1);

    expect(migrated).toEqual({
      ...DEFAULT_CONFIG,
      schemaVersion: 1,
    });
  });

  it('should handle null referenceProfile correctly', () => {
    const oldConfig: Partial<Config> = {
      referenceProfile: null,
      activeKeyboxId: 'test',
    };

    const migrated = migrateConfig(oldConfig, 0, 1);

    expect(migrated.referenceProfile).toBeNull();
  });

  it('should set schemaVersion to target version after migration', () => {
    const oldConfig: Partial<Config> = {
      schemaVersion: 0,
      activeKeyboxId: 'old',
    };

    const migrated = migrateConfig(oldConfig, 0, 1);
    expect(migrated.schemaVersion).toBe(1);

    // Also test incremental migration path
    const migratedIncremental = migrateConfig(
      { ...DEFAULT_CONFIG, schemaVersion: 1 },
      1,
      2
    );
    expect(migratedIncremental.schemaVersion).toBe(2);
  });
});
