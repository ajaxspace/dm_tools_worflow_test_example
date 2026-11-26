import 'dart:io';
import 'package:test/test.dart';

/// Shared-prep contract for the CI lanes (gh-41 regression).
///
/// PR #40 ("prep: simplify stamp write") introduced
/// `tool/prepare.sh` — the "Toolchain stamp (shared prep)" step. The script
/// shells out to `dart` and redirects into `.dart_tool/toolchain.txt`, but
/// on a fresh checkout NEITHER precondition holds before the lane's later
/// steps run: the Dart SDK is only installed by `dart-lang/setup-dart@v1`,
/// and the `.dart_tool/` directory is only created by `dart pub get`.
/// Both lanes ran the stamp FIRST, so every run died in the prep step
/// (gh-41: exit 127 `dart: command not found`, then exit 1
/// `.dart_tool/toolchain.txt: No such file or directory` once the older
/// failure mode was read as the cause).
///
/// The contract, mirrored from the healthy `ci-params.yml` lane:
///   1. every lane that stamps installs the Dart SDK BEFORE the stamp step;
///   2. the script creates `.dart_tool/` itself and works on a fresh
///      checkout (no `.dart_tool/`, `dart pub get` not run yet);
///   3. the script is idempotent (re-runs must stay green).

/// Lanes that run the shared prep stamp. `ci.yml` is the PR validation
/// lane (dispatched on PR heads as required check `test`), `ci-extra.yml`
/// runs on pushes to main — leaving either broken blocks the other's fixes.
const ciLanes = [
  '.github/workflows/ci.yml',
  '.github/workflows/ci-extra.yml',
];

final prepScriptPath = 'tool/prepare.sh';

void main() {
  group('CI lane step order (gh-41: stamp ran before setup-dart)', () {
    for (final lane in ciLanes) {
      test('$lane installs Dart before the shared prep stamp', () {
        final yaml = File(lane).readAsStringSync();
        final setupDart = yaml.indexOf('uses: dart-lang/setup-dart@v1');
        final prep = yaml.indexOf('run: bash tool/prepare.sh');
        expect(setupDart, greaterThan(-1),
            reason: '$lane must declare the Dart SDK install step');
        expect(prep, greaterThan(-1),
            reason: '$lane must declare the shared prep stamp step');
        expect(setupDart, lessThan(prep),
            reason: 'the stamp shells out to `dart` — the SDK must be on '
                'PATH first, or the step dies (gh-41 exit 127)');
      });
    }
  });

  group('tool/prepare.sh (shared prep)', () {
    test('creates .dart_tool before redirecting the stamp into it', () {
      final script = File(prepScriptPath).readAsStringSync();
      final mkdir = script.indexOf('mkdir -p .dart_tool');
      final redirect = script.indexOf('.dart_tool/toolchain.txt');
      expect(mkdir, greaterThan(-1),
          reason: 'on a fresh checkout .dart_tool/ does not exist yet '
              '(dart pub get runs later) — the bare redirect fails with '
              'exit 1: No such file or directory (gh-41)');
      expect(redirect, greaterThan(-1));
      expect(mkdir, lessThan(redirect),
          reason: 'bash sets up redirections before running the command, '
              'so the directory must exist before the redirect line');
    });

    test('runs green on a fresh checkout (no .dart_tool, no pub get)',
        () async {
      final sandbox =
          await Directory.systemTemp.createTemp('prep_contract_fresh-');
      try {
        final result = await Process.run(
          'bash',
          [File(prepScriptPath).absolute.path],
          workingDirectory: sandbox.path,
        );
        expect(result.exitCode, 0,
            reason: 'the CI stamp step must survive a fresh checkout');
        final stamp = File('${sandbox.path}/.dart_tool/toolchain.txt');
        expect(stamp.existsSync(), isTrue, reason: 'stamp file must exist');
        expect(stamp.readAsStringSync(), contains('Dart SDK version'),
            reason: 'the stamp records which Dart built the workspace');
        expect(result.stderr, isEmpty);
      } finally {
        sandbox.deleteSync(recursive: true);
      }
    });

    test('is idempotent — a second run in the same workspace stays green',
        () async {
      final sandbox =
          await Directory.systemTemp.createTemp('prep_contract_rerun-');
      try {
        final scriptPath = File(prepScriptPath).absolute.path;
        final first = await Process.run('bash', [scriptPath],
            workingDirectory: sandbox.path);
        expect(first.exitCode, 0);
        final second = await Process.run('bash', [scriptPath],
            workingDirectory: sandbox.path);
        expect(second.exitCode, 0,
            reason: 'mkdir -p and the overwrite must both be re-runnable');
      } finally {
        sandbox.deleteSync(recursive: true);
      }
    });
  });
}
