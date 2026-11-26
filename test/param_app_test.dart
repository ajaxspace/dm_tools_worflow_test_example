import 'dart:io';
import 'package:test/test.dart';

/// CLI contract for the Params Drill probe (`bin/param_app.dart`).
///
/// The drill lane (`ci-params.yml`) dispatches
/// `dart run bin/param_app.dart "<mode>"` — every dispatched mode must
/// produce a summary line and exit 0. A non-zero exit marks the whole
/// probe job red (gh-31: mode=bad had no data path and threw).
void main() {
  Future<ProcessResult> runProbe(String mode) => Process.run(
        'dart',
        ['run', 'bin/param_app.dart', mode],
      );

  group('params probe CLI (every drill mode exits 0)', () {
    test('mode=bad prints a summary and exits 0 (gh-31 regression)', () async {
      final result = await runProbe('bad');
      expect(result.exitCode, 0,
          reason: 'the drill dispatches mode=bad; a throw fails the probe');
      expect(result.stdout, contains('smoke bad:'));
      expect(result.stderr, isEmpty);
    });

    test('mode=good keeps its summary and exits 0', () async {
      final result = await runProbe('good');
      expect(result.exitCode, 0);
      expect(result.stdout, contains('smoke good: 12 revisions'));
    });

    test('mode=green keeps its summary and exits 0', () async {
      final result = await runProbe('green');
      expect(result.exitCode, 0);
      expect(result.stdout, contains('smoke green: 7 revisions'));
    });
  });
}
