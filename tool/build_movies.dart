/// Builds validated, hash-addressed Moodlo movie catalogues and episodes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

const String _downloadBase =
    'https://raw.githubusercontent.com/neuratim/moodlo-emoji/main/movies';
const List<String> _locales = <String>[
  'ar',
  'bn',
  'cs',
  'de',
  'en',
  'es',
  'fr',
  'hi',
  'id',
  'it',
  'ja',
  'ko',
  'pl',
  'pt',
  'ru',
  'tr',
  'vi',
  'zh',
];

Future<void> main() async {
  final root = Directory.current;
  final sourceRoot = Directory('${root.path}/movies/source');
  if (!sourceRoot.existsSync()) {
    stderr.writeln('Run from packages/moodlo/emoji.');
    exitCode = 64;
    return;
  }

  final movies = <Map<String, Object?>>[];
  final movieFolders = sourceRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final movieFolder in movieFolders) {
    movies.add(await _buildMovie(root, movieFolder));
  }
  if (movies.isEmpty) {
    throw const FormatException('At least one movie is required.');
  }

  final catalogueFile = File('${root.path}/movies/catalogue.json');
  final previous = _read(catalogueFile);
  final revision =
      previous != null && jsonEncode(previous['movies']) == jsonEncode(movies)
      ? previous['revision'] as int
      : ((previous?['revision'] as int?) ?? 0) + 1;
  final catalogue = <String, Object?>{
    'downloadBase': _downloadBase,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'licence': 'CC0 1.0 Universal (public domain). No attribution required.',
    'movies': movies,
    'revision': revision,
    'schema': 1,
  };
  await catalogueFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(catalogue)}\n',
    flush: true,
  );
  final episodes = movies.fold<int>(
    0,
    (count, movie) => count + (movie['episodes']! as List<Object?>).length,
  );
  stdout.writeln('Published ${movies.length} movie and $episodes episode.');
}

Future<Map<String, Object?>> _buildMovie(
  Directory root,
  Directory movieFolder,
) async {
  final sourceFile = File('${movieFolder.path}/movie.json');
  if (!sourceFile.existsSync()) {
    throw FormatException('${movieFolder.path} has no movie.json.');
  }
  final movie = _object(jsonDecode(await sourceFile.readAsString()), 'movie');
  final id = _text(movie, 'id');
  if (!RegExp(r'^[a-z][a-z0-9-]{2,31}$').hasMatch(id) ||
      _folderName(movieFolder) != id) {
    throw FormatException('Movie id $id does not match its folder.');
  }
  _validateMovie(id, movie);

  final episodes = <Map<String, Object?>>[];
  final episodeFolders = movieFolder.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final episodeFolder in episodeFolders) {
    episodes.add(await _buildEpisode(root, id, episodeFolder));
  }
  if (episodes.isEmpty) throw FormatException('$id has no episodes.');
  final ids = episodes.map((episode) => episode['id']).toSet();
  if (ids.length != episodes.length) {
    throw FormatException('$id has duplicate episode ids.');
  }

  return <String, Object?>{
    'episodes': episodes,
    'id': id,
    'localizations': movie['localizations'],
    'tags': movie['tags'],
    'version': movie['version'],
  };
}

