import 'dart:io';
import 'package:test/test.dart';

/// Geo Probe lane region-resolution contract (gh-68 regression).
///
/// ci-geo.yml triggered on BOTH `push` (main) and `workflow_dispatch`, but
/// `region` is a workflow_dispatch-only input: on push runs
/// `${{ inputs.region }}` interpolates EMPTY, so the guard checked
/// `regions/.conf` and every run died with
/// "region config missing: regions/.conf" (9/9 red, zero greens in the
/// incident window). The repo also shipped no `regions/` directory at all,
/// so even a dispatched region=eu failed on `regions/eu.conf` missing.
///
/// The contract, mirrored from the healed `ci-params.yml` lane style:
///   1. the probe step maps the region through a NON-EMPTY env default —
///      push runs and default dispatches must probe the default region;
///   2. the probe SCRIPT never interpolates `inputs.region` directly
///      (empty on push = the gh-68 collapse; free-typed dispatch input
///      spliced into bash is also a script-injection vector);
///   3. the env fallback must equal the workflow_dispatch input default —
///      one default region, kept in sync;
///   4. the default region's config file exists on the committed tree, and
///      the extracted probe logic is green for it / red for a region
///      without a conf.

const geoPath = '.github/workflows/ci-geo.yml';
const defaultRegion = 'eu';

/// The YAML slice from the step named [stepName] until the next step
/// (or end of file).
String stepSlice(String yaml, String stepName) {
  var start = yaml.indexOf("name: '$stepName'");
  if (start < 0) start = yaml.indexOf('name: $stepName');
  if (start < 0) return '';
  final rest = yaml.substring(start + 1);
  final next = RegExp(r'\n *- name:').firstMatch(rest);
  return next == null
      ? yaml.substring(start)
      : yaml.substring(start, start + 1 + next.start);
}

/// The `run: |` block of a step slice, dedented.
String stepRunScript(String slice) {
  final lines = slice.split('\n');
  final runAt = lines.indexWhere((l) => l.trim() == 'run: |');
  if (runAt < 0) return '';
  final body = lines.sublist(runAt + 1).takeWhile((l) => l.startsWith(' '));
  final widths = body
      .where((l) => l.trim().isNotEmpty)
      .map((l) => l.indexOf(l.trim()))
      .toList()
    ..sort();
  if (widths.isEmpty) return '';
  final w = widths.first;
  return body.map((l) => l.length >= w ? l.substring(w) : l.trimLeft()).join('\n');
}

void main() {
  final yaml = File(geoPath).readAsStringSync();
  final probeStep = stepSlice(yaml, 'Probe region');
  final script = stepRunScript(probeStep);

  group('Geo Probe region resolution (gh-68)', () {
    test('lane stays a parameterized leg (dispatch region input declared)',
        () {
      expect(yaml, contains('workflow_dispatch:'),
          reason: 'Geo Probe is a LEG_WORKFLOWS lane dispatched per region');
      expect(yaml, contains('region:'),
          reason: 'the region dispatch input must stay declared');
    });

    test('probe step maps the region through a NON-EMPTY env default', () {
      final env = RegExp(
              r"^ *REGION: \$\{\{ inputs\.region \|\| '[A-Za-z0-9_-]+' \}\} *$",
              multiLine: true)
          .firstMatch(probeStep);
      expect(env, isNotNull,
          reason: 'on push runs inputs.region interpolates EMPTY — without '
              'a non-empty fallback the guard checks regions/.conf and dies '
              '(the exact gh-68 signature)');
    });

    test('probe script never interpolates inputs.region directly', () {
      expect(script, isNot(contains('inputs.region')),
          reason: 'raw interpolation is empty on push (gh-68 collapse) and '
              'splices free-typed dispatch input straight into bash');
    });

    test('probe script guards and reports via the resolved REGION', () {
      expect(script, contains(r'regions/${REGION}.conf'),
          reason: 'the guard path must use the env-resolved region');
      expect(script, contains('probing region: '),
          reason: 'the lane log must name the region it probed');
    });

    test('env fallback equals the workflow_dispatch default (one default)',
        () {
      final dispatchDefault =
          RegExp(r"default: '([A-Za-z0-9_-]+)'").firstMatch(yaml)?.group(1);
      final envFallback = RegExp(
              r"REGION: \$\{\{ inputs\.region \|\| '([A-Za-z0-9_-]+)' \}\}")
          .firstMatch(probeStep)
          ?.group(1);
      expect(dispatchDefault, isNotNull,
          reason: 'the dispatch input must keep an explicit default');
      expect(envFallback, isNotNull,
          reason: 'the probe env must keep an explicit fallback');
      expect(envFallback, dispatchDefault,
          reason: 'two independent defaults drift — the fallback must be '
              'the dispatch default');
    });

    test('default region config is committed (regions/<default>.conf)', () {
      final conf = File('regions/$defaultRegion.conf');
      expect(conf.existsSync(), isTrue,
          reason: 'even a dispatched region=$defaultRegion failed on '
              'regions/$defaultRegion.conf missing — the default region '
              'must ship its config');
      expect(conf.readAsStringSync().trim(), isNotEmpty,
          reason: 'a placeholder-empty conf hides whether the lane really '
              'has a config');
    });

    test('extracted probe logic exits 0 for the default region', () async {
      final result = await Process.run('bash', ['-c', script],
          environment: {'REGION': defaultRegion},
          workingDirectory: Directory.current.path);
      expect(result.exitCode, 0,
          reason: 'the committed tree must satisfy the lane guard for the '
              'default region');
      expect(result.stdout, contains('probing region: $defaultRegion'));
      expect(result.stderr, isEmpty);
    });

    test('probe logic still rejects a region with no conf (exit 1)', () async {
      final result = await Process.run('bash', ['-c', script],
          environment: {'REGION': 'zz'},
          workingDirectory: Directory.current.path);
      expect(result.exitCode, 1,
          reason: 'the config-existence guard is the lane contract — an '
              'unshipped region must fail loudly, not probe blindly');
      expect(result.stderr,
          contains('region config missing: regions/zz.conf'));
    });
  });
}
