/// Builds validated, hash-addressed Moodlo Feelingverse narratives and episodes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

const String _downloadBase =
    'https://raw.githubusercontent.com/neuratim/moodlo-emoji/main/feelingverse';
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
  final sourceRoot = Directory('${root.path}/feelingverse/source');
  if (!sourceRoot.existsSync()) {
    stderr.writeln('Run from packages/moodlo/emoji.');
    exitCode = 64;
    return;
  }

  final narratives = <Map<String, Object?>>[];
  final narrativeFolders = sourceRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final narrativeFolder in narrativeFolders) {
    narratives.add(await _buildNarrative(root, narrativeFolder));
  }
  if (narratives.isEmpty) {
    throw const FormatException('At least one narrative is required.');
  }

  final catalogueFile = File('${root.path}/feelingverse/catalogue.json');
  final previous = _read(catalogueFile);
  final revision =
      previous != null &&
          jsonEncode(previous['narratives']) == jsonEncode(narratives)
      ? previous['revision'] as int
      : ((previous?['revision'] as int?) ?? 0) + 1;
  final catalogue = <String, Object?>{
    'downloadBase': _downloadBase,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'licence': 'CC0 1.0 Universal (public domain). No attribution required.',
    'narratives': narratives,
    'revision': revision,
    'schema': 1,
  };
  await catalogueFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(catalogue)}\n',
    flush: true,
  );
  final episodes = narratives.fold<int>(
    0,
    (count, narrative) =>
        count + (narrative['episodes']! as List<Object?>).length,
  );
  stdout.writeln(
    'Published ${narratives.length} narrative(s) and $episodes episode(s).',
  );
}

Future<Map<String, Object?>> _buildNarrative(
  Directory root,
  Directory narrativeFolder,
) async {
  final sourceFile = File('${narrativeFolder.path}/narrative.json');
  if (!sourceFile.existsSync()) {
    throw FormatException('${narrativeFolder.path} has no narrative.json.');
  }
  final narrative = _object(
    jsonDecode(await sourceFile.readAsString()),
    'narrative',
  );
  final id = _text(narrative, 'id');
  final number = narrative['number'];
  if (!RegExp(r'^\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id) ||
      _folderName(narrativeFolder) != id ||
      number is! int ||
      number < 0 ||
      number > 99 ||
      !id.startsWith('${number.toString().padLeft(2, '0')}-')) {
    throw FormatException(
      'Narrative id $id does not match its number or folder.',
    );
  }
  _validateNarrative(id, narrative);

  final episodes = <Map<String, Object?>>[];
  final episodeFolders =
      narrativeFolder.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final episodeFolder in episodeFolders) {
    episodes.add(await _buildEpisode(root, id, number, episodeFolder));
  }
  if (episodes.isEmpty) throw FormatException('$id has no episodes.');
  final ids = episodes.map((episode) => episode['id']).toSet();
  if (ids.length != episodes.length) {
    throw FormatException('$id has duplicate episode ids.');
  }

  return <String, Object?>{
    'episodes': episodes,
    'id': id,
    'localizations': narrative['localizations'],
    'number': number,
    'tags': narrative['tags'],
    'version': narrative['version'],
  };
}

Future<Map<String, Object?>> _buildEpisode(
  Directory root,
  String narrativeId,
  int narrativeNumber,
  Directory episodeFolder,
) async {
  final episodeNumber = int.tryParse(
    _folderName(episodeFolder).replaceFirst('E', ''),
  );
  final id =
      'N${narrativeNumber.toString().padLeft(2, '0')}E${episodeNumber?.toString().padLeft(2, '0')}';
  final sourceFile = File('${episodeFolder.path}/$id.json');
  if (!sourceFile.existsSync()) {
    throw FormatException('${episodeFolder.path} has no $id.json.');
  }
  final episode = _object(
    jsonDecode(await sourceFile.readAsString()),
    'episode',
  );
  final parsedId = _text(episode, 'id');
  if (episodeNumber == null ||
      episodeNumber < 1 ||
      episodeNumber > 99 ||
      !RegExp(r'^E\d{2}$').hasMatch(_folderName(episodeFolder)) ||
      parsedId != id ||
      episode['number'] != episodeNumber) {
    throw FormatException(
      'Episode $parsedId does not match $narrativeId/${_folderName(episodeFolder)}.',
    );
  }
  _validateEpisode(id, episode);

  final publishedFolder = Directory(
    '${root.path}/feelingverse/$narrativeId/episodes/${_folderName(episodeFolder)}',
  )..createSync(recursive: true);
  Map<String, Object?>? backdrop;
  final publishedPanels = <Map<String, Object?>>[];
  var totalBytes = 0;
  final panels = episode['panels']! as List<Object?>;
  final altTexts = episode['altTexts']! as List<Object?>;
  for (var index = 0; index < panels.length; index++) {
    final panel = _object(panels[index], '$id panel ${index + 1}');
    final expectedName = '${id}P${(index + 1).toString().padLeft(2, '0')}.png';
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
    '${publishedFolder.path}/$id.json',
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
    'cover': '$narrativeId/episodes/${_folderName(episodeFolder)}/${id}P01.png',
    'id': id,
    'localizations': <String, Object?>{
      for (final locale in _locales)
        locale: <String, Object?>{
          'title': _object(localizations[locale], '$id $locale')['title'],
        },
    },
    'number': episode['number'],
    'path': '$narrativeId/episodes/${_folderName(episodeFolder)}/$id.json',
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

void _validateNarrative(String id, Map<String, Object?> narrative) {
  if (narrative['schema'] != 1 ||
      narrative['version'] is! int ||
      (narrative['version']! as int) < 1) {
    throw FormatException('$id has an invalid schema or version.');
  }
  _validateLocalizations(id, narrative['localizations'], episode: false);
  _validateTags(id, narrative['tags']);
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
