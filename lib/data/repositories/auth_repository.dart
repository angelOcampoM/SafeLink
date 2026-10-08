import '../models/user.dart';

/// U-01, U-02, G-01, U-05. Implementaciones: `MockAuthRepository` (hoy) y
/// `ApiAuthRepository` (cuando exista la API).
abstract interface class AuthRepository {
  AppUser? get currentUser;

  /// `POST /auth/login`
  Future<AppUser> login({required String email, required String password});

  /// `POST /auth/register` (solo `protected_user`).
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  });

  Future<void> logout();

  /// `GET /auth/me` — refresca bloqueo, contador de falsas alarmas, etc.
  Future<AppUser> refreshMe();

  /// `PATCH /users/me/settings`
  Future<AppUser> updateSettings({required bool shakeEnabled});
}
