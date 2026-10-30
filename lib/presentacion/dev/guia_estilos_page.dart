// CAPA: PRESENTACIÓN — guía de estilos viva (solo modo debug)
// Muestra TODOS los tokens y componentes compartidos. Si agregas un componente a
// `presentacion/comun/widgets`, agrégalo también aquí.
// Acceso: botón "Ver guía de estilos" en el login.

import 'package:flutter/material.dart';

import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/tema/theme.dart';
import '../comun/widgets/widgets.dart';

class GuiaEstilosPage extends StatelessWidget {
  const GuiaEstilosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Guía de estilos'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Fundamentos'), Tab(text: 'Controles'), Tab(text: 'Contenido'), Tab(text: 'Especiales')],
          ),
        ),
        body: const TabBarView(
          children: [_Foundations(), _Controls(), _Content(), _Specials()],
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  const _Section(this.title, this.children, {this.note});
  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          if (note != null) ...[Text(note!, style: context.text.bodySmall), AppSpacing.gapSm],
          ...children,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color, this.usage);
  final String name;
  final Color color;
  final String usage;

  String get _hex => '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: color, borderRadius: AppRadius.brSm, border: Border.all(color: AppColors.border)),
          ),
          AppSpacing.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AppColors.$name', style: context.text.titleSmall),
                Text('$_hex · $usage', style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pestaña 1: Fundamentos ───────────────────────────────────────────
class _Foundations extends StatelessWidget {
  const _Foundations();

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final styles = <(String, TextStyle?)>[
      ('displayLarge · 56', t.displayLarge),
      ('displaySmall · 32', t.displaySmall),
      ('headlineMedium · 24', t.headlineMedium),
      ('titleLarge · 20', t.titleLarge),
      ('titleMedium · 16', t.titleMedium),
      ('bodyLarge · 16', t.bodyLarge),
      ('bodyMedium · 14', t.bodyMedium),
      ('bodySmall · 12', t.bodySmall),
      ('labelLarge · 16', t.labelLarge),
      ('labelSmall · 11', t.labelSmall),
    ];

    return ListView(
      padding: AppSpacing.screen,
      children: [
        const _Section('Superficies', [
          _Swatch('background', AppColors.background, 'Fondo de pantallas'),
          _Swatch('surface', AppColors.surface, 'Tarjetas, campos, hojas'),
          _Swatch('surfaceElevated', AppColors.surfaceElevated, 'Elemento sobre tarjeta'),
          _Swatch('border', AppColors.border, 'Bordes y divisores'),
        ]),
        const _Section('Texto', [
          _Swatch('textPrimary', AppColors.textPrimary, 'Títulos y texto principal'),
          _Swatch('textSecondary', AppColors.textSecondary, 'Descripciones'),
          _Swatch('textMuted', AppColors.textMuted, 'Placeholders, deshabilitado'),
        ]),
        const _Section('Semánticos', note: 'emergency es EXCLUSIVO del botón de alerta y alertas activas.', [
          _Swatch('emergency', AppColors.emergency, 'Botón de alerta, alerta activa'),
          _Swatch('warning', AppColors.warning, 'Urgente (agitación), pendiente'),
          _Swatch('success', AppColors.success, 'Confirmado, en turno, seguro'),
          _Swatch('info', AppColors.info, 'Acción principal, mapas, navegación'),
          _Swatch('danger', AppColors.danger, 'Errores de formulario, destructivo'),
        ]),
        _Section('Tipografía (Inter)', [
          for (final (name, style) in styles)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Guardia en camino', style: style),
                  Text(name, style: t.labelSmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
        ]),
        _Section('Espaciado (AppSpacing)', [
          for (final (name, v) in const [('xxs', 4.0), ('xs', 8.0), ('sm', 12.0), ('md', 16.0), ('lg', 24.0), ('xl', 32.0), ('xxl', 48.0)])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(width: 48, child: Text(name, style: t.labelMedium)),
                  Container(width: v * 3, height: 16, decoration: const BoxDecoration(color: AppColors.info, borderRadius: AppRadius.brSm)),
                  AppSpacing.gapXs,
                  Text('${v.toInt()} px', style: t.bodySmall),
                ],
              ),
            ),
        ]),
        _Section('Radios y táctil', [
          Row(
            children: [
              for (final (name, br) in const [('sm · 8', AppRadius.brSm), ('md · 16', AppRadius.brMd), ('pill', AppRadius.brPill)]) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(height: 56, decoration: BoxDecoration(color: AppColors.surface, borderRadius: br, border: Border.all(color: AppColors.info))),
                      AppSpacing.gapXxs,
                      Text(name, style: t.bodySmall),
                    ],
                  ),
                ),
                AppSpacing.gapSm,
              ],
            ],
          ),
          AppSpacing.gapSm,
          Text('Objetivo táctil mínimo: ${AppSizes.touchTarget.toInt()} px (alto de botones y filas).', style: t.bodyMedium),
        ]),
      ],
    );
  }
}