Future<Map<String, Object?>> _buildEpisode(
  Directory root,
  String movieId,
  Directory episodeFolder,
) async {
  final sourceFile = File('${episodeFolder.path}/episode.json');
  if (!sourceFile.existsSync()) {
    throw FormatException('${episodeFolder.path} has no episode.json.');
  }
  final episode = _object(
    jsonDecode(await sourceFile.readAsString()),
    'episode',
  );
  final id = _text(episode, 'id');
  if (!RegExp(r'^s\d{3}$').hasMatch(id) || _folderName(episodeFolder) != id) {
    throw FormatException('Episode id $id does not match its folder.');
  }
  _validateEpisode(id, episode);

  final publishedFolder = Directory('${root.path}/movies/$movieId/episodes/$id')
    ..createSync(recursive: true);
  Map<String, Object?>? backdrop;
  final publishedPanels = <Map<String, Object?>>[];
  var totalBytes = 0;
  final panels = episode['panels']! as List<Object?>;
  final altTexts = episode['altTexts']! as List<Object?>;
  for (var index = 0; index < panels.length; index++) {
    final panel = _object(panels[index], '$id panel ${index + 1}');
    final expectedName = '${id}_p${(index + 1).toString().padLeft(2, '0')}.png';
    if (_text(panel, 'image') != expectedName) {
      throw FormatException('$id panel ${index + 1} must be $expectedName.');
    }
    final sourceImage = File('${episodeFolder.path}/$expectedName');
    if (!sourceImage.existsSync()) {
      throw FormatException('$expectedName is missing.');
    }
    final decoded = image.decodePng(await sourceImage.readAsBytes());
    if (decoded == null ||
        (decoded.width / decoded.height - 0.8).abs() > 0.01) {
      throw FormatException('$expectedName must be a decodable 4:5 PNG.');
    }
    final resized = decoded.width == 1024 && decoded.height == 1280
        ? decoded
        : image.copyResize(
            decoded,
            height: 1280,
            interpolation: image.Interpolation.cubic,
            width: 1024,
          );
    final bytes = Uint8List.fromList(image.encodePng(resized, level: 9));
    if (bytes.length > 3 * 1024 * 1024) {
      throw FormatException('$expectedName exceeds the 3 MiB panel limit.');
    }
    await File(
      '${publishedFolder.path}/$expectedName',
    ).writeAsBytes(bytes, flush: true);
    if (index == 0) {
      backdrop = _buildBackdrop(id, resized, episode['artworkHeightFraction']);
    }
    totalBytes += bytes.length;
    publishedPanels.add(<String, Object?>{
      'altText': altTexts[index],
      'bytes': bytes.length,
      'image': expectedName,
      'sha256': sha256.convert(bytes).toString(),
    });
  }

  final publishedEpisode = <String, Object?>{
    'id': id,
    'localizations': episode['localizations'],
    'number': episode['number'],
    'panels': publishedPanels,
    'schema': episode['schema'],
    'tags': episode['tags'],
    'version': episode['version'],
  };
  final episodeBytes = Uint8List.fromList(
    utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(publishedEpisode)}\n',
    ),
  );
  await File(
    '${publishedFolder.path}/episode.json',
  ).writeAsBytes(episodeBytes, flush: true);
  totalBytes += episodeBytes.length;
  if (totalBytes > 24 * 1024 * 1024) {
    throw FormatException('$id exceeds the 24 MiB episode limit.');
  }

  final localizations = _object(episode['localizations'], '$id localizations');
  if (backdrop == null) throw FormatException('$id has no backdrop source.');
  return <String, Object?>{
    'artworkHeightFraction': episode['artworkHeightFraction'] ?? 1,
    'backdrop': backdrop,
    'bytes': totalBytes,
    'cover': '$movieId/episodes/$id/${id}_p01.png',
    'id': id,
    'localizations': <String, Object?>{
      for (final locale in _locales)
        locale: <String, Object?>{
          'title': _object(localizations[locale], '$id $locale')['title'],
        },
    },
    'number': episode['number'],
    'path': '$movieId/episodes/$id/episode.json',
    'releaseDate': episode['releaseDate'],
    'sha256': sha256.convert(episodeBytes).toString(),
    'tags': episode['tags'],
    'version': episode['version'],
  };
}

