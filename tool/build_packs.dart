import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const _categories = <String, String>{
  'emotions': 'emotion',
  'gallery': 'gallery',
  'levels': 'level',
};
const _expectedCounts = <String, int>{
  'emotions': 11,
  'gallery': 54,
  'levels': 9,
};
const _idPattern = r'^[a-z][a-z0-9-]*$';
const _identityPattern = r'^[A-Za-z][A-Za-z0-9_]*$';
const _maxImageBytes = 1024 * 1024;
const _maxImageEdge = 768;

Future<void> main() async {
  final root = Directory.current;
  final definitionsFile = File('${root.path}/styles.json');
  if (!definitionsFile.existsSync()) {
    stderr.writeln('Run this command from the emoji repository root.');
    exitCode = 64;
    return;
  }

  final definitions = _object(
    jsonDecode(await definitionsFile.readAsString()),
    'styles.json',
  );
  final downloadBase = _requiredText(definitions, 'downloadBase');
  final licence = _requiredText(definitions, 'licence');
  final schema = _requiredInt(definitions, 'schema');
  if (schema != 1) throw const FormatException('styles.json schema must be 1');
  final rawStyles = definitions['styles'];
  if (rawStyles is! List || rawStyles.isEmpty) {
    throw const FormatException('styles.json styles must be a non-empty list');
  }

  final styles = rawStyles.map((value) => _object(value, 'style')).toList()
    ..sort((a, b) => _requiredText(a, 'id').compareTo(_requiredText(b, 'id')));
  final existing = File('${root.path}/catalogue.json');
  Map<String, Object?>? previousCatalogue;
  final previousStyles = <String, Map<String, Object?>>{};
  if (existing.existsSync()) {
    try {
      previousCatalogue = _object(
        jsonDecode(await existing.readAsString()),
        'catalogue.json',
      );
      final rawPreviousStyles = previousCatalogue['styles'];
      if (rawPreviousStyles is List) {
        for (final value in rawPreviousStyles) {
          final style = _object(value, 'previous style');
          previousStyles[_requiredText(style, 'id')] = style;
        }
      }
    } on Object {
      previousCatalogue = null;
      previousStyles.clear();
    }
  }
  final ids = <String>{};
  final catalogueStyles = <Map<String, Object?>>[];
  final packsDirectory = Directory('${root.path}/packs')
    ..createSync(recursive: true);
  final previewsDirectory = Directory('${root.path}/previews')
    ..createSync(recursive: true);

  for (final style in styles) {
    final bundled = style['bundled'];
    final id = _requiredText(style, 'id');
    final version = _requiredInt(style, 'version');
    if (!RegExp(_idPattern).hasMatch(id) || !ids.add(id)) {
      throw FormatException('Invalid or duplicate style id: $id');
    }
    if (bundled is! bool) {
      throw FormatException('$id bundled must be a boolean');
    }
    if (version <= 0) throw FormatException('$id version must be positive');

    final source = Directory('${root.path}/source/$id');
    if (!source.existsSync()) throw FormatException('Missing source/$id');
    final assets = <Map<String, Object?>>[];
    final archive = Archive();

    for (final category in _categories.keys) {
      final directory = Directory('${source.path}/$category');
      final files = directory.existsSync()
          ? directory
                .listSync()
                .whereType<File>()
                .where((file) => file.path.endsWith('.webp'))
                .toList()
          : <File>[];
      files.sort((a, b) => a.path.compareTo(b.path));
      if (files.length != _expectedCounts[category]) {
        throw FormatException(
          '$id/$category has ${files.length}; expected ${_expectedCounts[category]}',
        );
      }
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final identity = name.substring(0, name.length - '.webp'.length);
        if (!RegExp(_identityPattern).hasMatch(identity)) {
          throw FormatException(
            '$id/$category has an invalid identity: $identity',
          );
        }
        final bytes = await file.readAsBytes();
        _validateWebp(bytes, '$id/$category/$name');
        final path = 'emoji/$category/$name';
        assets.add(<String, Object?>{
          'bytes': bytes.length,
          'key': '${_categories[category]}:$identity',
          'path': path,
          'sha256': sha256.convert(bytes).toString(),
        });
        archive.addFile(_archiveFile(path, bytes));
      }
    }

    assets.sort((a, b) => (a['key']! as String).compareTo(b['key']! as String));
    final pack = <String, Object?>{
      'assets': assets,
      'description': _requiredText(style, 'description'),
      'id': id,
      'licence': licence,
      'localizations': style['localizations'] is Map
          ? style['localizations']
          : const <String, Object?>{},
      'name': _requiredText(style, 'name'),
      'schema': 1,
      'version': version,
    };
    final packBytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(pack)}\n',
    );
    archive.addFile(_archiveFile('pack.json', packBytes));

    final encoded = Uint8List.fromList(ZipEncoder().encode(archive, level: 0));
    final encodedSha256 = sha256.convert(encoded).toString();
    final previousStyle = previousStyles[id];
    if (previousStyle != null) {
      final previousVersion = _requiredInt(previousStyle, 'version');
      if (version < previousVersion) {
        throw FormatException(
          '$id version $version is older than published version $previousVersion',
        );
      }
      if (version == previousVersion &&
          encodedSha256 != _requiredText(previousStyle, 'sha256')) {
        throw FormatException(
          '$id version $version changed; increment its version before publishing',
        );
      }
    }
    final archiveName = '$id-$version.zip';
    final archiveFile = File('${packsDirectory.path}/$archiveName');
    await archiveFile.writeAsBytes(encoded, flush: true);

    final previewSource = File('${source.path}/emotions/happy.webp');
    if (!previewSource.existsSync()) {
      throw FormatException('$id is missing emotions/happy.webp');
    }
    final previewName = '$id.webp';
    final previewBytes = await previewSource.readAsBytes();
    await previewSource.copy('${previewsDirectory.path}/$previewName');

    catalogueStyles.add(<String, Object?>{
      'archive': 'packs/$archiveName',
      'bundled': bundled,
      'bytes': encoded.length,
      'description': pack['description'],
      'id': id,
      'localizations': pack['localizations'],
      'name': pack['name'],
      'preview': 'previews/$previewName',
      'previewBytes': previewBytes.length,
      'previewSha256': sha256.convert(previewBytes).toString(),
      'sha256': encodedSha256,
      'version': version,
    });
  }

  var generatedAt = DateTime.now().toUtc().toIso8601String();
  var revision = 1;
  final old = previousCatalogue;
  if (old != null) {
    final oldRevision = old['revision'];
    if (oldRevision is int && oldRevision > 0) revision = oldRevision;
    final comparable = Map<String, Object?>.from(old)
      ..remove('generatedAt')
      ..remove('revision');
    final nextComparable = <String, Object?>{
      'downloadBase': downloadBase,
      'licence': licence,
      'schema': 1,
      'styles': catalogueStyles,
    };
    if (jsonEncode(comparable) != jsonEncode(nextComparable)) {
      revision++;
    } else if (old['generatedAt'] case final String oldGeneratedAt) {
      generatedAt = oldGeneratedAt;
    }
  }

  final catalogue = <String, Object?>{
    'downloadBase': downloadBase,
    'generatedAt': generatedAt,
    'licence': licence,
    'revision': revision,
    'schema': 1,
    'styles': catalogueStyles,
  };
  await existing.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(catalogue)}\n',
    flush: true,
  );
  stdout.writeln(
    'Built ${catalogueStyles.length} emoji packs at catalogue revision $revision.',
  );
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw FormatException('$label must be an object');
}

