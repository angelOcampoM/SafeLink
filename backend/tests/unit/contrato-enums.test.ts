// BE-01 paso 3: los enums de Prisma deben coincidir EXACTAMENTE con CodigosJson del front
// (lib/datos/nube_mapeadores.dart). Si el front y el esquema difieren, esta prueba falla.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const RAIZ = resolve(import.meta.dirname, '..', '..', '..');
const dart = readFileSync(resolve(RAIZ, 'lib/datos/nube_mapeadores.dart'), 'utf8');
const esquema = readFileSync(resolve(RAIZ, 'backend/prisma/schema.prisma'), 'utf8');

/** Valores de `static const <nombre> = { ... };` dentro de CodigosJson. */
function codigosDart(nombre: string): string[] {
  const clase = /abstract final class CodigosJson \{([\s\S]*?)\n\}/.exec(dart)?.[1] ?? '';
  const bloque = new RegExp(String.raw`static const ${nombre} = \{([\s\S]*?)\};`).exec(clase)?.[1];
  if (bloque === undefined) throw new Error(`No se encontró CodigosJson.${nombre} en el front`);
  return [...bloque.matchAll(/:\s*'([a-z_]+)'/g)].map((m) => m[1] as string);
}

/** Valores de `enum <nombre> { ... }` en schema.prisma (ignora comentarios y @@map). */
function valoresEsquema(nombre: string): string[] {
  const bloque = new RegExp(String.raw`enum ${nombre} \{([\s\S]*?)\n\}`).exec(esquema)?.[1];
  if (bloque === undefined) throw new Error(`No se encontró el enum ${nombre} en schema.prisma`);
  return bloque
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '' && !l.startsWith('//') && !l.startsWith('@@'));
}

const pares: [string, string, number][] = [
  ['rol', 'Role', 3],
  ['estado', 'AlertStatus', 8],
  ['metodo', 'TriggerMethod', 3],
  ['razon', 'EscalationReason', 2],
  ['resolucion', 'Resolution', 3],
];

describe('Contrato de enums front <-> schema.prisma (BE-01 paso 3)', () => {
  for (const [dartNombre, prismaNombre, cantidad] of pares) {
    it(`CodigosJson.${dartNombre} coincide exactamente con enum ${prismaNombre}`, () => {
      const front = codigosDart(dartNombre);
      expect(front).toHaveLength(cantidad);
      expect(valoresEsquema(prismaNombre).sort()).toEqual([...front].sort());
    });
  }

  it('el método de disparo "shake" se conserva (en la app es "doble clic de volumen")', () => {
    expect(valoresEsquema('TriggerMethod')).toContain('shake');
    expect(valoresEsquema('TriggerMethod')).not.toContain('volume');
  });
});
