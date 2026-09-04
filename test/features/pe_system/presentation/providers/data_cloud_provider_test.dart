import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/dataCloud_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/widgets/data_cloud_item.dart';

void main() {
  const baseUrl = 'https://example.test/api/data/';
  const rootPath = r'D:\DataCloud';

  test('fetches the configured API route with path and bearer token', () async {
    final tokenProvider = _FakeTokenProvider('access-token');
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/data/get-data');
      expect(request.url.queryParameters['path'], rootPath);
      expect(request.headers['authorization'], 'Bearer access-token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'currentPath': rootPath,
          'items': <Map<String, String>>[
            <String, String>{
              'name': 'Manuals',
              'path': r'D:\DataCloud\Manuals',
              'type': 'Folder',
            },
          ],
        }),
        200,
      );
    });
    final provider = DatacloudProvider(
      baseUrl: baseUrl,
      rootPath: rootPath,
      client: client,
      authTokenProvider: tokenProvider,
    );
    addTearDown(provider.dispose);

    await provider.fetchDataCloud();

    expect(provider.dataCloudError, isNull);
    expect(provider.dataCloudResponse?.items.single.name, 'Manuals');
    expect(provider.pathHistory, <String>[rootPath]);
  });

  test('refreshes an expired token and repeats the request', () async {
    var callCount = 0;
    final tokenProvider = _FakeTokenProvider(
      'expired-token',
      refreshedToken: 'new-token',
    );
    final client = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        expect(request.headers['authorization'], 'Bearer expired-token');
        return http.Response('Unauthorized', 401);
      }
      expect(request.headers['authorization'], 'Bearer new-token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'currentPath': rootPath,
          'items': <Object?>[],
        }),
        200,
      );
    });
    final provider = DatacloudProvider(
      baseUrl: baseUrl,
      rootPath: rootPath,
      client: client,
      authTokenProvider: tokenProvider,
    );
    addTearDown(provider.dispose);

    await provider.fetchDataCloud();

    expect(callCount, 2);
    expect(tokenProvider.refreshCount, 1);
    expect(provider.dataCloudError, isNull);
  });

  test('deleting from root refreshes the current folder', () async {
    var callCount = 0;
    final client = MockClient((request) async {
      callCount++;
      if (request.method == 'POST') {
        expect(request.url.path, '/api/data/delete-items');
        final body = jsonDecode(request.body) as List<dynamic>;
        expect(body.single['path'], r'D:\DataCloud\old.txt');
        return http.Response('', 204);
      }

      expect(request.url.path, '/api/data/get-data');
      expect(request.url.queryParameters['path'], rootPath);
      return http.Response(
        jsonEncode(<String, Object?>{
          'currentPath': rootPath,
          'items': <Object?>[],
        }),
        200,
      );
    });
    final provider = DatacloudProvider(
      baseUrl: baseUrl,
      rootPath: rootPath,
      client: client,
    );
    addTearDown(provider.dispose);

    final deleted = await provider.deleteItem(r'D:\DataCloud\old.txt', 'File');

    expect(deleted, isTrue);
    expect(callCount, 2);
    expect(provider.pathHistory, <String>[rootPath]);
    expect(provider.dataCloudError, isNull);
  });

  test('search and download use the published API routes', () async {
    final requestedPaths = <String>[];
    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path.endsWith('/search')) {
        expect(request.url.scheme, 'https');
        expect(request.url.queryParameters['keyword'], 'board 1');
        expect(request.url.queryParameters['path'], rootPath);
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'CurrentPath': rootPath,
              'Items': <Object?>[],
            },
          }),
          200,
        );
      }

      expect(request.url.queryParameters['path'], r'D:\DataCloud\guide.pdf');
      return http.Response.bytes(<int>[1, 2, 3], 200);
    });
    final provider = DatacloudProvider(
      baseUrl: baseUrl,
      rootPath: rootPath,
      client: client,
    );
    addTearDown(provider.dispose);

    await provider.searchDataCloud(' board 1 ');
    final download = await provider.downloadItem(
      DataCloudItem(
        name: 'guide.pdf',
        path: r'D:\DataCloud\guide.pdf',
        type: 'File',
      ),
    );

    expect(requestedPaths, <String>[
      '/api/data/search',
      '/api/data/download-file',
    ]);
    expect(download?.fileName, 'guide.pdf');
    expect(download?.bytes, <int>[1, 2, 3]);
    expect(provider.dataCloudError, isNull);
  });
}

class _FakeTokenProvider implements AuthTokenProvider {
  _FakeTokenProvider(this.accessToken, {this.refreshedToken});

  @override
  String? accessToken;
  final String? refreshedToken;
  int refreshCount = 0;

  @override
  Future<String?> refreshAccessToken() async {
    refreshCount++;
    accessToken = refreshedToken;
    return refreshedToken;
  }
}