ArchiveFile _archiveFile(String path, List<int> bytes) =>
    ArchiveFile(path, bytes.length, bytes)
      ..creationTime = 0
      ..lastModTime = 0;

int _requiredInt(Map<String, Object?> value, String key) {
  final found = value[key];
  if (found is int) return found;
  throw FormatException('$key must be an integer');
}

String _requiredText(Map<String, Object?> value, String key) {
  final found = value[key];
  if (found is String && found.trim().isNotEmpty) return found.trim();
  throw FormatException('$key must be non-empty text');
}

void _validateWebp(Uint8List bytes, String label) {
  if (bytes.length < 30 || bytes.length > _maxImageBytes) {
    throw FormatException('$label has an invalid byte size');
  }
  String readAscii(int start, int count) =>
      ascii.decode(bytes.sublist(start, start + count));
  if (readAscii(0, 4) != 'RIFF' || readAscii(8, 4) != 'WEBP') {
    throw FormatException('$label is not WebP');
  }
  final chunk = readAscii(12, 4);
  int width;
  int height;
  if (chunk == 'VP8X') {
    width = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
    height = 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16);
  } else if (chunk == 'VP8L' && bytes.length >= 25) {
    final bits =
        bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    width = (bits & 0x3fff) + 1;
    height = ((bits >> 14) & 0x3fff) + 1;
  } else {
    throw FormatException('$label uses unsupported WebP chunk $chunk');
  }
  if (width <= 0 ||
      height <= 0 ||
      width > _maxImageEdge ||
      height > _maxImageEdge ||
      width != height) {
    throw FormatException(
      '$label must be square and at most $_maxImageEdge px; found ${width}x$height',
    );
  }
}
