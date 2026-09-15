import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitfront_preview/settings_store.dart';
import 'package:path/path.dart' as path;

Future<Directory> temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'gitfront-settings-test-',
  );
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return directory;
}

JsonSettingsStore storeFor({
  required String documents,
  required SettingsBuildMode buildMode,
  String? legacyFile,
}) {
  return JsonSettingsStore(
    buildMode: buildMode,
    documentsDirectory: () async => documents,
    legacySettingsFile: () async => legacyFile,
  );
}

void main() {
  group('settings paths', () {
    const documents = r'C:\Users\tester\OneDrive\Documents';

    test('release uses the GitFront documents root', () {
      expect(
        SettingsPathLayout.settingsFile(documents, SettingsBuildMode.release),
        path.join(documents, 'GitFront', 'settings.json'),
      );
    });

    test('debug and profile use the develop directory', () {
      for (final mode in [SettingsBuildMode.debug, SettingsBuildMode.profile]) {
        expect(
          SettingsPathLayout.settingsFile(documents, mode),
          path.join(documents, 'GitFront', 'develop', 'settings.json'),
        );
      }
    });
  });

  test('round trips every setting', () async {
    final directory = await temporaryDirectory();
    final store = storeFor(
      documents: directory.path,
      buildMode: SettingsBuildMode.debug,
    );
    const expected = AppSettings(
      openRepositories: [r'D:\repos\one', r'D:\repos\two'],
      activeRepository: r'D:\repos\two',
      language: 'korean',
      darkMode: true,
      recentRepositories: [r'D:\repos\two', r'D:\repos\one'],
      leftPanelWidth: 312,
      detailPanelWidth: 684,
      detailPanelVisible: false,
      externalEditor: 'custom',
      customEditorExecutable: r'C:\Tools\editor.exe',
      lastUpdateCheck: 123456789,
      commitDrafts: {r'd:\repos\two': 'subject\n\nbody'},
      historyCacheLimitMb: 1024,
    );

    await store.save(expected);

    expect(await store.load(), expected);
    expect(await File(await store.filePath).exists(), isTrue);
  });

  test('uses safe defaults for missing and invalid values', () async {
    final directory = await temporaryDirectory();
    final store = storeFor(
      documents: directory.path,
      buildMode: SettingsBuildMode.debug,
    );
    final target = File(await store.filePath);
    await target.parent.create(recursive: true);
    await target.writeAsString(
      jsonEncode({
        'openRepositories': [r'D:\repos\valid', 42],
        'language': 7,
        'darkMode': 'dark',
        'leftPanelWidth': 'wide',
        'detailPanelWidth': <Object?>[],
        'detailPanelVisible': 'yes',
        'lastUpdateCheck': -20,
      }),
    );

    final settings = await store.load();

    expect(settings.openRepositories, [r'D:\repos\valid']);
    expect(settings.language, 'system');
    expect(settings.darkMode, isNull);
    expect(settings.leftPanelWidth, 250);
    expect(settings.detailPanelWidth, 560);
    expect(settings.detailPanelVisible, isTrue);
    expect(settings.lastUpdateCheck, 0);
    expect(settings.historyCacheLimitMb, 512);
  });

  test('recovers a corrupt settings file from its backup', () async {
    final directory = await temporaryDirectory();
    final store = storeFor(
      documents: directory.path,
      buildMode: SettingsBuildMode.debug,
    );
    const previous = AppSettings(language: 'korean');
    const latest = AppSettings(language: 'english');
    await store.save(previous);
    await store.save(latest);
    final target = File(await store.filePath);
    await target.writeAsString('{not valid json');

    expect(await store.load(), previous);
    expect(
      AppSettings.fromJson(
        (jsonDecode(await target.readAsString()) as Map)
            .cast<String, Object?>(),
      ),
      previous,
    );
  });

  test(
    'serializes overlapping writes and preserves the latest value',
    () async {
      final directory = await temporaryDirectory();
      final store = storeFor(
        documents: directory.path,
        buildMode: SettingsBuildMode.debug,
      );

      await Future.wait([
        store.save(const AppSettings(language: 'system')),
        store.save(const AppSettings(language: 'korean')),
        store.save(const AppSettings(language: 'english')),
      ]);

      expect((await store.load()).language, 'english');
    },
  );

  test('release migrates and removes verified legacy settings', () async {
    final directory = await temporaryDirectory();
    final legacy = File(path.join(directory.path, 'legacy.json'));
    await legacy.writeAsString(
      jsonEncode({
        'flutter.openRepositories': [r'D:\repos\one'],
        'flutter.activeRepository': r'D:\repos\one',
        'flutter.language': 'korean',
        'flutter.darkMode': true,
        'flutter.leftPanelWidth': 330.0,
        'flutter.externalEditor': 'systemDefault',
        'flutter.lastUpdateCheck': 9000,
      }),
    );
    final store = storeFor(
      documents: path.join(directory.path, 'Documents'),
      buildMode: SettingsBuildMode.release,
      legacyFile: legacy.path,
    );

    final settings = await store.load();

    expect(settings.openRepositories, [r'D:\repos\one']);
    expect(settings.activeRepository, r'D:\repos\one');
    expect(settings.language, 'korean');
    expect(settings.darkMode, isTrue);
    expect(settings.leftPanelWidth, 330);
    expect(settings.externalEditor, 'systemDefault');
    expect(settings.lastUpdateCheck, 9000);
    expect(await File(await store.filePath).exists(), isTrue);
    expect(await legacy.exists(), isFalse);
  });

  test('development builds do not consume legacy release settings', () async {
    final directory = await temporaryDirectory();
    final legacy = File(path.join(directory.path, 'legacy.json'));
    await legacy.writeAsString(jsonEncode({'flutter.language': 'korean'}));
    final store = storeFor(
      documents: path.join(directory.path, 'Documents'),
      buildMode: SettingsBuildMode.debug,
      legacyFile: legacy.path,
    );

    expect(await store.load(), const AppSettings());
    expect(await legacy.exists(), isTrue);
    expect(await File(await store.filePath).exists(), isFalse);
  });

  test('an empty release profile imports development settings once', () async {
    final directory = await temporaryDirectory();
    final documents = path.join(directory.path, 'Documents');
    final development = storeFor(
      documents: documents,
      buildMode: SettingsBuildMode.debug,
    );
    await development.save(
      const AppSettings(
        openRepositories: [r'D:\repos\large'],
        activeRepository: r'D:\repos\large',
        recentRepositories: [r'D:\repos\large'],
        language: 'korean',
      ),
    );
    final release = storeFor(
      documents: documents,
      buildMode: SettingsBuildMode.release,
    );
    await release.save(const AppSettings(lastUpdateCheck: 1234));

    final imported = await release.load();

    expect(imported.openRepositories, [r'D:\repos\large']);
    expect(imported.activeRepository, r'D:\repos\large');
    expect(imported.language, 'korean');
    expect(imported.lastUpdateCheck, 1234);
    expect(await File(await development.filePath).exists(), isTrue);

    await release.save(imported.copyWith(language: 'english'));
    expect((await release.load()).language, 'english');
  });

  test(
    'an existing new settings file wins without deleting legacy data',
    () async {
      final directory = await temporaryDirectory();
      final legacy = File(path.join(directory.path, 'legacy.json'));
      await legacy.writeAsString(jsonEncode({'flutter.language': 'korean'}));
      final store = storeFor(
        documents: path.join(directory.path, 'Documents'),
        buildMode: SettingsBuildMode.release,
        legacyFile: legacy.path,
      );
      await store.save(const AppSettings(language: 'english'));

      expect((await store.load()).language, 'english');
      expect(await legacy.exists(), isTrue);
    },
  );

  test('failed migration preserves the legacy file', () async {
    final directory = await temporaryDirectory();
    final blockedDocuments = File(path.join(directory.path, 'blocked'));
    await blockedDocuments.writeAsString('not a directory');
    final legacy = File(path.join(directory.path, 'legacy.json'));
    await legacy.writeAsString(jsonEncode({'flutter.language': 'korean'}));
    final store = storeFor(
      documents: blockedDocuments.path,
      buildMode: SettingsBuildMode.release,
      legacyFile: legacy.path,
    );

    expect(await store.load(), const AppSettings());
    expect(await legacy.exists(), isTrue);
  });
}
