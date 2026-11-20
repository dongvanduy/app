import 'dart:collection';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/chat_models.dart';

const maximumChatImageBytes = 5 * 1024 * 1024;

String chatImageContentType(Uint8List bytes) {
  if (bytes.isEmpty) throw const FormatException('chatImageEmpty');
  if (bytes.length > maximumChatImageBytes) throw const FormatException('chatImageTooLarge');
  if (bytes.length >= 24 && bytes[0] == 137 && String.fromCharCodes(bytes.sublist(1, 4)) == 'PNG'
      && bytes[4] == 13 && bytes[5] == 10 && bytes[6] == 26 && bytes[7] == 10
      && String.fromCharCodes(bytes.sublist(12, 16)) == 'IHDR') return 'image/png';
  if (bytes.length >= 4 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255 && bytes[bytes.length - 2] == 255 && bytes.last == 217) return 'image/jpeg';
  if (bytes.length >= 20 && String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF'
      && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
      && ByteData.sublistView(bytes).getUint32(4, Endian.little) == bytes.length - 8
      && ['VP8 ', 'VP8L', 'VP8X'].contains(String.fromCharCodes(bytes.sublist(12, 16)))) return 'image/webp';
  throw const FormatException('chatImageUnsupported');
}

abstract interface class ChatPhotoPicker {
  Future<ChatDraftImage?> pick({required bool camera});
}

class ChatImageService implements ChatPhotoPicker {
  ChatImageService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;
  @override
  Future<ChatDraftImage?> pick({required bool camera}) async {
    final file = await _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, requestFullMetadata: false);
    if (file == null) return null;
    if (await file.length() > maximumChatImageBytes) throw const FormatException('chatImageTooLarge');
    final bytes = await file.readAsBytes();
    final type = chatImageContentType(bytes);
    return ChatDraftImage(bytes: bytes, contentType: type, fileName: 'chat.${type == 'image/jpeg' ? 'jpg' : type.split('/').last}');
  }
}

class ChatImageCache {
  ChatImageCache({this.maximumBytes = 20 * 1024 * 1024, this.onEvict});
  final int maximumBytes;
  final void Function(Uint8List)? onEvict;
  final _cache = LinkedHashMap<String, Uint8List>();
  final _pending = <String, Future<Uint8List>>{};
  int _bytes = 0, _generation = 0;
  int get byteLength => _bytes;
  Future<Uint8List> load(String key, Future<Uint8List> Function() fetch) {
    final cached = _cache.remove(key);
    if (cached != null) { _cache[key] = cached; return Future.value(cached); }
    if (_pending.containsKey(key)) return _pending[key]!;
    final generation = _generation;
    late final Future<Uint8List> operation;
    operation = Future.sync(fetch).then((bytes) {
      if (generation != _generation || !identical(_pending[key], operation)) throw StateError('Chat image request canceled');
      chatImageContentType(bytes);
      if (bytes.length <= maximumBytes) {
        while (_bytes + bytes.length > maximumBytes && _cache.isNotEmpty) {
          final removed = _cache.remove(_cache.keys.first)!;
          _bytes -= removed.length;
          onEvict?.call(removed);
        }
        _cache[key] = bytes;
        _bytes += bytes.length;
      }
      return bytes;
    }).whenComplete(() { if (identical(_pending[key], operation)) _pending.remove(key); });
    _pending[key] = operation;
    return operation;
  }
  void clear() {
    _generation++;
    for (final bytes in _cache.values) { onEvict?.call(bytes); }
    _cache.clear(); _pending.clear(); _bytes = 0;
  }
  void evictConversation(String id) {
    for (final key in _cache.keys.where((key) => key.startsWith('$id:')).toList()) {
      final bytes = _cache.remove(key)!; _bytes -= bytes.length; onEvict?.call(bytes);
    }
    _pending.removeWhere((key, value) => key.startsWith('$id:'));
  }
}
