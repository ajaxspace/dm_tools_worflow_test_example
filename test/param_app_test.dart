import 'dart:io';
import 'package:test/test.dart';

/// CLI contract for the Params Drill probe (`bin/param_app.dart`).
///
/// The drill lane (`ci-params.yml`) dispatches
/// `dart run bin/param_app.dart "<mode>"` — every dispatched mode must
/// produce a summary line and exit 0. A non-zero exit marks the whole
/// probe job red (gh-31: mode=bad had no data path and threw; gh-33:
/// ANY mode without a revisions entry threw, despite the lane contract
/// "bad = fail, anything else = ok").
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
      expect(result.stdout, contains('smoke bad: 0 revisions'),
          reason: 'pin the exact healed summary line, as good/green do');
      expect(result.stderr, isEmpty);
    });

    test('mode=smoke (no data entry) summarizes and exits 0 (gh-33 regression)',
        () async {
      final result = await runProbe('smoke');
      expect(result.exitCode, 0,
          reason: 'the lane contract is "anything else = ok"; a throw '
              'fails the probe with the gh-33 exit-255 signature');
      expect(result.stdout, contains('smoke smoke: 0 revisions'));
      expect(result.stderr, isEmpty);
    });

    test('mode=chaos (no data entry) summarizes and exits 0 (gh-33 regression)',
        () async {
      final result = await runProbe('chaos');
      expect(result.exitCode, 0,
          reason: 'a second unknown mode proves the fallback is '
              'mode-independent, not a special case for one string');
      expect(result.stdout, contains('smoke chaos: 0 revisions'));
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
