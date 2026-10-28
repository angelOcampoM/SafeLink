// A-03 Turnos y radios — guardar llama al repositorio con lo elegido.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/admin/cobertura_guardia_view_model.dart';

import 'espias.dart';

void main() {
  test('guardar llama al repositorio con el turno y el radio elegidos', () async {
    final repo = AdminEspia(guardia: guardiaPrueba());
    final vm = CoberturaGuardiaViewModel(repo, 'grd-1', config: Configuracion.porDefecto, centroPorDefecto: const PuntoGeo(0, 0));
    await vm.cargar();

    vm.cambiarInicio(22, 0);
    vm.cambiarFin(6, 0);
    vm.cambiarRadio(4530); // se redondea a 100 m
    final ok = await vm.guardar();

    expect(ok, isTrue);
    expect(repo.coberturas.single, (id: 'grd-1', inicio: '22:00', fin: '06:00', centro: puntoAlerta, radio: 4500));
    expect(vm.cruzaMedianoche, isTrue);
    expect(vm.duracionMinutos, 8 * 60);
  });

  test('el radio se mantiene entre 500 y 10 000 m y se refleja en el mapa', () async {
    final vm = CoberturaGuardiaViewModel(AdminEspia(guardia: guardiaPrueba()), 'grd-1', config: Configuracion.porDefecto, centroPorDefecto: puntoAlerta);
    await vm.cargar();

    vm.cambiarRadio(50);
    expect(vm.radioMetros, 500);
    vm.cambiarRadio(99999);
    expect(vm.radioMetros, 10000);
    expect(vm.radioFraccion, closeTo(0.45, 0.001));
  });

  test('un guardia sin zona usa el centro por defecto', () async {
    final sinZona = Guardia(
      usuario: guardiaPrueba().usuario,
      perfil: const PerfilGuardia(usuarioId: 'u-1', inicioTurno: '08:00', finTurno: '16:00', centroCobertura: null, radioCoberturaMetros: null),
    );
    final repo = AdminEspia(guardia: sinZona);
    const centro = PuntoGeo(18.84, -99.18);
    final vm = CoberturaGuardiaViewModel(repo, 'grd-8', config: Configuracion.porDefecto, centroPorDefecto: centro);
    await vm.cargar();

    await vm.guardar();
    expect(repo.coberturas.single.centro, centro);
    expect(repo.coberturas.single.radio, 3000);
  });
}
