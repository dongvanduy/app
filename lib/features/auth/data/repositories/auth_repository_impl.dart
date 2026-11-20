import 'dart:developer' as developer;

import '../../../../core/error/exceptions.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/auth_models.dart';
import '../storage/auth_session_storage.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthSessionStorage sessionStorage;

  AuthSessionModel? _session;
  Future<String?>? _refreshOperation;
  int _sessionGeneration = 0;
  int get sessionGeneration => _sessionGeneration;
  Future<void> _storageOperation = Future<void>.value();

  Future<void> _persist(Future<void> Function() operation) {
    final next = _storageOperation.then((_) => operation());
    _storageOperation = next.catchError((Object _) {});
    return next;
  }

  AuthRepositoryImpl({
    required this.remoteDataSource,
    required this.sessionStorage,
  });

  @override
  String? get accessToken => _session?.accessToken;

  @override
  AuthUser? get currentUser => _session?.user;

  @override
  Future<AuthUser?> restoreSession() async {
    final generation = ++_sessionGeneration;
    final restored = await sessionStorage.read();
    if (generation != _sessionGeneration) return null;
    _session = restored;
    final storedSession = _session;
    if (storedSession == null) {
      return null;
    }

    try {
      return await _loadCurrentUser(storedSession.accessToken);
    } on ServerException catch (error) {
      if (error.kind == ApiFailureKind.unauthorized) {
        return _restoreWithRefresh(storedSession.user);
      }
      if (_isTemporaryFailure(error)) {
        return storedSession.user;
      }
      rethrow;
    }
  }

  Future<AuthUser?> _restoreWithRefresh(AuthUser cachedUser) async {
    try {
      final refreshedToken = await refreshAccessToken();
      if (refreshedToken == null) {
        return null;
      }
      return await _loadCurrentUser(refreshedToken);
    } on ServerException catch (error) {
      if (_isTemporaryFailure(error)) {
        return cachedUser;
      }
      if (error.kind == ApiFailureKind.unauthorized) {
        await _clearSession();
        return null;
      }
      rethrow;
    }
  }

  Future<AuthUser> _loadCurrentUser(String token) async {
    final generation = _sessionGeneration;
    final user = await remoteDataSource.me(token);
    final session = _session;
    if (session == null || generation != _sessionGeneration) {
      throw const ServerException(
        'Authentication session is no longer available.',
        kind: ApiFailureKind.unauthorized,
      );
    }
    _session = session.copyWithUser(user);
    final updated = _session!;
    await _persist(() => sessionStorage.write(updated));
    return user;
  }

  @override
  Future<AuthUser> login(String username, String password) async {
    final generation = ++_sessionGeneration;
    _refreshOperation = null;
    final session = await remoteDataSource.login(
      username.trim(),
      password,
    );
    if (generation != _sessionGeneration) {
      throw const ServerException('Authentication session changed.', kind: ApiFailureKind.unauthorized);
    }
    _session = session;
    await _persist(() => sessionStorage.write(session));
    return session.user;
  }

  @override
  Future<String?> refreshAccessToken() {
    final activeRefresh = _refreshOperation;
    if (activeRefresh != null) {
      return activeRefresh;
    }

    final operation = _refreshTokens();
    _refreshOperation = operation;
    return operation.whenComplete(() {
      if (identical(_refreshOperation, operation)) {
        _refreshOperation = null;
      }
    });
  }

  Future<String?> _refreshTokens() async {
    final generation = _sessionGeneration;
    final currentSession = _session;
    if (currentSession == null || currentSession.refreshToken.isEmpty) {
      return null;
    }

    try {
      final refreshedSession =
          await remoteDataSource.refresh(currentSession.refreshToken);
      if (generation != _sessionGeneration) return null;
      _session = refreshedSession;
      await _persist(() => sessionStorage.write(refreshedSession));
      return generation == _sessionGeneration ? refreshedSession.accessToken : null;
    } on ServerException catch (error) {
      if (generation != _sessionGeneration) return null;
      if (error.kind == ApiFailureKind.unauthorized ||
          error.statusCode == 400) {
        await _clearSession();
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    final session = _session;
    await _clearSession();
    if (session == null) {
      return;
    }

    try {
      await remoteDataSource.logout(
        session.accessToken,
        session.refreshToken,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Remote logout failed after the local session was cleared.',
        name: 'AuthRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _clearSession() async {
    _sessionGeneration++;
    _refreshOperation = null;
    _session = null;
    await _persist(sessionStorage.clear);
  }

  bool _isTemporaryFailure(ServerException error) {
    return error.kind == ApiFailureKind.network ||
        error.kind == ApiFailureKind.timeout ||
        error.kind == ApiFailureKind.server;
  }
}
