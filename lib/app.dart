import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/theme.dart';
import 'data/dependencies.dart';

class SafeLinkApp extends StatefulWidget {
  const SafeLinkApp({super.key, required this.deps});
  final AppDependencies deps;

  @override
  State<SafeLinkApp> createState() => _SafeLinkAppState();
}

class _SafeLinkAppState extends State<SafeLinkApp> {
  late final GoRouter _router = buildRouter(widget.deps.session);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ...widget.deps.providers,
        Provider<AppDependencies>.value(value: widget.deps),
      ],
      child: MaterialApp.router(
        title: 'SafeLink',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        locale: const Locale('es', 'MX'),
        supportedLocales: const [Locale('es', 'MX'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: _router,
      ),
    );
  }
}
