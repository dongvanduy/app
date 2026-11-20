import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:mobile_app/features/auth/data/models/auth_models.dart';
import 'package:mobile_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:mobile_app/features/auth/data/storage/auth_session_storage.dart';

class MemoryChatAuthStorage implements AuthSessionStorage {
  AuthSessionModel? value;
  @override
  Future<AuthSessionModel?> read() async => value;
  @override
  Future<void> write(AuthSessionModel session) async { value = session; }
  @override
  Future<void> clear() async { value = null; }
}

Map<String, dynamic> session(String token, int id) => {'accessToken':token,'refreshToken':'refresh-$token',
  'user':{'userId':id,'username':'user$id','role':'User','allowedAreas':'','permissions':<String>[],
    'fullName':'User $id','chineseName':'','email':'','department':'PE','cft':'Adapter'}};

void main() {
  for (final failOldRefresh in [false, true]) {
    test('old refresh ${failOldRefresh ? 'failure' : 'success'} cannot overwrite a new login', () async {
      final storage = MemoryChatAuthStorage(); final refreshed = Completer<http.Response>();
      final enteredRefresh = Completer<void>(); var login = 0;
      final auth = AuthRepositoryImpl(sessionStorage: storage, remoteDataSource: AuthRemoteDataSource(apiClient:
        ApiClient(baseUrl:'https://example.test/api/', client:MockClient((request) async {
          if (request.url.path.endsWith('/login')) return http.Response(jsonEncode(session('login-${++login}', login)), 200);
          if (request.url.path.endsWith('/refresh')) { enteredRefresh.complete(); return refreshed.future; }
          return http.Response('{}',200);
        }))));
      await auth.login('first', 'password');
      final operation = auth.refreshAccessToken(); await enteredRefresh.future;
      await auth.logout(); await auth.login('second', 'password');
      refreshed.complete(http.Response(jsonEncode(session('stale-refresh',1)), failOldRefresh ? 401 : 200));
      expect(await operation, isNull); expect(auth.accessToken, 'login-2'); expect(storage.value!.accessToken, 'login-2');
    });
  }
}
