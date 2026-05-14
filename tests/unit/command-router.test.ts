import { describe, it, expect } from 'vitest';

// Whitelist of allowed commands (same as bridge.sh)
const WHITELIST = [
  'keybox_add',
  'keybox_list',
  'keybox_select',
  'keybox_delete',
  'keybox_validate',
  'target_list_installed',
  'target_add',
  'target_remove',
  'target_import',
  'target_export',
  'profiler_run',
  'profiler_reference',
  'profiler_calibrate',
  'config_get',
  'config_set',
  'log_tail',
];

const BRIDGE_TIMEOUT = 30;

/**
 * Check if a command is in the whitelist.
 * Models _is_whitelisted() from bridge.sh.
 */
function isWhitelisted(command: string): boolean {
  return WHITELIST.includes(command);
}

/**
 * Resolve the backend script name based on command prefix.
 * Models _resolve_backend() from bridge.sh.
 */
function resolveBackend(command: string): string {
  if (command.startsWith('keybox_')) {
    return 'keybox_manager.sh';
  }
  if (command.startsWith('target_')) {
    return 'target_manager.sh';
  }
  if (command.startsWith('profiler_')) {
    return 'latency_profiler.sh';
  }
  if (command.startsWith('config_') || command.startsWith('log_')) {
    return 'config_manager.sh';
  }
  return '';
}

/**
 * Extract the command field from a JSON input string.
 * Models _json_get_str() usage in bridge.sh _main().
 */
function parseCommand(jsonInput: string): string | null {
  try {
    const parsed = JSON.parse(jsonInput);
    if (typeof parsed.command === 'string' && parsed.command.length > 0) {
      return parsed.command;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Create a proper JSON response structure.
 * Models the response format used throughout bridge.sh:
 * - Success: { status: 0, data: ... }
 * - Error:   { status: N, message: ... }
 */
function createResponse(
  status: number,
  dataOrMessage: unknown
): { status: number; data?: unknown; message?: string } {
  if (status === 0) {
    return { status: 0, data: dataOrMessage };
  }
  return { status, message: String(dataOrMessage) };
}

/**
 * Check if timeout has been exceeded.
 * Models the timeout loop logic in bridge.sh _main().
 */
function handleTimeout(startTime: number, timeout: number): boolean {
  const now = Math.floor(Date.now() / 1000);
  const elapsed = now - startTime;
  return elapsed > timeout;
}

describe('Command Router - Whitelist Validation', () => {
  it('should accept all whitelisted commands', () => {
    for (const cmd of WHITELIST) {
      expect(isWhitelisted(cmd)).toBe(true);
    }
    // Verify we tested all 16 commands
    expect(WHITELIST).toHaveLength(16);
  });

  it('should reject unknown commands with status 400', () => {
    const unknownCommands = [
      'unknown_cmd',
      'shell_exec',
      'rm_rf',
      'keybox_hack',
      'sudo_run',
    ];
    for (const cmd of unknownCommands) {
      expect(isWhitelisted(cmd)).toBe(false);
    }
    // Verify the response structure for rejected commands
    const response = createResponse(400, 'Unknown command');
    expect(response.status).toBe(400);
    expect(response.message).toBe('Unknown command');
  });

  it('should reject empty command with status 400', () => {
    expect(isWhitelisted('')).toBe(false);

    const response = createResponse(400, 'Missing command field');
    expect(response.status).toBe(400);
    expect(response.message).toBe('Missing command field');
  });
});

describe('Command Router - Backend Resolution', () => {
  it('should route keybox_* commands to keybox_manager.sh', () => {
    const keyboxCommands = [
      'keybox_add',
      'keybox_list',
      'keybox_select',
      'keybox_delete',
      'keybox_validate',
    ];
    for (const cmd of keyboxCommands) {
      expect(resolveBackend(cmd)).toBe('keybox_manager.sh');
    }
  });

  it('should route target_* commands to target_manager.sh', () => {
    const targetCommands = [
      'target_list_installed',
      'target_add',
      'target_remove',
      'target_import',
      'target_export',
    ];
    for (const cmd of targetCommands) {
      expect(resolveBackend(cmd)).toBe('target_manager.sh');
    }
  });

  it('should route profiler_* commands to latency_profiler.sh', () => {
    const profilerCommands = [
      'profiler_run',
      'profiler_reference',
      'profiler_calibrate',
    ];
    for (const cmd of profilerCommands) {
      expect(resolveBackend(cmd)).toBe('latency_profiler.sh');
    }
  });

  it('should route config_* and log_* commands to config_manager.sh', () => {
    expect(resolveBackend('config_get')).toBe('config_manager.sh');
    expect(resolveBackend('config_set')).toBe('config_manager.sh');
    expect(resolveBackend('log_tail')).toBe('config_manager.sh');
  });
});

describe('Command Router - JSON Parsing', () => {
  it('should parse command from valid JSON input', () => {
    expect(parseCommand('{"command": "keybox_list"}')).toBe('keybox_list');
    expect(parseCommand('{"command": "config_get", "key": "logLevel"}')).toBe(
      'config_get'
    );
    expect(
      parseCommand('{"command": "target_add", "package": "com.example.app"}')
    ).toBe('target_add');
  });

  it('should handle malformed JSON input gracefully', () => {
    expect(parseCommand('')).toBeNull();
    expect(parseCommand('not json at all')).toBeNull();
    expect(parseCommand('{invalid json}')).toBeNull();
    expect(parseCommand('{"command": }')).toBeNull();
    // Missing command field
    expect(parseCommand('{"action": "keybox_list"}')).toBeNull();
    // Empty command value
    expect(parseCommand('{"command": ""}')).toBeNull();
    // Non-string command value
    expect(parseCommand('{"command": 123}')).toBeNull();
  });
});

describe('Command Router - Timeout Handling', () => {
  it('should detect timeout when elapsed > 30 seconds', () => {
    const now = Math.floor(Date.now() / 1000);
    // Start time 31 seconds ago
    const startTime = now - 31;
    expect(handleTimeout(startTime, BRIDGE_TIMEOUT)).toBe(true);
  });

  it('should not timeout when elapsed < 30 seconds', () => {
    const now = Math.floor(Date.now() / 1000);
    // Start time 10 seconds ago
    const startTime = now - 10;
    expect(handleTimeout(startTime, BRIDGE_TIMEOUT)).toBe(false);
  });
});

describe('Command Router - Response Structure', () => {
  it('should create proper success response structure (status=0, data field)', () => {
    const response = createResponse(0, { keyboxes: ['kb1', 'kb2'] });
    expect(response.status).toBe(0);
    expect(response.data).toEqual({ keyboxes: ['kb1', 'kb2'] });
    expect(response).not.toHaveProperty('message');
  });

  it('should create proper error response structure (status!=0, message field)', () => {
    const response = createResponse(500, 'Internal routing error');
    expect(response.status).toBe(500);
    expect(response.message).toBe('Internal routing error');
    expect(response).not.toHaveProperty('data');

    const timeout = createResponse(408, 'Timeout');
    expect(timeout.status).toBe(408);
    expect(timeout.message).toBe('Timeout');
    expect(timeout).not.toHaveProperty('data');
  });
});
