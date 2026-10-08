import 'package:flutter/material.dart';

import 'app.dart';
import 'data/dependencies.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SafeLinkApp(deps: AppDependencies()));
}
