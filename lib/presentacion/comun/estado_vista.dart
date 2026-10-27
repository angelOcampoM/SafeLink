// CAPA: PRESENTACIÓN — patrón State para pantallas que cargan datos
// Una pantalla siempre está en uno de cuatro estados: Cargando, Vacío, Error o
// Listo. Al ser `sealed`, el `switch` de la View obliga a cubrirlos todos.
// No hace: no carga nada; el ViewModel decide en qué estado está.
// (El error se llama `ErrorVista` para no ocultar el `Error` de dart:core.)

sealed class EstadoVista<T> {
  const EstadoVista();

  /// Lista vacía → `Vacio`; con elementos → `Listo`.
  static EstadoVista<List<E>> deLista<E>(List<E> lista) => lista.isEmpty ? Vacio<List<E>>() : Listo(lista);

  /// Los datos si está `Listo`, si no `null`.
  T? get datos => switch (this) {
        Listo<T>(:final datos) => datos,
        _ => null,
      };

  bool get cargando => this is Cargando<T>;
}

final class Cargando<T> extends EstadoVista<T> {
  const Cargando();
}

final class Vacio<T> extends EstadoVista<T> {
  const Vacio();
}

final class ErrorVista<T> extends EstadoVista<T> {
  const ErrorVista(this.mensaje);
  final String mensaje;
}

final class Listo<T> extends EstadoVista<T> {
  const Listo(this.datos);
  @override
  final T datos;
}
