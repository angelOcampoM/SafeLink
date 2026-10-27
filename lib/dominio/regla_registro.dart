// CAPA: DOMINIO — reglas de datos personales
// U-01 Registro · U-02 Inicio de sesión · A-01 Alta · A-02 Edición de guardia
// Nombre, correo, teléfono (10 dígitos) y contraseña. Cada regla devuelve el
// motivo del rechazo o `null`, así sirve igual al formulario y al ViewModel.
// No hace: no sabe si el correo ya existe (eso lo responde el repositorio).

abstract final class ReglaRegistro {
  static final _correoRe = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  static String? obligatorio(String? v, {String mensaje = 'Este campo es obligatorio'}) =>
      (v == null || v.trim().isEmpty) ? mensaje : null;

  static String? nombre(String? v) {
    final r = obligatorio(v, mensaje: 'Escribe tu nombre');
    if (r != null) return r;
    return v!.trim().length < 3 ? 'Escribe tu nombre completo' : null;
  }

  static String? correo(String? v) {
    final r = obligatorio(v, mensaje: 'Escribe tu correo');
    if (r != null) return r;
    return _correoRe.hasMatch(v!.trim()) ? null : 'Correo no válido';
  }

  /// 10 dígitos (sección 4.1).
  static String? telefono(String? v) {
    final r = obligatorio(v, mensaje: 'Escribe tu teléfono');
    if (r != null) return r;
    return RegExp(r'^\d{10}$').hasMatch(v!.trim()) ? null : 'Debe tener 10 dígitos';
  }

  static String? contrasena(String? v) {
    final r = obligatorio(v, mensaje: 'Escribe tu contraseña');
    if (r != null) return r;
    if (v!.length < 8) return 'Mínimo 8 caracteres';
    if (!RegExp(r'\d').hasMatch(v)) return 'Incluye al menos un número';
    return null;
  }

  static String? confirmarContrasena(String? original, String? v) =>
      v != original ? 'Las contraseñas no coinciden' : null;

  /// Inicio de sesión: solo pide que no estén vacíos.
  static String? contrasenaLogin(String? v) => obligatorio(v, mensaje: 'Escribe tu contraseña');
}
