/// Builds and refreshes Moodlo's public Feelingverse catalogue.
///
/// `dart run tool/build_feelingverse.dart` publishes every narrative from the
/// local production tree under `feelingverse/source/`.
///
/// `dart run tool/build_feelingverse.dart --sync` needs no production tree. It
/// re-reads the published episodes under `feelingverse/<narrative>/episodes/`,
/// checks each one against the rules the app applies, and refreshes what the
/// catalogue copies from them: episode titles, tags and versions, the card
/// backdrops, and the advisory file fingerprints. Edit an episode's text or
/// replace a panel in place, then run it; CI runs it on every push.
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

/// The reader scrolls, and a translation runs longer than the English it comes
/// from; the bound only keeps one caption from being unbounded.
const int _captionLimit = 1000;
const int _panelLimit = 5 * 1024 * 1024;
const int _panelMaxWidth = 2048;
const int _panelMinWidth = 640;

Future<void> main(List<String> arguments) async {
  final root = Directory.current;
  if (!Directory('${root.path}/feelingverse').existsSync()) {
    stderr.writeln('Run from packages/moodlo/emoji.');
    exitCode = 64;
    return;
  }
  final catalogueFile = File('${root.path}/feelingverse/catalogue.json');
  try {
    final narratives = arguments.contains('--sync')
        ? await _syncNarratives(root, catalogueFile)
        : await _buildNarratives(root);
    await _writeCatalogue(catalogueFile, narratives);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

Future<List<Map<String, Object?>>> _buildNarratives(Directory root) async {
  final sourceRoot = Directory('${root.path}/feelingverse/source');
  if (!sourceRoot.existsSync()) {
    throw const FormatException(
      'There is no feelingverse/source production tree here. To refresh the '
      'catalogue from the published episodes, run with --sync.',
    );
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
  return narratives;
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
  return _narrativeEntry(narrative, episodes);
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
  final panelFiles = <String, Object?>{};
  final publishedPanels = <Map<String, Object?>>[];
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
    _checkPanel(expectedName, bytes, decode: false);
    await File(
      '${publishedFolder.path}/$expectedName',
    ).writeAsBytes(bytes, flush: true);
    if (index == 0) {
      backdrop = _buildBackdrop(id, resized, episode['artworkHeightFraction']);
    }
    panelFiles[expectedName] = _sha256(bytes);
    publishedPanels.add(<String, Object?>{
      'altText': altTexts[index],
      'image': expectedName,
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

  if (backdrop == null) throw FormatException('$id has no backdrop source.');
  final folder = '$narrativeId/episodes/${_folderName(episodeFolder)}';
  return _episodeEntry(
    artworkHeightFraction: episode['artworkHeightFraction'] ?? 1,
    backdrop: backdrop,
    files: <String, Object?>{'$id.json': _sha256(episodeBytes), ...panelFiles},
    folder: folder,
    manifest: publishedEpisode,
    releaseDate: episode['releaseDate'],
  );
}

/// Refreshes every catalogue entry from its published episode. Every problem
/// is collected first and nothing is written unless all episodes pass.
Future<List<Map<String, Object?>>> _syncNarratives(
  Directory root,
  File catalogueFile,
) async {
  final catalogue = _read(catalogueFile);
  if (catalogue == null) {
    throw const FormatException('feelingverse/catalogue.json is missing.');
  }
  final rawNarratives = catalogue['narratives'];
  if (rawNarratives is! List<Object?> || rawNarratives.isEmpty) {
    throw const FormatException('The catalogue has no narratives.');
  }
  final problems = <String>[];
  final narratives = <Map<String, Object?>>[];
  for (final value in rawNarratives) {
    final narrative = _object(value, 'narrative');
    final id = _text(narrative, 'id');
    final rawEpisodes = narrative['episodes'];
    if (rawEpisodes is! List<Object?> || rawEpisodes.isEmpty) {
      problems.add('$id has no episodes.');
      continue;
    }
    try {
      _validateLocalizations(id, narrative['localizations'], episode: false);
      _validateTags(id, narrative['tags']);
    } on FormatException catch (error) {
      problems.add(error.message);
    }
    final entries = <Map<String, Object?>>[
      for (final entry in rawEpisodes) _object(entry, '$id episode'),
    ];
    final episodes = <Map<String, Object?>>[];
    for (final entry in entries) {
      try {
        episodes.add(await _syncEpisode(root, id, entry));
      } on FormatException catch (error) {
        problems.add(error.message);
      }
    }
    _warnUnlisted(root, id, entries);
    if (episodes.isNotEmpty) {
      narratives.add(_narrativeEntry(narrative, episodes));
    }
  }
  if (problems.isNotEmpty) {
    throw FormatException(
      'Nothing was written. Fix these and run again:\n'
      '${problems.map((problem) => '  - $problem').join('\n')}',
    );
  }
  return narratives;
}

Future<Map<String, Object?>> _syncEpisode(
  Directory root,
  String narrativeId,
  Map<String, Object?> entry,
) async {
  final id = _text(entry, 'id');
  final number = entry['number'];
  if (number is! int ||
      number < 1 ||
      number > 99 ||
      id !=
          'N${narrativeId.substring(0, 2)}E${number.toString().padLeft(2, '0')}') {
    throw FormatException('$narrativeId lists $id with number $number.');
  }
  final folder = '$narrativeId/episodes/E${number.toString().padLeft(2, '0')}';
  if (entry['path'] != '$folder/$id.json' ||
      entry['cover'] != '$folder/${id}P01.png') {
    throw FormatException('$id must be published under feelingverse/$folder/.');
  }
  _validateRelease(id, entry);

  final directory = '${root.path}/feelingverse/$folder';
  final manifestFile = File('$directory/$id.json');
  if (!manifestFile.existsSync()) {
    throw FormatException('$folder/$id.json is missing.');
  }
  final manifestBytes = await manifestFile.readAsBytes();
  final Map<String, Object?> manifest;
  try {
    manifest = _object(jsonDecode(utf8.decode(manifestBytes)), '$id.json');
  } on FormatException catch (error) {
    throw FormatException(
      '$folder/$id.json is not valid JSON: ${error.message}',
    );
  }
  _validatePublished(id, number, manifest);

  final previous = entry['files'] is Map
      ? _object(entry['files'], '$id files')
      : const <String, Object?>{};
  final files = <String, Object?>{'$id.json': _sha256(manifestBytes)};
  var backdrop = entry['backdrop'];
  for (var index = 1; index <= 7; index++) {
    final name = '${id}P${index.toString().padLeft(2, '0')}.png';
    final file = File('$directory/$name');
    if (!file.existsSync()) throw FormatException('$folder/$name is missing.');
    final bytes = await file.readAsBytes();
    final hash = _sha256(bytes);
    // Decoding is the slow part; a panel unchanged since the last sync was
    // decoded then, and its header is still checked below.
    final rebuildBackdrop =
        index == 1 && (previous[name] != hash || backdrop == null);
    final decoded = _checkPanel(
      name,
      bytes,
      decode: previous[name] != hash || rebuildBackdrop,
    );
    if (rebuildBackdrop) {
      backdrop = _buildBackdrop(id, decoded!, entry['artworkHeightFraction']);
    }
    files[name] = hash;
  }
  return _episodeEntry(
    artworkHeightFraction: entry['artworkHeightFraction'] ?? 1,
    backdrop: backdrop,
    files: files,
    folder: folder,
    manifest: manifest,
    releaseDate: entry['releaseDate'],
  );
}

Map<String, Object?> _episodeEntry({
  required Object artworkHeightFraction,
  required Object? backdrop,
  required Map<String, Object?> files,
  required String folder,
  required Map<String, Object?> manifest,
  required Object? releaseDate,
}) {
  final id = _text(manifest, 'id');
  final localizations = _object(manifest['localizations'], '$id localizations');
  return <String, Object?>{
    'artworkHeightFraction': artworkHeightFraction,
    'backdrop': backdrop,
    'cover': '$folder/${id}P01.png',
    'files': files,
    'id': id,
    'localizations': <String, Object?>{
      for (final locale in _locales)
        locale: <String, Object?>{
          'title': _object(localizations[locale], '$id $locale')['title'],
        },
    },
    'number': manifest['number'],
    'path': '$folder/$id.json',
    'releaseDate': releaseDate,
    'tags': manifest['tags'],
    'version': manifest['version'],
  };
}

/// The narrative card shows its first episode's scene; each episode card shows
/// its own, so a shelf of episodes is not one picture repeated.
Map<String, Object?> _narrativeEntry(
  Map<String, Object?> narrative,
  List<Map<String, Object?>> episodes,
) {
  final backdrop = episodes.first['backdrop'];
  if (backdrop == null) {
    throw FormatException('${narrative['id']} has no backdrop source.');
  }
  return <String, Object?>{
    'backdrop': backdrop,
    'episodes': episodes,
    'id': narrative['id'],
    'localizations': narrative['localizations'],
    'number': narrative['number'],
    'tags': narrative['tags'],
    'version': narrative['version'],
  };
}

/// Writes the catalogue with the next revision, or leaves the file untouched
/// when nothing it lists has changed.
Future<void> _writeCatalogue(
  File catalogueFile,
  List<Map<String, Object?>> narratives,
) async {
  final previous = _read(catalogueFile);
  final episodes = narratives.fold<int>(
    0,
    (count, narrative) =>
        count + (narrative['episodes']! as List<Object?>).length,
  );
  if (previous != null &&
      previous['schema'] == 3 &&
      jsonEncode(previous['narratives']) == jsonEncode(narratives)) {
    stdout.writeln(
      'The catalogue already matches all $episodes published episode(s).',
    );
    return;
  }
  final revision = ((previous?['revision'] as int?) ?? 0) + 1;
  final catalogue = <String, Object?>{
    'downloadBase': _downloadBase,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'licence': 'CC0 1.0 Universal (public domain). No attribution required.',
    'narratives': narratives,
    'revision': revision,
    'schema': 3,
  };
  await catalogueFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(catalogue)}\n',
    flush: true,
  );
  stdout.writeln(
    'Published ${narratives.length} narrative(s) and $episodes episode(s) '
    'as catalogue revision $revision.',
  );
}

int _bigEndian(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

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
    'sha256': _sha256(bytes),
  };
}

/// The app's panel rules: a PNG of at most 5 MiB, 640 to 2048 pixels wide, in
/// the reader's 4:5 portrait shape within 1 %. The header is always checked;
/// the full decode, which is slow, only when [decode] asks for it.
image.Image? _checkPanel(String name, Uint8List bytes, {required bool decode}) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length > _panelLimit) {
    throw FormatException('$name is larger than 5 MiB.');
  }
  if (bytes.length < 24 ||
      !List<int>.generate(
        8,
        (index) => bytes[index],
      ).indexed.every((byte) => byte.$2 == signature[byte.$1])) {
    throw FormatException('$name is not a PNG.');
  }
  final width = _bigEndian(bytes, 16);
  final height = _bigEndian(bytes, 20);
  if (width < _panelMinWidth ||
      width > _panelMaxWidth ||
      (width * 5 - height * 4).abs() * 100 > height * 4) {
    throw FormatException(
      '$name is $width x $height; a panel is 4:5 portrait, '
      '$_panelMinWidth to $_panelMaxWidth pixels wide.',
    );
  }
  if (!decode) return null;
  final decoded = image.decodePng(bytes);
  if (decoded == null || decoded.width != width || decoded.height != height) {
    throw FormatException('$name cannot be decoded.');
  }
  return decoded;
}

