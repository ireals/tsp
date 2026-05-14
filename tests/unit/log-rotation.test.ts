import { describe, it, expect } from 'vitest';

// Constants matching logger.sh
const LOG_MAX_SIZE = 5 * 1024 * 1024; // 5MB (5242880 bytes)

// Log level numeric values matching logger.sh _log_level_to_num()
const LOG_LEVELS: Record<string, number> = {
  ERROR: 0,
  WARN: 1,
  INFO: 2,
  DEBUG: 3,
};

interface LogEntry {
  timestamp: string;
  level: string;
  component: string;
  message: string;
  raw: string;
  size: number;
}

/**
 * Determine if log rotation is needed.
 * Models the check in logger.sh _log_rotate():
 *   if [ "${_size:-0}" -gt "$LOG_MAX_SIZE" ]
 */
function shouldRotate(currentSize: number, maxSize: number): boolean {
  return currentSize > maxSize;
}

/**
 * Simulate log rotation.
 * Models logger.sh _log_rotate():
 *   mv -f "$LOG_FILE" "${LOG_FILE}.1"
 *   : > "$LOG_FILE"
 * Returns { archived, current } where archived contains old entries
 * and current is the new empty log.
 */
function rotateLog(
  logEntries: LogEntry[],
  maxSize: number
): { archived: LogEntry[]; current: LogEntry[] } {
  const totalSize = logEntries.reduce((sum, entry) => sum + entry.size, 0);

  if (totalSize > maxSize) {
    return {
      archived: [...logEntries],
      current: [],
    };
  }

  return {
    archived: [],
    current: [...logEntries],
  };
}

/**
 * Format a log entry matching logger.sh _log_write() format:
 *   "$_timestamp [$_level] $LOG_COMPONENT: $_message"
 * Timestamp format: YYYY-MM-DD HH:MM:SS
 */
function formatLogEntry(
  level: string,
  component: string,
  message: string
): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');

  const timestamp = `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  return `${timestamp} [${level}] ${component}: ${message}`;
}

/**
 * Filter log entries by minimum log level.
 * Models logger.sh _log_should_output():
 *   Lower numeric value = higher severity.
 *   Only entries with level <= minLevel numeric value pass.
 */
function filterByLevel(entries: LogEntry[], minLevel: string): LogEntry[] {
  const minLevelNum = LOG_LEVELS[minLevel] ?? 2;
  return entries.filter((entry) => {
    const entryLevelNum = LOG_LEVELS[entry.level] ?? 2;
    return entryLevelNum <= minLevelNum;
  });
}

// Helper to create a LogEntry for testing
function createLogEntry(
  level: string,
  component: string,
  message: string
): LogEntry {
  const raw = formatLogEntry(level, component, message);
  return {
    timestamp: raw.substring(0, 19),
    level,
    component,
    message,
    raw,
    size: Buffer.byteLength(raw + '\n', 'utf8'),
  };
}

describe('Log Rotation', () => {
  it('should detect when rotation is needed (size > 5MB)', () => {
    const overSize = LOG_MAX_SIZE + 1;
    expect(shouldRotate(overSize, LOG_MAX_SIZE)).toBe(true);

    // Well over threshold
    const wayOver = LOG_MAX_SIZE * 2;
    expect(shouldRotate(wayOver, LOG_MAX_SIZE)).toBe(true);
  });

  it('should not rotate when under threshold', () => {
    const underSize = LOG_MAX_SIZE - 1;
    expect(shouldRotate(underSize, LOG_MAX_SIZE)).toBe(false);

    // Much smaller
    expect(shouldRotate(1024, LOG_MAX_SIZE)).toBe(false);

    // Empty log
    expect(shouldRotate(0, LOG_MAX_SIZE)).toBe(false);
  });

  it('should format log entries with correct timestamp format', () => {
    const formatted = formatLogEntry('INFO', 'config_manager', 'Config loaded');

    // Verify format: "YYYY-MM-DD HH:MM:SS [LEVEL] component: message"
    const pattern =
      /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\] config_manager: Config loaded$/;
    expect(formatted).toMatch(pattern);

    // Verify different levels
    const errorFormatted = formatLogEntry('ERROR', 'hook', 'Failed to attach');
    expect(errorFormatted).toMatch(
      /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[ERROR\] hook: Failed to attach$/
    );
  });

  it('should filter entries by log level', () => {
    const entries: LogEntry[] = [
      createLogEntry('ERROR', 'main', 'Critical failure'),
      createLogEntry('WARN', 'main', 'Something concerning'),
      createLogEntry('INFO', 'main', 'Normal operation'),
      createLogEntry('DEBUG', 'main', 'Verbose detail'),
    ];

    // Filter at ERROR level: only ERROR passes
    const errorOnly = filterByLevel(entries, 'ERROR');
    expect(errorOnly).toHaveLength(1);
    expect(errorOnly[0].level).toBe('ERROR');

    // Filter at WARN level: ERROR and WARN pass
    const warnAndAbove = filterByLevel(entries, 'WARN');
    expect(warnAndAbove).toHaveLength(2);
    expect(warnAndAbove.map((e) => e.level)).toEqual(['ERROR', 'WARN']);

    // Filter at INFO level: ERROR, WARN, INFO pass
    const infoAndAbove = filterByLevel(entries, 'INFO');
    expect(infoAndAbove).toHaveLength(3);

    // Filter at DEBUG level: all pass
    const all = filterByLevel(entries, 'DEBUG');
    expect(all).toHaveLength(4);
  });

  it('should preserve log entries during rotation (archived)', () => {
    const entries: LogEntry[] = [
      createLogEntry('INFO', 'service', 'Started'),
      createLogEntry('WARN', 'service', 'High latency detected'),
      createLogEntry('ERROR', 'service', 'Connection lost'),
    ];

    // Simulate entries exceeding max size by using a tiny max
    const tinyMax = 10; // 10 bytes — all entries exceed this
    const result = rotateLog(entries, tinyMax);

    // All entries should be archived
    expect(result.archived).toHaveLength(3);
    expect(result.archived[0].message).toBe('Started');
    expect(result.archived[1].message).toBe('High latency detected');
    expect(result.archived[2].message).toBe('Connection lost');
  });

  it('should create empty log after rotation', () => {
    const entries: LogEntry[] = [
      createLogEntry('INFO', 'main', 'Entry 1'),
      createLogEntry('INFO', 'main', 'Entry 2'),
    ];

    // Use tiny max to force rotation
    const tinyMax = 10;
    const result = rotateLog(entries, tinyMax);

    // Current log should be empty after rotation
    expect(result.current).toHaveLength(0);
    expect(result.current).toEqual([]);
  });

  it('should handle edge case of exactly max size', () => {
    // At exactly max size, should NOT rotate (logger.sh uses -gt, not -ge)
    expect(shouldRotate(LOG_MAX_SIZE, LOG_MAX_SIZE)).toBe(false);

    // One byte over should trigger rotation
    expect(shouldRotate(LOG_MAX_SIZE + 1, LOG_MAX_SIZE)).toBe(true);

    // Verify rotateLog with entries exactly at max
    const entry = createLogEntry('INFO', 'test', 'x');
    const exactMax = entry.size; // Set max to exactly one entry's size
    const result = rotateLog([entry], exactMax);

    // Not over max, so no rotation
    expect(result.archived).toHaveLength(0);
    expect(result.current).toHaveLength(1);
  });
});
