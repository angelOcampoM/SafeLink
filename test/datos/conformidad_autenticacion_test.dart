// BE-02 — corre la suite de conformidad contra cada implementación.
//
// Cuando el equipo decida el backend (T-04), basta con agregar aquí su
// entorno: la suite es la misma y dice si cumple.
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/datos/nube_admin_repository.dart';
import 'package:safelink/datos/nube_alerta_guardia_repository.dart';
import 'package:safelink/datos/nube_auth_repository.dart';
import 'package:safelink/datos/safelink_service.dart';

import 'conformidad_autenticacion.dart';

void main() {
  pruebasDeAutenticacion('en memoria', () {
    final db = MemoriaBaseDatos(latencia: Duration.zero);
    return (
      auth: MemoriaAuthRepository(db),
      admin: MemoriaAdminRepository(db),
      guardia: MemoriaAlertaGuardiaRepository(db),
      cerrar: db.dispose,
    );
  });

  pruebasDeAutenticacion('contra la API', () {
    final s = SafeLinkService(
      servidor: MemoriaBaseDatos(latencia: Duration.zero),
      latenciaMin: Duration.zero,
      latenciaMax: Duration.zero,
    );
    return (
      auth: NubeAuthRepository(s),
      admin: NubeAdminRepository(s),
      guardia: NubeAlertaGuardiaRepository(s),
      cerrar: s.dispose,
    );
  });

  // TODO(BE-01): al elegir el backend en T-04, agregar aquí su entorno.
  //   pruebasDeAutenticacion('contra <backend>', () { ... });
}
