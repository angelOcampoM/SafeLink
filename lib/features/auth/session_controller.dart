import 'package:flutter/foundation.dart';

import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';

/// Estado de sesión global. El router lo escucha para redirigir por rol.
class SessionController extends ChangeNotifier {
  SessionController(this._auth);
  final AuthRepository _auth;

  AppUser? get user => _auth.currentUser;
  bool get isLoggedIn => user != null;

  Future<AppUser> login(String email, String password) async {
    final u = await _auth.login(email: email, password: password);
    notifyListeners();
    return u;
  }

  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final u = await _auth.register(name: name, email: email, phone: phone, password: password);
    notifyListeners();
    return u;
  }

  Future<void> setShakeEnabled(bool value) async {
    await _auth.updateSettings(shakeEnabled: value);
    notifyListeners();
  }

  Future<void> refresh() async {
    await _auth.refreshMe();
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.logout();
    notifyListeners();
  }
}
