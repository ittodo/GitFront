import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const _unset = Object();

enum SettingsBuildMode { debug, profile, release }

SettingsBuildMode get currentSettingsBuildMode {
  if (kReleaseMode) return SettingsBuildMode.release;
  if (kProfileMode) return SettingsBuildMode.profile;
  return SettingsBuildMode.debug;
}

class SettingsPathLayout {
  const SettingsPathLayout._();

  static String settingsFile(
    String documentsDirectory,
    SettingsBuildMode buildMode,
  ) {
    final root = path.join(documentsDirectory, 'GitFront');
    final directory = buildMode == SettingsBuildMode.release
        ? root
        : path.join(root, 'develop');
    return path.join(directory, 'settings.json');
  }
}

class AppSettings {
  const AppSettings({
    this.schemaVersion = currentSchemaVersion,
    this.openRepositories = const [],
    this.activeRepository,
    this.language = 'system',
    this.darkMode,
    this.recentRepositories = const [],
    this.leftPanelWidth = 250,
    this.detailPanelWidth = 560,
    this.detailPanelVisible = true,
    this.externalEditor = 'vsCode',
    this.customEditorExecutable = '',
    this.lastUpdateCheck = 0,
    this.commitDrafts = const {},
    this.historyCacheLimitMb = 512,
  });

  static const currentSchemaVersion = 3;

  final int schemaVersion;
  final List<String> openRepositories;
  final String? activeRepository;
  final String language;
  final bool? darkMode;
  final List<String> recentRepositories;
  final double leftPanelWidth;
  final double detailPanelWidth;
  final bool detailPanelVisible;
  final String externalEditor;
  final String customEditorExecutable;
  final int lastUpdateCheck;
  final Map<String, String> commitDrafts;
  final int historyCacheLimitMb;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      schemaVersion: _integer(json['schemaVersion']) ?? currentSchemaVersion,
      openRepositories: _stringList(json['openRepositories']),
      activeRepository: _string(json['activeRepository']),
      language: _string(json['language']) ?? 'system',
      darkMode: json['darkMode'] is bool ? json['darkMode'] as bool : null,
      recentRepositories: _stringList(json['recentRepositories']),
      leftPanelWidth: _width(json['leftPanelWidth'], 250, 100, 1600),
      detailPanelWidth: _width(json['detailPanelWidth'], 560, 160, 2400),
      detailPanelVisible: json['detailPanelVisible'] is bool
          ? json['detailPanelVisible'] as bool
          : true,
      externalEditor: _string(json['externalEditor']) ?? 'vsCode',
      customEditorExecutable: _string(json['customEditorExecutable']) ?? '',
      lastUpdateCheck: (_integer(json['lastUpdateCheck']) ?? 0)
          .clamp(0, 0x7fffffffffffffff)
          .toInt(),
      commitDrafts: _stringMap(json['commitDrafts']),
      historyCacheLimitMb: (_integer(json['historyCacheLimitMb']) ?? 512)
          .clamp(64, 4096)
          .toInt(),
    );
  }

  factory AppSettings.fromLegacyJson(Map<String, Object?> json) {
    final normalized = <String, Object?>{};
    for (final entry in json.entries) {
      final key = entry.key.startsWith('flutter.')
          ? entry.key.substring('flutter.'.length)
          : entry.key;
      normalized[key] = entry.value;
    }
    return AppSettings.fromJson(normalized);
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'openRepositories': openRepositories,
    'activeRepository': activeRepository,
    'language': language,
    'darkMode': darkMode,
    'recentRepositories': recentRepositories,
    'leftPanelWidth': leftPanelWidth,
    'detailPanelWidth': detailPanelWidth,
    'detailPanelVisible': detailPanelVisible,
    'externalEditor': externalEditor,
    'customEditorExecutable': customEditorExecutable,
    'lastUpdateCheck': lastUpdateCheck,
    'commitDrafts': commitDrafts,
    'historyCacheLimitMb': historyCacheLimitMb,
  };

  AppSettings copyWith({
    List<String>? openRepositories,
    Object? activeRepository = _unset,
    String? language,
    Object? darkMode = _unset,
    List<String>? recentRepositories,
    double? leftPanelWidth,
    double? detailPanelWidth,
    bool? detailPanelVisible,
    String? externalEditor,
    String? customEditorExecutable,
    int? lastUpdateCheck,
    Map<String, String>? commitDrafts,
    int? historyCacheLimitMb,
  }) {
    return AppSettings(
      schemaVersion: schemaVersion,
      openRepositories: openRepositories ?? this.openRepositories,
      activeRepository: identical(activeRepository, _unset)
          ? this.activeRepository
          : activeRepository as String?,
      language: language ?? this.language,
      darkMode: identical(darkMode, _unset) ? this.darkMode : darkMode as bool?,
      recentRepositories: recentRepositories ?? this.recentRepositories,
      leftPanelWidth: leftPanelWidth ?? this.leftPanelWidth,
      detailPanelWidth: detailPanelWidth ?? this.detailPanelWidth,
      detailPanelVisible: detailPanelVisible ?? this.detailPanelVisible,
      externalEditor: externalEditor ?? this.externalEditor,
      customEditorExecutable:
          customEditorExecutable ?? this.customEditorExecutable,
      lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
      commitDrafts: commitDrafts ?? this.commitDrafts,
      historyCacheLimitMb: historyCacheLimitMb ?? this.historyCacheLimitMb,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        schemaVersion == other.schemaVersion &&
        listEquals(openRepositories, other.openRepositories) &&
        activeRepository == other.activeRepository &&
        language == other.language &&
        darkMode == other.darkMode &&
        listEquals(recentRepositories, other.recentRepositories) &&
        leftPanelWidth == other.leftPanelWidth &&
        detailPanelWidth == other.detailPanelWidth &&
        detailPanelVisible == other.detailPanelVisible &&
        externalEditor == other.externalEditor &&
        customEditorExecutable == other.customEditorExecutable &&
        lastUpdateCheck == other.lastUpdateCheck &&
        mapEquals(commitDrafts, other.commitDrafts) &&
        historyCacheLimitMb == other.historyCacheLimitMb;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    Object.hashAll(openRepositories),
    activeRepository,
    language,
    darkMode,
    Object.hashAll(recentRepositories),
    leftPanelWidth,
    detailPanelWidth,
    detailPanelVisible,
    externalEditor,
    customEditorExecutable,
    lastUpdateCheck,
    Object.hashAllUnordered(commitDrafts.entries),
    historyCacheLimitMb,
  );
}

