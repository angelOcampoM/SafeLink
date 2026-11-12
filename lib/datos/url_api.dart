// CAPA: DATOS — validación pura de la URL de la API (`--dart-define=API_URL=...`).
// En release/profile solo se acepta https:// (los tokens no deben viajar en
// claro). En debug también http:// (adb reverse, LAN de desarrollo).

bool urlApiPermitida(String url, {required bool esRelease}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  return switch (uri.scheme.toLowerCase()) {
    'https' => true,
    'http' => !esRelease,
    _ => false,
  };
}