// ── Pestaña 2: Controles ─────────────────────────────────────────────
class _Controls extends StatefulWidget {
  const _Controls();

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _switch = true;
  bool _loading = false;
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.screen,
      children: [
        _Section('SlButton · variantes', [
          SlButton(label: 'Aceptar alerta', icon: Icons.check_rounded, onPressed: () {}),
          AppSpacing.gapSm,
          SlButton(label: 'Ya fui atendido', icon: Icons.check_circle_outline, variant: SlButtonVariant.success, onPressed: () {}),
          AppSpacing.gapSm,
          SlButton(label: 'Enviar alerta', icon: Icons.sos_rounded, variant: SlButtonVariant.emergency, onPressed: () {}),
          AppSpacing.gapSm,
          SlButton(label: 'Dar de baja', icon: Icons.person_off_outlined, variant: SlButtonVariant.danger, onPressed: () {}),
          AppSpacing.gapSm,
          SlButton(label: 'Abrir en Google Maps', icon: Icons.map_outlined, variant: SlButtonVariant.secondary, onPressed: () {}),
          AppSpacing.gapSm,
          SlButton(label: '¿Olvidaste tu contraseña?', variant: SlButtonVariant.ghost, onPressed: () {}),
        ]),
        _Section('SlButton · estados', [
          const SlButton(label: 'Deshabilitado (onPressed: null)', onPressed: null),
          AppSpacing.gapSm,
          SlButton(
            label: _loading ? 'Guardando…' : 'Toca para ver carga',
            loading: _loading,
            onPressed: () async {
              setState(() => _loading = true);
              await Future<void>.delayed(const Duration(seconds: 2));
              if (mounted) setState(() => _loading = false);
            },
          ),
          AppSpacing.gapSm,
          Row(
            children: [
              SlButton(label: 'expand: false', expand: false, onPressed: () {}),
              AppSpacing.gapSm,
              SlButton(label: 'Cancelar', expand: false, variant: SlButtonVariant.secondary, onPressed: () {}),
            ],
          ),
        ]),
        _Section('SlTextField', note: 'Toca "Validar" para ver el estado de error.', [
          Form(
            key: _formKey,
            child: Column(
              children: [
                const SlTextField(label: 'Correo electrónico', hint: 'nombre@correo.com', icon: Icons.mail_outline_rounded),
                AppSpacing.gapMd,
                const SlTextField(label: 'Contraseña', icon: Icons.lock_outline_rounded, obscure: true),
                AppSpacing.gapMd,
                SlTextField(label: 'Teléfono (con error)', icon: Icons.phone_outlined, validator: (_) => 'Debe tener 10 dígitos'),
                AppSpacing.gapMd,
                const SlTextField(label: 'Correo (error del ViewModel)', icon: Icons.mail_outline_rounded, errorText: 'Correo no válido'),
                AppSpacing.gapMd,
                const SlTextField(label: 'Deshabilitado', enabled: false, hint: 'No editable'),
                AppSpacing.gapMd,
                const SlTextField(label: 'Nota administrativa', hint: 'Multilínea, para textos largos', maxLines: 4, minLines: 3, maxLength: 300),
                AppSpacing.gapMd,
                SlButton(label: 'Validar', variant: SlButtonVariant.secondary, onPressed: () => _formKey.currentState!.validate()),
              ],
            ),
          ),
        ]),
        _Section('Switch, chips de filtro y navegación', [
          SlCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: _switch,
              onChanged: (v) => setState(() => _switch = v),
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Alerta por agitación'),
              subtitle: const Text('SwitchListTile dentro de SlCard'),
            ),
          ),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              ChoiceChip(label: const Text('Todas'), selected: true, onSelected: (_) {}),
              ChoiceChip(label: const Text('Escaladas'), selected: false, onSelected: (_) {}),
              ActionChip(label: const Text('ActionChip'), onPressed: () {}),
            ],
          ),
          AppSpacing.gapSm,
          SlButton(
            label: 'Mostrar SnackBar',
            variant: SlButtonVariant.secondary,
            onPressed: () => context.showSnack('Alerta marcada como "Resuelta"'),
          ),
        ]),
      ],
    );
  }
}