abstract interface class SettingsStore {
  Future<String> get filePath;

  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

typedef DirectoryPathProvider = Future<String> Function();
typedef OptionalFilePathProvider = Future<String?> Function();

class JsonSettingsStore implements SettingsStore {
  JsonSettingsStore({
    required this.buildMode,
    required DirectoryPathProvider documentsDirectory,
    required OptionalFilePathProvider legacySettingsFile,
  }) : _documentsDirectory = documentsDirectory,
       _legacySettingsFile = legacySettingsFile;

  factory JsonSettingsStore.system() {
    return JsonSettingsStore(
      buildMode: currentSettingsBuildMode,
      documentsDirectory: () async =>
          (await getApplicationDocumentsDirectory()).path,
      legacySettingsFile: () async {
        final roamingAppData = Platform.environment['APPDATA'];
        if (roamingAppData == null || roamingAppData.isEmpty) return null;
        return path.join(
          roamingAppData,
          'dev.gitfront',
          'gitfront_preview',
          'shared_preferences.json',
        );
      },
    );
  }

  final SettingsBuildMode buildMode;
  final DirectoryPathProvider _documentsDirectory;
  final OptionalFilePathProvider _legacySettingsFile;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<String> get filePath async =>
      SettingsPathLayout.settingsFile(await _documentsDirectory(), buildMode);

  @override
  Future<AppSettings> load() async {
    try {
      return await _load();
    } on Object catch (error) {
      debugPrint('Unable to initialize GitFront settings: $error');
      return const AppSettings();
    }
  }

