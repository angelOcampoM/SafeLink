// CAPA: PRESENTACIÓN — ViewModel
// G-03 Inicio del guardia (versión mínima): estado del turno y cierre de sesión.
// Carga el perfil y dice si el guardia está en turno, fuera de turno o sin zona.
// No importa material.dart y no navega. El dashboard completo llega en la Etapa 5.

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

enum EstadoTurno {
  enTurno('En turno'),
  fueraDeTurno('Fuera de turno'),
  sinZona('Sin zona');

  const EstadoTurno(this.etiqueta);
  final String etiqueta;
}

class InicioGuardiaViewModel extends ViewModel {
  InicioGuardiaViewModel(this._alertas, this._sesion, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final SesionViewModel _sesion;
  final DateTime Function() _reloj;

  EstadoVista<Guardia> perfil = const Cargando();

  DateTime get ahora => _reloj();

  /// `null` mientras no hay perfil.
  EstadoTurno? get estadoTurno {
    final g = perfil.datos;
    if (g == null) return null;
    if (!g.perfil.tieneCobertura) return EstadoTurno.sinZona;
    return g.disponibleA(ahora) ? EstadoTurno.enTurno : EstadoTurno.fueraDeTurno;
  }

  /// Por qué no recibe alertas, o `null` si está disponible.
  String? get motivoNoDisponible {
    final g = perfil.datos;
    return switch (estadoTurno) {
      EstadoTurno.sinZona => 'Aún no tienes una zona asignada. Pide al administrador tu radio de cobertura.',
      EstadoTurno.fueraDeTurno =>
        'Tu turno es de ${g!.perfil.inicioTurno} a ${g.perfil.finTurno}. No recibirás alertas hasta entonces.',
      _ => null,
    };
  }

  Future<void> cargar() async {
    if (perfil is! Listo) {
      perfil = const Cargando();
      notifyListeners();
    }
    try {
      perfil = Listo(await _alertas.obtenerMiPerfil());
    } catch (e) {
      perfil = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<void> cerrarSesion() => _sesion.cerrarSesion();
}
