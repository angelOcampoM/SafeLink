// CAPA: PRESENTACIÓN — View
// A-03 Turnos y radios de cobertura
// Selectores de hora de inicio/fin y Slider de radio (500–10 000 m) reflejado en
// el MapPlaceholder. Solo pasa lo que eligió el admin; no valida ni guarda.
//
// TODO(A-03): mover el centro de la zona tocando el mapa real.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dominio/dominio.dart';
import '../comun/formato.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';
import 'cobertura_guardia_view_model.dart';

class CoberturaGuardiaPage extends StatefulWidget {
  const CoberturaGuardiaPage({super.key, required this.viewModel});
  final CoberturaGuardiaViewModel viewModel;

  @override
  State<CoberturaGuardiaPage> createState() => _CoberturaGuardiaPageState();
}

class _CoberturaGuardiaPageState extends State<CoberturaGuardiaPage> {
  late final CoberturaGuardiaViewModel vm = widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.cargar();
  }

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> _elegirHora({required bool inicio}) async {
    final actual = ReglaTurno.aMinutos(inicio ? vm.inicioTurno : vm.finTurno);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: actual ~/ 60, minute: actual % 60),
      helpText: inicio ? 'Inicio del turno' : 'Fin del turno',
    );
    if (t == null) return;
    inicio ? vm.cambiarInicio(t.hour, t.minute) : vm.cambiarFin(t.hour, t.minute);
  }

  Future<void> _alGuardar() async {
    final ok = await vm.guardar();
    if (!ok || !mounted) return;
    context.showSnack('Turno y radio guardados');
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Turno y radio')),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => SlStateView<Guardia>(
          estado: vm.estado,
          onRetry: vm.cargar,
          builder: (context, g) => Column(
            children: [
              Expanded(
                child: ListView(
                  padding: AppSpacing.screen,
                  children: [
                    Text(g.usuario.nombre, style: context.text.titleLarge),
                    AppSpacing.gapMd,
                    if (vm.error != null) ...[SlBanner(type: SlBannerType.danger, message: vm.error!), AppSpacing.gapMd],
                    const SectionHeader('Turno'),
                    SlCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.login_rounded),
                            title: const Text('Inicio'),
                            trailing: Text(vm.inicioTurno, style: context.text.titleMedium),
                            onTap: () => _elegirHora(inicio: true),
                          ),
                          ListTile(
                            leading: const Icon(Icons.logout_rounded),
                            title: const Text('Fin'),
                            trailing: Text(vm.finTurno, style: context.text.titleMedium),
                            onTap: () => _elegirHora(inicio: false),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.gapXs,
                    Text(
                      'Duración ${Fmt.duration(vm.duracionMinutos * 60)}${vm.cruzaMedianoche ? ' · cruza medianoche' : ''}',
                      style: context.text.bodySmall,
                    ),
                    AppSpacing.gapLg,
                    SectionHeader('Radio de cobertura · ${Fmt.distance(vm.radioMetros)}'),
                    MapPlaceholder(
                      height: 260,
                      radiusFraction: vm.radioFraccion,
                      markers: const [MapMarker(offset: Offset.zero, color: AppColors.info, icon: Icons.shield_rounded)],
                    ),
                    Slider(
                      value: vm.radioMetros.toDouble(),
                      min: vm.radioMin.toDouble(),
                      max: vm.radioMax.toDouble(),
                      divisions: (vm.radioMax - vm.radioMin) ~/ 100,
                      label: Fmt.distance(vm.radioMetros),
                      onChanged: vm.cambiarRadio,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(Fmt.distance(vm.radioMin), style: context.text.labelSmall),
                        Text(Fmt.distance(vm.radioMax), style: context.text.labelSmall),
                      ],
                    ),
                    if (!g.perfil.tieneCobertura) ...[
                      AppSpacing.gapMd,
                      const SlBanner(type: SlBannerType.warning, message: 'Este guardia aún no tiene zona: no recibe alertas hasta que guardes un radio.'),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: AppSpacing.screen,
                  child: SlButton(label: 'Guardar', icon: Icons.save_outlined, loading: vm.guardando, onPressed: _alGuardar),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
