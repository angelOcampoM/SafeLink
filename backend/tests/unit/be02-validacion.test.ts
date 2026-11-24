// BE-02 · Validación de entrada del registro, los ajustes y el alta de guardias.
// Unitaria: no toca la base. Lo que el front valida (regla_registro.dart) debe
// valer también aquí, o el usuario ve un error que no entiende.
import { describe, expect, it } from 'vitest';
import { describeZodError } from '../../src/http/validate.js';
import { registerBodySchema, settingsBodySchema } from '../../src/modules/auth/schemas.js';
import { createGuardBodySchema, guardsQuerySchema, updateGuardBodySchema } from '../../src/modules/admin/schemas.js';

const VALIDO = {
  name: 'Ana López Ruiz',
  email: 'ana@safelink.mx',
  phone: '7771234567',
  password: 'SafeLink1',
};

/** Mensaje en español que vería la app, o null si el cuerpo es válido. */
function error(schema: typeof registerBodySchema, body: unknown): string | null {
  const r = schema.safeParse(body);
  return r.success ? null : describeZodError(r.error, body);
}

describe('POST /auth/register', () => {
  it('acepta un cuerpo válido y normaliza el correo', () => {
    const r = registerBodySchema.safeParse({ ...VALIDO, email: '  ANA@SafeLink.MX  ' });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.email).toBe('ana@safelink.mx');
  });

  it('exige nombre completo', () => {
    expect(error(registerBodySchema, { ...VALIDO, name: 'Al' })).toBe('Escribe tu nombre completo');
  });

  it('rechaza un correo sin formato', () => {
    for (const email of ['sin-arroba', 'a@b', 'a@b.', '@safelink.mx']) {
      expect(error(registerBodySchema, { ...VALIDO, email })).toBe('Correo no válido');
    }
  });

  it('exige teléfono de exactamente 10 dígitos', () => {
    for (const phone of ['123', '77712345678', '777-123-456', '']) {
      expect(error(registerBodySchema, { ...VALIDO, phone })).toBe('Debe tener 10 dígitos');
    }
  });

  it('exige contraseña de 8 o más con al menos un número', () => {
    expect(error(registerBodySchema, { ...VALIDO, password: 'corta1' })).toBe('Mínimo 8 caracteres');
    expect(error(registerBodySchema, { ...VALIDO, password: 'sinnumeros' })).toBe('Incluye al menos un número');
  });

  it('no deja pedir el rol: el registro público siempre crea usuario protegido', () => {
    expect(error(registerBodySchema, { ...VALIDO, role: 'admin' })).toBe('Campos no permitidos: role');
  });

  it('avisa qué campo falta', () => {
    const sinCorreo = { name: VALIDO.name, phone: VALIDO.phone, password: VALIDO.password };
    expect(error(registerBodySchema, sinCorreo)).toBe('El campo email es obligatorio');
  });
});

describe('PATCH /users/me/settings', () => {
  it('acepta el interruptor', () => {
    expect(settingsBodySchema.safeParse({ volumeDoubleClickEnabled: true }).success).toBe(true);
  });

  it('rechaza cualquier otro campo', () => {
    const r = settingsBodySchema.safeParse({ volumeDoubleClickEnabled: true, role: 'admin' });
    expect(r.success).toBe(false);
  });

  it('exige un booleano, no una cadena', () => {
    expect(settingsBodySchema.safeParse({ volumeDoubleClickEnabled: 'true' }).success).toBe(false);
  });
});

describe('POST /admin/guards', () => {
  it('pide las mismas reglas que el registro, incluida la contraseña inicial', () => {
    expect(createGuardBodySchema.safeParse(VALIDO).success).toBe(true);
    expect(error(createGuardBodySchema, { ...VALIDO, password: 'abcdefgh' })).toBe('Incluye al menos un número');
  });

  it('no deja elegir el rol del guardia', () => {
    expect(error(createGuardBodySchema, { ...VALIDO, role: 'admin' })).toBe('Campos no permitidos: role');
  });
});

describe('PATCH /admin/guards/:id', () => {
  it('acepta solo los campos que cambian', () => {
    expect(updateGuardBodySchema.safeParse({ name: 'Carlos Hernández López' }).success).toBe(true);
    expect(updateGuardBodySchema.safeParse({ phone: '7779998877' }).success).toBe(true);
  });

  it('no permite cambiar la contraseña ni el turno por aquí', () => {
    expect(updateGuardBodySchema.safeParse({ password: 'Otra1234' }).success).toBe(false);
    expect(updateGuardBodySchema.safeParse({ shiftStart: '09:00' }).success).toBe(false);
  });

  it('un cuerpo vacío no es una edición', () => {
    expect(updateGuardBodySchema.safeParse({}).success).toBe(false);
  });
});

describe('GET /admin/guards', () => {
  it('el front manda search siempre, aunque vaya vacío', () => {
    const r = guardsQuerySchema.safeParse({ search: '' });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.search).toBe('');
  });

  it('sin search se asume búsqueda vacía', () => {
    const r = guardsQuerySchema.safeParse({});
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.search).toBe('');
  });
});
