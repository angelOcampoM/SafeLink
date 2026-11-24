// CAPA: DOMINIO — coordenada geográfica
// Un punto latitud/longitud con igualdad por valor.
// No hace: no calcula distancias (eso es ReglaGeocerca) ni se convierte a JSON.

class PuntoGeo {
  const PuntoGeo(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is PuntoGeo && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'PuntoGeo($lat, $lng)';
}
