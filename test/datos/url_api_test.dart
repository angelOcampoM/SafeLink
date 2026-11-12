import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/url_api.dart';

void main() {
  test('https se acepta siempre', () {
    expect(urlApiPermitida('https://api.safelink.mx/api/v1', esRelease: true), isTrue);
    expect(urlApiPermitida('https://api.safelink.mx/api/v1', esRelease: false), isTrue);
  });

  test('http se rechaza en release/profile y se acepta en debug', () {
    expect(urlApiPermitida('http://127.0.0.1:3000/api/v1', esRelease: true), isFalse);
    expect(urlApiPermitida('http://127.0.0.1:3000/api/v1', esRelease: false), isTrue);
  });

  test('vacía, sin host o con otro esquema se rechaza', () {
    for (final url in ['', '   ', 'api.safelink.mx', 'ftp://x.mx', 'https://']) {
      expect(urlApiPermitida(url, esRelease: false), isFalse, reason: url);
    }
  });
}
