import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/core/network/auth_token_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/providers/dataCloud_provider.dart';
import 'package:mobile_app/features/pe_system/presentation/widgets/data_cloud_item.dart';

void main() {
  const baseUrl = 'https://example.test/api/datacloud/';
  const rootPath = '';

  test('fetches the configured API route with path and bearer token', () async {
    final tokenProvider = _FakeTokenProvider('access-token');
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/datacloud/get-data');
      expect(request.url.queryParameters['path'], rootPath);
      expect(request.url.queryParameters['scope'], 'Private');
      expect(request.headers['authorization'], 'Bearer access-token');
      return http.Response(
        jsonEncode(<String, Object?>{
          'currentPath': rootPath,
          'items': <Map<String, String>>[
            <String, String>{
              'name': 'Manuals',
              'path': 'Manuals',
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
        expect(request.url.path, '/api/datacloud/delete-items');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['items'], [
          {'scope': 'Private', 'path': 'old.txt', 'type': 'File'},
        ]);
        return http.Response('', 204);
      }

      expect(request.url.path, '/api/datacloud/get-data');
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

    final deleted = await provider.deleteItem('old.txt', 'File');

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

      expect(request.url.queryParameters['path'], 'guide.pdf');
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
      DataCloudItem(name: 'guide.pdf', path: 'guide.pdf', type: 'File'),
    );

    expect(requestedPaths, <String>[
      '/api/datacloud/search',
      '/api/datacloud/download-file',
    ]);
    expect(download?.fileName, 'guide.pdf');
    expect(download?.bytes, <int>[1, 2, 3]);
    expect(provider.dataCloudError, isNull);
  });

  test(
    'scope changes reset navigation and training blocks rename/delete',
    () async {
      final requests = <http.Request>[];
      final provider = DatacloudProvider(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          requests.add(request);
          return _listing(request.url.queryParameters['path'] ?? '');
        }),
      );
      addTearDown(provider.dispose);
      await provider.fetchDataCloud(path: r'Manuals\Boards');
      expect(provider.currentPath, 'Manuals/Boards');
      await provider.changeScope(DataCloudScope.public);
      expect(provider.pathHistory, ['']);
      expect(requests.last.url.queryParameters['scope'], 'Public');
      await provider.changeScope(DataCloudScope.dataTraining);
      expect(requests.last.url.queryParameters['scope'], 'DataTraining');
      final count = requests.length;
      expect(await provider.deleteItem('sample.txt', 'File'), isFalse);
      expect(
        await provider.renameItem(
          DataCloudItem(
            name: 'sample.txt',
            path: 'sample.txt',
            type: 'File',
            scope: DataCloudScope.dataTraining,
          ),
          'new.txt',
        ),
        isFalse,
      );
      expect(requests.length, count);
      expect(provider.allowDelete, isFalse);
      expect(provider.allowRename, isFalse);
    },
  );

  test(
    'create-folder uses multipart form binding and rename uses JSON',
    () async {
      final provider = DatacloudProvider(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          if (request.method == 'GET') return _listing('');
          if (request.url.path.endsWith('/create-folder')) {
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data;'),
            );
            expect(request.body, contains('name="Scope"\r\n\r\nPrivate'));
            expect(request.body, contains('name="Path"'));
            expect(request.body, contains('name="FolderName"\r\n\r\nManuals'));
          } else {
            expect(request.url.path, '/api/datacloud/rename-item');
            expect(jsonDecode(request.body), {
              'scope': 'Private',
              'path': 'Manuals',
              'type': 'Folder',
              'newName': 'Guides',
            });
          }
          return http.Response('{"success":true,"data":null}', 200);
        }),
      );
      addTearDown(provider.dispose);
      expect(
        await provider.createFolder(' Manuals '),
        isTrue,
        reason: provider.dataCloudError,
      );
      expect(
        await provider.renameItem(
          DataCloudItem(name: 'Manuals', path: 'Manuals', type: 'Folder'),
          'Guides',
        ),
        isTrue,
      );
    },
  );

  test(
    'folder upload preserves relative filenames through a token retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'datacloud-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/guide.txt',
      ).writeAsString('board guide');
      var uploads = 0;
      final tokens = _FakeTokenProvider('expired', refreshedToken: 'fresh');
      final provider = DatacloudProvider(
        baseUrl: baseUrl,
        authTokenProvider: tokens,
        client: MockClient((request) async {
          if (request.method == 'GET') return _listing('');
          uploads++;
          expect(request.url.path, '/api/datacloud/upload-folder');
          expect(request.body, contains('name="Scope"\r\n\r\nPrivate'));
          expect(
            request.body,
            contains('name="Files"; filename="Manuals/Boards/guide.txt"'),
          );
          expect(request.body, contains('board guide'));
          if (uploads == 1) return http.Response('', 401);
          expect(request.headers['authorization'], 'Bearer fresh');
          return http.Response('{"success":true}', 200);
        }),
      );
      addTearDown(provider.dispose);
      expect(
        await provider.uploadFiles(
          [file],
          isFolder: true,
          relativePaths: [r'Manuals\Boards\guide.txt'],
        ),
        isTrue,
      );
      expect(uploads, 2);
      expect(tokens.refreshCount, 1);
    },
  );

  test(
    'search accepts relativePath and download uses item scope and server name',
    () async {
      final provider = DatacloudProvider(
        baseUrl: baseUrl,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/search')) {
            expect(request.url.queryParameters['scope'], 'Private');
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [
                    {
                      'name': 'guide.pdf',
                      'relativePath': 'Manuals/guide.pdf',
                      'scope': 'Public',
                      'type': 'File',
                    },
                  ],
                },
              }),
              200,
            );
          }
          expect(request.url.queryParameters, {
            'scope': 'Public',
            'path': 'Manuals/guide.pdf',
          });
          return http.Response.bytes(
            [255, 0, 1],
            200,
            headers: {
              'content-disposition':
                  "attachment; filename*=UTF-8''board%20guide.pdf",
            },
          );
        }),
      );
      addTearDown(provider.dispose);
      await provider.searchDataCloud('guide');
      final item = provider.dataCloudResponse!.items.single;
      final download = await provider.downloadItem(item);
      expect(download!.fileName, 'board guide.pdf');
      expect(download.bytes, [255, 0, 1]);
    },
  );

  test('business errors with HTTP 200 are not treated as success', () async {
    final provider = DatacloudProvider(
      baseUrl: baseUrl,
      client: MockClient(
        (_) async =>
            http.Response('{"success":false,"message":"Folder exists"}', 200),
      ),
    );
    addTearDown(provider.dispose);
    expect(await provider.createFolder('Manuals'), isFalse);
    expect(provider.dataCloudError, contains('Folder exists'));
    expect(provider.isLoadingDataCloud, isFalse);
  });

  test(
    'relative paths keep DataCloud-named folders and reject drive paths',
    () {
      expect(
        normalizeDataCloudPath(r'/Manuals\DataCloud/'),
        'Manuals/DataCloud',
      );
      expect(normalizeDataCloudPath(''), '');
      expect(
        () => normalizeDataCloudPath(r'D:\DataCloud'),
        throwsFormatException,
      );
      expect(() => normalizeDataCloudPath('../Public'), throwsFormatException);
    },
  );
}

http.Response _listing(String path) => http.Response(
  jsonEncode({
    'success': true,
    'data': {'currentPath': path, 'items': []},
  }),
  200,
);

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
