import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/error/exceptions.dart';
import '../models/auth_models.dart';

abstract interface class AuthSessionStorage {
  Future<AuthSessionModel?> read();

  Future<void> write(AuthSessionModel session);

  Future<void> clear();
}

class SecureAuthSessionStorage implements AuthSessionStorage {
  static const String _sessionKey = 'auth_session_v1';

  final FlutterSecureStorage _storage;

  SecureAuthSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<AuthSessionModel?> read() async {
    final rawSession = await _storage.read(key: _sessionKey);
    if (rawSession == null || rawSession.trim().isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(rawSession);
      if (json is! Map<String, dynamic>) {
        await clear();
        return null;
      }
      return AuthSessionModel.fromJson(json);
    } on Object catch (error) {
      if (error is! FormatException && error is! ServerException) rethrow;
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSessionModel session) {
    return _storage.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