/// Text that went through a non-UTF-8 pipe: every character the code page
/// could not hold came out as `?` (or U+FFFD). A real question mark ends a
/// clause; it is never doubled and never runs straight into a letter.
final RegExp _damagedText = RegExp(r'�|\?\?|\?\p{L}', unicode: true);

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

String _readable(
  Map<String, Object?> object,
  String key,
  String label,
  int maxLength,
) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$label $key must be non-empty text.');
  }
  if (value.length > maxLength) {
    throw FormatException('$label $key is longer than $maxLength characters.');
  }
  if (_damagedText.hasMatch(value)) {
    throw FormatException('$label $key is encoding-damaged: $value');
  }
  return value;
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

String _text(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('$key must be non-empty text.');
}

void _validateEpisode(String id, Map<String, Object?> episode) {
  _validateRelease(id, episode);
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
      _readable(translation, 'title', '$id $locale', 160);
      final captions = translation['captions'];
      if (captions is! List<Object?> ||
          captions.length != 7 ||
          captions.any(
            (caption) => caption is! String || caption.length > _captionLimit,
          )) {
        throw FormatException(
          '$id $locale must contain seven captions of at most $_captionLimit '
          'characters.',
        );
      }
    } else {
      _readable(translation, 'description', '$id $locale', 240);
      _readable(translation, 'title', '$id $locale', 160);
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

/// The rules the app applies to a published manifest. Any other key a panel
/// carries is ignored by the app and therefore here.
void _validatePublished(String id, int number, Map<String, Object?> manifest) {
  if (manifest['schema'] != 1 ||
      manifest['id'] != id ||
      manifest['number'] != number) {
    throw FormatException(
      '$id.json must keep "schema": 1, "id": "$id" and "number": $number.',
    );
  }
  final version = manifest['version'];
  if (version is! int || version < 1) {
    throw FormatException('$id.json needs a positive whole-number version.');
  }
  _validateLocalizations(id, manifest['localizations'], episode: true);
  _validateTags(id, manifest['tags']);
  final panels = manifest['panels'];
  if (panels is! List<Object?> || panels.length != 7) {
    throw FormatException('$id.json must contain exactly seven panels.');
  }
  for (var index = 0; index < 7; index++) {
    final label = '$id.json panel ${index + 1}';
    final panel = _object(panels[index], label);
    final expected = '${id}P${(index + 1).toString().padLeft(2, '0')}.png';
    if (panel['image'] != expected) {
      throw FormatException('$label must name "$expected".');
    }
    _readable(panel, 'altText', label, 500);
  }
}

void _validateRelease(String id, Map<String, Object?> episode) {
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

/// An episode folder the catalogue does not list is left out: a new episode
/// needs a release date and card metadata, which the full build provides.
void _warnUnlisted(
  Directory root,
  String narrativeId,
  List<Map<String, Object?>> entries,
) {
  final directory = Directory(
    '${root.path}/feelingverse/$narrativeId/episodes',
  );
  if (!directory.existsSync()) return;
  final listed = entries
      .map((entry) => '${entry['path']}'.split('/')[2])
      .toSet();
  for (final folder in directory.listSync().whereType<Directory>()) {
    final name = _folderName(folder);
    if (!listed.contains(name)) {
      stderr.writeln(
        '$narrativeId/episodes/$name is not in the catalogue and was left out.',
      );
    }
  }
}
