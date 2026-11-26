import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';

/// CI prep contract for the shared `tool/prepare.sh` stamp step
/// ([ci-heal] gh-43: fresh-checkout toolchain stamp failure).
///
/// The CI lanes (ci.yml, ci-extra.yml) run `bash tool/prepare.sh` as the
/// "Toolchain stamp (shared prep)" step. Two invariants keep that step green
/// on a fresh `actions/checkout` workspace:
///
///   1. The script must create its own `.dart_tool/` output directory —
///      `.dart_tool` is gitignored, so a fresh checkout does NOT contain it.
///   2. The stamp step must run AFTER `dart-lang/setup-dart` — the GitHub
///      runners have no `dart` on PATH until that action installs one.
///
/// Invariant 1 is exercised behaviorally (the script is run in a temp
/// workspace with no `.dart_tool/`); invariant 2 is a textual workflow
/// contract in the style of `run_name_contract_test.dart`.
const prepScriptPath = 'tool/prepare.sh';
const stampStepMarker = 'Toolchain stamp (shared prep)';
const dartInstallMarker = 'uses: dart-lang/setup-dart@v1';
const lanes = [
  '.github/workflows/ci.yml',
  '.github/workflows/ci-extra.yml',
];

void main() {
  group('tool/prepare.sh fresh checkout', () {
    test('creates the missing .dart_tool directory and writes the stamp',
        () async {
      final workspace = await Directory.systemTemp.createTemp('ci_prep_test');
      addTearDown(() => workspace.delete(recursive: true));

      // Fresh checkout shape: the script, NO .dart_tool/ directory, and a
      // stub `dart` on PATH (the runner shape once setup-dart has run).
      await File(prepScriptPath).copy('${workspace.path}/prepare.sh');
      final stubBin = await Directory('${workspace.path}/stubbin').create();
      final stub = File('${stubBin.path}/dart');
      await stub.writeAsString('#!/usr/bin/env bash\n'
          'echo "Dart SDK version: 0.0.0 (stub) (stub) on \\"stub_x64\\""\n');
      await Process.run('chmod', ['+x', stub.path]);

      final result = await Process.run(
        'bash',
        ['prepare.sh'],
        workingDirectory: workspace.path,
        environment: {
          ...Platform.environment,
          'PATH': '${stubBin.path}:${Platform.environment['PATH'] ?? ''}',
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.exitCode, 0,
          reason: 'prepare.sh must succeed in a fresh checkout; '
              'stderr: ${result.stderr}');
      final stamp = File('${workspace.path}/.dart_tool/toolchain.txt');
      expect(stamp.existsSync(), isTrue, reason: 'stamp file must be written');
      expect(stamp.readAsStringSync(), contains('Dart SDK version'));
      expect(result.stdout, contains('prep:'));
    });

    test('is idempotent when .dart_tool already exists (dart pub get ran)',
        () async {
      final workspace = await Directory.systemTemp.createTemp('ci_prep_test');
      addTearDown(() => workspace.delete(recursive: true));

      await File(prepScriptPath).copy('${workspace.path}/prepare.sh');
      await Directory('${workspace.path}/.dart_tool').create();
      final stubBin = await Directory('${workspace.path}/stubbin').create();
      final stub = File('${stubBin.path}/dart');
      await stub.writeAsString('#!/usr/bin/env bash\n'
          'echo "Dart SDK version: 0.0.0 (stub) (stub) on \\"stub_x64\\""\n');
      await Process.run('chmod', ['+x', stub.path]);

      final result = await Process.run(
        'bash',
        ['prepare.sh'],
        workingDirectory: workspace.path,
        environment: {
          ...Platform.environment,
          'PATH': '${stubBin.path}:${Platform.environment['PATH'] ?? ''}',
        },
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.exitCode, 0,
          reason: 'prepare.sh must succeed when .dart_tool already exists');
    });
  });

  group('CI lane step order contract', () {
    for (final lane in lanes) {
      test('$lane stamps the toolchain AFTER installing the Dart SDK', () {
        final lines = File(lane).readAsLinesSync();
        final stampStep = lines.indexWhere((l) => l.contains(stampStepMarker));
        final dartInstall = lines.indexWhere((l) => l.contains(dartInstallMarker));

        expect(stampStep, isNonNegative,
            reason: '$lane must run the shared prep stamp step');
        expect(dartInstall, isNonNegative,
            reason: '$lane must install the Dart SDK');
        expect(stampStep, greaterThan(dartInstall),
            reason: 'the stamp step shells out to `dart`, which is only on '
                'PATH after dart-lang/setup-dart has run');
      });
    }
  });
}
