import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'source_page_loader.dart';

abstract class SourceImageLoader {
  Future<Uint8List> load(String url);
}

/// Only bounded raster downloads from article image URLs, without app headers.
class HttpSourceImageLoader implements SourceImageLoader {
  static final shared = HttpSourceImageLoader();
  final http.Client Function() clientFactory;
  final _cache = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};
  HttpSourceImageLoader({http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;

  @override
  Future<Uint8List> load(String url) {
    if (_cache.containsKey(url)) return Future.value(_cache[url]!);
    return _pending.putIfAbsent(
      url,
      () => _download(url)
          .then((bytes) {
            if (_cache.length >= 4) _cache.remove(_cache.keys.first);
            _cache[url] = bytes;
            return bytes;
          })
          .whenComplete(() {
            _pending.remove(url);
          }),
    );
  }

  Future<Uint8List> _download(String url) async {
    final client = clientFactory();
    try {
      var uri = Uri.parse(url);
      for (var redirect = 0; redirect <= 3; redirect++) {
        if (!HttpSourcePageLoader.isPublicPage(uri)) {
          throw const SourcePageException('Unsupported image URL.');
        }
        final response = await client
            .send(http.Request('GET', uri)..followRedirects = false)
            .timeout(const Duration(seconds: 8));
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null) break;
          uri = uri.resolve(location);
          continue;
        }
        if (response.statusCode != 200 ||
            !['image/png', 'image/jpeg', 'image/webp'].contains(
              response.headers['content-type']?.split(';').first.trim(),
            )) {
          throw const SourcePageException('Image unavailable.');
        }
        if ((response.contentLength ?? 0) > 2500000) {
          throw const SourcePageException('Image too large.');
        }
        final bytes = BytesBuilder(copy: false);
        await (() async {
          await for (final part in response.stream) {
            if (bytes.length + part.length > 2500000) {
              throw const SourcePageException('Image too large.');
            }
            bytes.add(part);
          }
        })().timeout(const Duration(seconds: 8));
        return bytes.takeBytes();
      }
      throw const SourcePageException('Image unavailable.');
    } finally {
      client.close();
    }
  }
}
