import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../../../core/error/exceptions.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthProvider with ChangeNotifier {
  final AuthRepository repository;

  AuthUser? _user;
  bool _isInitialized = false;
  bool _isLoggingIn = false;
  String? _loginError;

  AuthProvider({required this.repository});

  AuthUser? get user => _user;
  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _user != null && repository.accessToken != null;
  bool get isLoggingIn => _isLoggingIn;
  String? get loginError => _loginError;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      _user = await repository.restoreSession();
    } catch (error, stackTrace) {
      _user = repository.currentUser;
      developer.log(
        'Unable to validate the stored authentication session.',
        name: 'AuthProvider',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    if (_isLoggingIn) {
      return false;
    }

    _isLoggingIn = true;
    _loginError = null;
    notifyListeners();

    try {
      _user = await repository.login(username, password);
      return true;
    } on ServerException catch (error) {
      _loginError = _messageFor(error);
      return false;
    } catch (_) {
      _loginError = 'Đăng nhập không thành công. Vui lòng thử lại.';
      return false;
    } finally {
      _isLoggingIn = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final operation = repository.logout();
    _user = null;
    _loginError = null;
    notifyListeners();
    await operation;
  }

  void clearLoginError() {
    if (_loginError == null) {
      return;
    }
    _loginError = null;
    notifyListeners();
  }

  String _messageFor(ServerException error) {
    return switch (error.kind) {
      ApiFailureKind.network =>
        'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.',
      ApiFailureKind.timeout => 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.',
      ApiFailureKind.unauthorized => error.message,
      ApiFailureKind.forbidden => 'Tài khoản không có quyền truy cập ứng dụng.',
      _ => error.message,
    };
  }
}
