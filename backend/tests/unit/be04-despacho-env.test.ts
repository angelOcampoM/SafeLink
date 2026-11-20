// BE-04 paso 11 (D44): PUSH_MAX_TOKENS_PER_ALERT.
import { describe, expect, it } from 'vitest';
import { ConfigError, loadConfig } from '../../src/config/env.js';

const base = (extra: Record<string, string> = {}) => ({ JWT_SECRET: 'x'.repeat(32), NODE_ENV: 'test', ...extra });
const msg = (env: Record<string, string>): string => {
  try {
    loadConfig(env);
  } catch (e) {
    expect(e).toBeInstanceOf(ConfigError);
    return (e as Error).message;
  }
  throw new Error('Se esperaba ConfigError');
};

describe('PUSH_MAX_TOKENS_PER_ALERT (D44)', () => {
  it('por defecto es 500', () => {
    expect(loadConfig(base()).PUSH_MAX_TOKENS_PER_ALERT).toBe(500);
  });

  it('acepta los bordes 1 y 500 y un valor intermedio', () => {
    expect(loadConfig(base({ PUSH_MAX_TOKENS_PER_ALERT: '1' })).PUSH_MAX_TOKENS_PER_ALERT).toBe(1);
    expect(loadConfig(base({ PUSH_MAX_TOKENS_PER_ALERT: '500' })).PUSH_MAX_TOKENS_PER_ALERT).toBe(500);
    expect(loadConfig(base({ PUSH_MAX_TOKENS_PER_ALERT: '42' })).PUSH_MAX_TOKENS_PER_ALERT).toBe(42);
  });

  it.each(['0', '501', '-1', '1.5', 'abc'])('rechaza %s nombrando la variable', (v) => {
    expect(msg(base({ PUSH_MAX_TOKENS_PER_ALERT: v }))).toContain('PUSH_MAX_TOKENS_PER_ALERT');
  });
});
