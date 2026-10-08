// A-05 Historial con filtros
//
// TODO(A-05): filtros por rango de fechas, guardia y usuario.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../shared/widgets/widgets.dart';

class AdminHistoryPage extends StatefulWidget {
  const AdminHistoryPage({super.key});

  @override
  State<AdminHistoryPage> createState() => _AdminHistoryPageState();
}

class _AdminHistoryPageState extends State<AdminHistoryPage> {
  late final _repo = context.read<AdminRepository>();
  AlertStatus? _status;
  late Future<List<Alert>> _alerts = _repo.getHistory(const AlertHistoryFilter());

  void _setStatus(AlertStatus? s) => setState(() {
        _status = s;
        _alerts = _repo.getHistory(AlertHistoryFilter(status: s));
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                ChoiceChip(label: const Text('Todas'), selected: _status == null, onSelected: (_) => _setStatus(null)),
                for (final s in AlertStatus.values) ...[
                  AppSpacing.gapXs,
                  ChoiceChip(label: Text(s.label), selected: _status == s, onSelected: (_) => _setStatus(s)),
                ],
              ],
            ),
          ),
          AppSpacing.gapXs,
          Expanded(
            child: FutureBuilder<List<Alert>>(
              future: _alerts,
              builder: (context, snap) {
                final list = snap.data;
                if (list == null) return const LoadingView();
                if (list.isEmpty) return const EmptyState(icon: Icons.filter_alt_off_outlined, title: 'Sin alertas con este filtro');
                final now = DateTime.now();
                return ListView.separated(
                  padding: AppSpacing.screen,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => AppSpacing.gapSm,
                  itemBuilder: (_, i) => AlertCard(alert: list[i], now: now),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
