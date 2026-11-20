// BE-05 · Reglas puras del escalamiento (D14), la nota administrativa y la falsa alarma (A-08).
// Unitaria: no toca la base.
import { describe, expect, it } from 'vitest';
import { adminNoteError, applyFalseAlarm, escalationReasonFor } from '../../src/domain/alert-rules.js';
import { loadConfig } from '../../src/config/env.js';

const AHORA = new Date('2026-11-19T18:00:00.000Z');
const LIMITES = { acceptTimeoutSeconds: 300, confirmTimeoutSeconds: 900 };
const hace = (segundos: number) => new Date(AHORA.getTime() - segundos * 1000);

describe('escalationReasonFor (U-09, A-04, D14)', () => {
  it('searching sin aceptar en ACCEPT_TIMEOUT_SECONDS escala "sin respuesta"; antes no', () => {
    expect(escalationReasonFor({ status: 'searching', statusChangedAt: hace(299) }, AHORA, LIMITES)).toBeNull();
    expect(escalationReasonFor({ status: 'searching', statusChangedAt: hace(300) }, AHORA, LIMITES)).toBe('no_response');
    expect(escalationReasonFor({ status: 'searching', statusChangedAt: hace(3600) }, AHORA, LIMITES)).toBe('no_response');
  });

  it('guard_arrived sin confirmar en CONFIRM_TIMEOUT_SECONDS escala "sin confirmación"', () => {
    expect(escalationReasonFor({ status: 'guard_arrived', statusChangedAt: hace(899) }, AHORA, LIMITES)).toBeNull();
    expect(escalationReasonFor({ status: 'guard_arrived', statusChangedAt: hace(900) }, AHORA, LIMITES)).toBe(
      'no_confirmation',
    );
  });

  it('cada caso usa su propio límite (el front usaba uno solo de demostración)', () => {
    // 400 s: pasó el de aceptar, no el de confirmar.
    expect(escalationReasonFor({ status: 'searching', statusChangedAt: hace(400) }, AHORA, LIMITES)).toBe('no_response');
    expect(escalationReasonFor({ status: 'guard_arrived', statusChangedAt: hace(400) }, AHORA, LIMITES)).toBeNull();
  });

  it('no_response heredado (semilla) también se escala como "sin respuesta"', () => {
    expect(escalationReasonFor({ status: 'no_response', statusChangedAt: hace(300) }, AHORA, LIMITES)).toBe('no_response');
  });

  it('nunca escalan pending_location, in_progress ni los estados finales (D14, D36)', () => {
    for (const status of ['pending_location', 'in_progress', 'closed', 'escalated', 'resolved_by_admin'] as const) {
      expect(escalationReasonFor({ status, statusChangedAt: hace(86_400) }, AHORA, LIMITES), status).toBeNull();
    }
  });
});

describe('adminNoteError (A-04)', () => {
  it('exige una nota con texto, recortada, de hasta el máximo', () => {
    expect(adminNoteError('', 300)).toBe('Escribe una nota administrativa para resolver la alerta');
    expect(adminNoteError('   ', 300)).toBe('Escribe una nota administrativa para resolver la alerta');
    expect(adminNoteError('a'.repeat(301), 300)).toBe('La nota no puede pasar de 300 caracteres');
    expect(adminNoteError(`  ${'a'.repeat(300)}  `, 300)).toBeNull();
    expect(adminNoteError('Se contactó al usuario', 300)).toBeNull();
  });

  it('el mensaje usa el máximo configurado', () => {
    expect(adminNoteError('abcdef', 5)).toBe('La nota no puede pasar de 5 caracteres');
  });
});

describe('applyFalseAlarm (A-08)', () => {
  it('debajo del límite solo suma y no toca el bloqueo', () => {
    expect(applyFalseAlarm(0, AHORA, 3, 7)).toEqual({ falseAlarmCount: 1 });
    expect(applyFalseAlarm(1, AHORA, 3, 7)).toEqual({ falseAlarmCount: 2 });
  });

  it('al llegar al límite bloquea BLOCK_DAYS días desde ahora', () => {
    expect(applyFalseAlarm(2, AHORA, 3, 7)).toEqual({
      falseAlarmCount: 3,
      blockedUntil: new Date('2026-11-26T18:00:00.000Z'),
    });
  });

  it('cada falsa alarma posterior renueva el bloqueo', () => {
    const despues = new Date('2026-11-21T00:00:00.000Z');
    expect(applyFalseAlarm(3, despues, 3, 7)).toEqual({
      falseAlarmCount: 4,
      blockedUntil: new Date('2026-11-28T00:00:00.000Z'),
    });
  });
});

describe('configuración del escalamiento', () => {
  const base = { JWT_SECRET: 'x'.repeat(32) };

  it('revisa cada 15 s por defecto y 0 lo apaga', () => {
    expect(loadConfig(base).ESCALATION_SWEEP_SECONDS).toBe(15);
    expect(loadConfig({ ...base, ESCALATION_SWEEP_SECONDS: '0' }).ESCALATION_SWEEP_SECONDS).toBe(0);
    expect(() => loadConfig({ ...base, ESCALATION_SWEEP_SECONDS: '-1' })).toThrow();
    expect(() => loadConfig({ ...base, ESCALATION_SWEEP_SECONDS: '301' })).toThrow();
  });
});