Map<String, Object?> _buildBackdrop(
  String id,
  image.Image source,
  Object? rawFraction,
) {
  final fraction = rawFraction is num ? rawFraction.toDouble() : 1;
  final artworkHeight = (source.height * fraction).round().clamp(
    1,
    source.height,
  );
  final wideHeight = (source.width * 9 / 16).round();
  final cropHeight = artworkHeight < wideHeight ? artworkHeight : wideHeight;
  final cropTop = ((artworkHeight - cropHeight) / 2).round();
  final crop = image.copyCrop(
    source,
    height: cropHeight,
    width: source.width,
    x: 0,
    y: cropTop,
  );
  final resized = image.copyResize(
    crop,
    height: 135,
    interpolation: image.Interpolation.cubic,
    width: 240,
  );
  final bytes = Uint8List.fromList(image.encodeJpg(resized, quality: 44));
  if (bytes.length > 64 * 1024) {
    throw FormatException('$id backdrop exceeds 64 KiB.');
  }
  return <String, Object?>{
    'bytes': bytes.length,
    'data': base64Encode(bytes),
    'sha256': sha256.convert(bytes).toString(),
  };
}

String _folderName(Directory directory) =>
    directory.uri.pathSegments.where((part) => part.isNotEmpty).last;

Map<String, Object?> _object(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  throw FormatException('$label must be an object.');
}

Map<String, Object?>? _read(File file) {
  if (!file.existsSync()) return null;
  return _object(jsonDecode(file.readAsStringSync()), 'catalogue');
}

String _text(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('$key must be non-empty text.');
}

void _validateEpisode(String id, Map<String, Object?> episode) {
  final fraction = episode['artworkHeightFraction'] ?? 1;
  if (fraction is! num ||
      !fraction.isFinite ||
      fraction < 0.5 ||
      fraction > 1) {
    throw FormatException('$id has an invalid artwork height fraction.');
  }
  final release = _text(episode, 'releaseDate');
  final date = DateTime.tryParse(release);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(release) ||
      date == null ||
      date.toIso8601String().split('T').first != release) {
    throw FormatException('$id needs a valid releaseDate (YYYY-MM-DD).');
  }
  if (episode['schema'] != 1 ||
      episode['version'] is! int ||
      (episode['version']! as int) < 1 ||
      episode['number'] is! int ||
      (episode['number']! as int) < 1) {
    throw FormatException('$id has an invalid schema, number, or version.');
  }
  final altTexts = episode['altTexts'];
  final panels = episode['panels'];
  if (altTexts is! List<Object?> ||
      altTexts.length != 7 ||
      altTexts.any((text) => text is! String || text.trim().isEmpty)) {
    throw FormatException('$id must contain seven non-empty alt texts.');
  }
  if (panels is! List<Object?> || panels.length != 7) {
    throw FormatException('$id must contain exactly seven panels.');
  }
  _validateLocalizations(id, episode['localizations'], episode: true);
  _validateTags(id, episode['tags']);
}

void _validateLocalizations(String id, Object? value, {required bool episode}) {
  final localizations = _object(value, '$id localizations');
  if (!localizations.keys.toSet().containsAll(_locales) ||
      localizations.length != _locales.length) {
    throw FormatException(
      '$id must contain exactly ${_locales.length} supported locales.',
    );
  }
  for (final locale in _locales) {
    final translation = _object(localizations[locale], '$id $locale');
    if (episode) {
      _text(translation, 'title');
      final captions = translation['captions'];
      if (captions is! List<Object?> ||
          captions.length != 7 ||
          captions.any(
            (caption) => caption is! String || caption.length > 400,
          )) {
        throw FormatException('$id $locale must contain seven captions.');
      }
    } else {
      _text(translation, 'description');
      _text(translation, 'title');
    }
  }
}

void _validateMovie(String id, Map<String, Object?> movie) {
  if (movie['schema'] != 1 ||
      movie['version'] is! int ||
      (movie['version']! as int) < 1) {
    throw FormatException('$id has an invalid schema or version.');
  }
  _validateLocalizations(id, movie['localizations'], episode: false);
  _validateTags(id, movie['tags']);
}

void _validateTags(String id, Object? value) {
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.length > 12 ||
      value.any(
        (tag) => tag is! String || tag.trim().isEmpty || tag.length > 40,
      )) {
    throw FormatException('$id has invalid tags.');
  }
}