// ── Pestaña 3: Contenido ─────────────────────────────────────────────
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sample = Alerta(
      id: 'demo',
      usuarioId: 'u',
      nombreUsuario: 'Rosa María Díaz',
      estado: EstadoAlerta.buscando,
      metodo: MetodoDisparo.agitacion,
      disparadaEn: now.subtract(const Duration(minutes: 3)),
      evidenciaIncompleta: true,
    );

    return ListView(
      padding: AppSpacing.screen,
      children: [
        _Section('StatusChip · estados de alerta', [
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [for (final s in EstadoAlerta.values) StatusChip(s)]),
        ]),
        _Section('TriggerChip y resoluciones', [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final m in MetodoDisparo.values) TriggerChip(m),
              for (final r in Resolucion.values) SlChip.fromStyle(r.style),
            ],
          ),
        ]),
        const _Section('SlBanner', [
          SlBanner(message: 'Tu ubicación se comparte en tiempo real.'),
          AppSpacing.gapSm,
          SlBanner(type: SlBannerType.success, message: 'No hay usuarios bloqueados.'),
          AppSpacing.gapSm,
          SlBanner(type: SlBannerType.warning, title: 'Esperando ubicación', message: 'Activa el GPS para publicar tu alerta.'),
          AppSpacing.gapSm,
          SlBanner(type: SlBannerType.danger, message: 'Correo o contraseña incorrectos'),
        ]),
        _Section('SlCard', [
          const SlCard(child: Text('Tarjeta base')),
          AppSpacing.gapSm,
          SlCard(accent: AppColors.emergency, onTap: () {}, child: const Text('accent: emergency (alerta activa, tocable)')),
          AppSpacing.gapSm,
          const SlCard(accent: AppColors.warning, child: Text('accent: warning (urgente)')),
        ]),
        _Section('AlertCard', [
          AlertCard(alert: sample, now: now, distanceMeters: 640, onTap: () {}),
          AppSpacing.gapSm,
          AlertCard(alert: sample.copyWith(estado: EstadoAlerta.cerrada, resolucion: Resolucion.resuelta), now: now),
        ]),
        _Section('AlertDetailSheet', note: 'Detalle de una alerta del historial (usuario, guardia y admin).', [
          SlButton(
            label: 'Abrir detalle',
            variant: SlButtonVariant.secondary,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AlertDetailSheet(
                alert: sample.copyWith(
                  nombreGuardia: 'Carlos Hernández López',
                  notaAdmin: 'Se verificó con la usuaria; no hubo riesgo.',
                ),
              ),
            ),
          ),
        ]),
        _Section('SlStateView · Cargando, Vacío, Error y Listo', note: 'Pinta el EstadoVista del ViewModel. Con onRefresh agrega pull-to-refresh.', [
          SizedBox(height: 120, child: SlStateView<String>(estado: const Cargando(), builder: (_, d) => Text(d))),
          SizedBox(
            height: 220,
            child: SlStateView<String>(
              estado: const Vacio(),
              empty: const EmptyState(icon: Icons.inbox_outlined, title: 'Sin alertas'),
              builder: (_, d) => Text(d),
            ),
          ),
          SlStateView<String>(
            estado: const ErrorVista('No pudimos conectar con el servidor. Intenta de nuevo.'),
            onRetry: () => context.showSnack('Reintentar'),
            builder: (_, d) => Text(d),
          ),
          SlStateView<String>(
            estado: const Listo('Listo: aquí va el contenido'),
            builder: (_, d) => SlCard(child: Text(d)),
          ),
        ]),
        const _Section('MetricTile · InfoRow · InitialsAvatar', [
          Row(
            children: [
              Expanded(child: MetricTile(label: 'Aceptación promedio', value: '1 min', icon: Icons.timer_outlined)),
              AppSpacing.gapSm,
              Expanded(child: MetricTile(label: 'Sin respuesta', value: '6 %', icon: Icons.timer_off_outlined, color: AppColors.warning)),
            ],
          ),
          AppSpacing.gapSm,
          SlCard(
            child: Column(
              children: [
                InfoRow(icon: Icons.schedule_rounded, label: 'Hora', value: '18:17'),
                InfoRow(icon: Icons.near_me_outlined, label: 'Distancia', value: '640 m', valueColor: AppColors.info),
                InfoRow(icon: Icons.explore_outlined, label: 'Rumbo', value: '40° NE'),
              ],
            ),
          ),
          AppSpacing.gapSm,
          Row(
            children: [
              InitialsAvatar('CH'),
              AppSpacing.gapSm,
              InitialsAvatar('RD', color: AppColors.warning),
              AppSpacing.gapSm,
              InitialsAvatar('JO', color: AppColors.success),
            ],
          ),
        ]),
      ],
    );
  }
}

// ── Pestaña 4: Especiales ────────────────────────────────────────────
class _Specials extends StatelessWidget {
  const _Specials();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.screen,
      children: [
        _Section('EmergencyButton', note: 'Solo visual + gestos. La lógica de U-03/U-04 vive en la pantalla de inicio.', [
          Center(child: EmergencyButton(onTap: () => context.showSnack('onTap'))),
          const Center(child: EmergencyButton(enabled: false, label: 'BLOQUEADO')),
        ]),
        const _Section('MapPlaceholder', note: 'Mismo tamaño que tendrá GoogleMap. Con ruta, geocerca y cono de rumbo.', [
          MapPlaceholder(
            showRoute: true,
            radiusFraction: 0.12,
            markers: [
              MapMarker(offset: Offset(-0.6, 0.5), color: AppColors.info, icon: Icons.shield_rounded),
              MapMarker(offset: Offset(0.2, -0.1), color: AppColors.emergency, icon: Icons.person_pin_circle_rounded, heading: 40),
            ],
          ),
        ]),
        const _Section('EmptyState', [
          SlCard(
            child: EmptyState(
              icon: Icons.shield_outlined,
              color: AppColors.success,
              title: 'Todo tranquilo',
              message: 'No hay alertas en tu zona.',
            ),
          ),
        ]),
        const _Section('LoadingView', [SizedBox(height: 120, child: LoadingView(message: 'Cargando alertas…'))]),
      ],
    );
  }
}