  Future<AppSettings> _load() async {
    final target = File(await filePath);
    final backup = File('${target.path}.bak');

    if (await target.exists()) {
      try {
        final settings = await _read(target);
        return await _importDevelopmentSettings(target, settings);
      } on Object catch (error) {
        debugPrint('Unable to read GitFront settings: $error');
        return await _recoverBackup(target, backup) ?? const AppSettings();
      }
    }

    final recovered = await _recoverBackup(target, backup);
    if (recovered != null) return recovered;

    if (buildMode == SettingsBuildMode.release) {
      return await _migrateLegacy(target) ?? const AppSettings();
    }
    return const AppSettings();
  }

  Future<AppSettings> _importDevelopmentSettings(
    File target,
    AppSettings current,
  ) async {
    if (buildMode != SettingsBuildMode.release ||
        current.openRepositories.isNotEmpty ||
        current.recentRepositories.isNotEmpty ||
        current.activeRepository != null ||
        current.commitDrafts.isNotEmpty) {
      return current;
    }
    final development = File(
      path.join(target.parent.path, 'develop', 'settings.json'),
    );
    if (!await development.exists()) return current;
    try {
      final candidate = await _read(development);
      if (candidate.openRepositories.isEmpty &&
          candidate.recentRepositories.isEmpty &&
          candidate.commitDrafts.isEmpty) {
        return current;
      }
      final imported = candidate.copyWith(
        lastUpdateCheck: current.lastUpdateCheck,
      );
      await _writeValidated(imported);
      return await _read(target);
    } on Object catch (error) {
      debugPrint('Unable to import GitFront development settings: $error');
      return current;
    }
  }

  @override
  Future<void> save(AppSettings settings) {
    final write = _writeQueue.then((_) => _writeValidated(settings));
    _writeQueue = write.then<void>((_) {}, onError: (_, _) {});
    return write;
  }

  Future<AppSettings?> _migrateLegacy(File target) async {
    final legacyPath = await _legacySettingsFile();
    if (legacyPath == null) return null;
    final legacy = File(legacyPath);
    if (!await legacy.exists()) return null;

    try {
      final decoded = jsonDecode(await legacy.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Legacy settings root must be an object.');
      }
      final migrated = AppSettings.fromLegacyJson(decoded);
      await save(migrated);
      final verified = await _read(target);
      if (verified != migrated) {
        throw const FormatException('Migrated settings verification failed.');
      }
      await legacy.delete();
      return verified;
    } on Object catch (error) {
      debugPrint('Unable to migrate GitFront settings: $error');
      return null;
    }
  }

  Future<AppSettings?> _recoverBackup(File target, File backup) async {
    if (!await backup.exists()) return null;
    try {
      final recovered = await _read(backup);
      await target.parent.create(recursive: true);
      if (await target.exists()) await target.delete();
      await backup.copy(target.path);
      return recovered;
    } on Object catch (error) {
      debugPrint('Unable to recover GitFront settings backup: $error');
      return null;
    }
  }

  Future<AppSettings> _read(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Settings root must be an object.');
    }
    return AppSettings.fromJson(decoded);
  }

  Future<void> _writeValidated(AppSettings settings) async {
    final target = File(await filePath);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await target.parent.create(recursive: true);

    try {
      final contents = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());
      await temporary.writeAsString('$contents\n', flush: true);
      if (await _read(temporary) != settings) {
        throw const FormatException('Staged settings verification failed.');
      }

      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      try {
        await temporary.rename(target.path);
      } on Object {
        if (!await target.exists() && await backup.exists()) {
          await backup.copy(target.path);
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

String? _string(Object? value) => value is String ? value : null;

int? _integer(Object? value) => value is num ? value.toInt() : null;

List<String> _stringList(Object? value) => value is List<Object?>
    ? value.whereType<String>().toList(growable: false)
    : const [];

Map<String, String> _stringMap(Object? value) {
  if (value is! Map<String, Object?>) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is String) entry.key: entry.value! as String,
  };
}

double _width(Object? value, double fallback, double minimum, double maximum) {
  if (value is! num) return fallback;
  final width = value.toDouble();
  if (!width.isFinite) return fallback;
  return width.clamp(minimum, maximum).toDouble();
}
