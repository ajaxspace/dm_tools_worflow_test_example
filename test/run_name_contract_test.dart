import 'dart:io';
import 'package:test/test.dart';

/// Run-name contract for the parameterized factory-owned workflows
/// ([ci-heal] self-heal observability).
///
/// The self-heal legs-health detector groups runs by the FIRST token of the
/// run-name (`displayTitle | split(" ")[0]`), so for a parameterized
/// workflow the run-name must OPEN with the stable group key
/// (`gh-<issue>` / `pr-<pr>`) and must not carry run-varying values.
/// The tests mirror the two consumers of the run-name in
/// `.github/workflows/ci-heal.yml`:
///   * the "Run-name contract scan" step (first quoted literal heuristic), and
///   * the "Legs health" step (grouping by the first space-delimited token),
/// plus the dedupe gate regex in `ai-teammate.yml` itself.
const workflowPath = '.github/workflows/ai-teammate.yml';

/// The run-name scalar: an inline value, or a folded (`>-`) block unfolded
/// the way YAML folds (continuation lines joined with single spaces).
String runNameValue(String yaml) {
  final lines = yaml.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('run-name:'));
  if (start < 0) return '';
  final inline = lines[start].substring('run-name:'.length).trim();
  final block = lines
      .sublist(start + 1)
      .takeWhile((l) => l.trim().isEmpty || l.startsWith(' '))
      .map((l) => l.trim())
      .toList();
  if (!RegExp(r'^[>|][-+\d]*$').hasMatch(inline)) return inline;
  return block.join(' ');
}

/// Replicates ci-heal's scan acceptance: the first quoted literal holding a
/// `{` placeholder, cut at the first `{`/`$`, whitespace-stripped. Empty =
/// no group template at all ("group hidden"); otherwise the prefix must be
/// a short stable tag (gh-, pr-, param-, geo-).
String scanGroupPrefix(String runName) {
  for (final match in RegExp("'[^']*'").allMatches(runName)) {
    final literal = match.group(0)!.replaceAll("'", '');
    if (!literal.contains('{')) continue;
    final cut = literal.indexOf(RegExp(r'[{$]'));
    return literal.substring(0, cut < 0 ? literal.length : cut)
        .replaceAll(RegExp(r'\s'), '');
  }
  return '';
}

/// The LEG_WORKFLOWS leg lanes declared in ci-heal.yml (the scan's input):
/// the block-scalar lines indented under the key. Comment lines at the
/// key's own indent are YAML structure, not legs. The block scalar may use
/// the clip (`|`) or the strip (`|-`) chomping indicator — ci-heal.yml
/// requires `|-` (gh-77): a trailing newline makes `done <<< "$LEG_WORKFLOWS"`
/// iterate one extra empty lane.
List<String> legWorkflows() {
  final yaml = File('.github/workflows/ci-heal.yml').readAsStringSync();
  final block = RegExp(r'LEG_WORKFLOWS: \|-?\n((?: {4,}\S.*\n)+)')
      .firstMatch(yaml)
      ?.group(1);
  if (block == null) return [];
  return block
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
}

/// Workflow file declaring `name: <wfName>` — ci-heal resolves legs to
/// files the same way (first `name:` match under .github/workflows).
String? workflowFileFor(String wfName) {
  final nameRe = RegExp(
      "^name: ['\"]?" + RegExp.escape(wfName) + "['\"]?\\s*\$",
      multiLine: true);
  for (final entity in Directory('.github/workflows').listSync()) {
    if (entity is File && nameRe.hasMatch(entity.readAsStringSync())) {
      return entity.path;
    }
  }
  return null;
}

/// Replicates ci-heal's "group hidden" heuristic: the first quoted literal,
/// cut at the first `{`, whitespace-stripped. Non-empty = a literal prefix
/// hides the group token.
String scannerPrefix(String runName) {
  final firstQuoted = RegExp("'[^']*'").firstMatch(runName)?.group(0);
  if (firstQuoted == null) return '';
  final literal = firstQuoted.replaceAll("'", '');
  final brace = literal.indexOf('{');
  return (brace < 0 ? literal : literal.substring(0, brace))
      .replaceAll(RegExp(r'\s'), '');
}

void main() {
  final yaml = File(workflowPath).readAsStringSync();
  final runName = runNameValue(yaml);

  group('run-name contract (ci-heal observability)', () {
    test('parameterized workflow declares a run-name', () {
      expect(yaml, contains('issues:'),
          reason: 'the issues trigger makes the workflow parameterized');
      expect(yaml, contains('inputs:'),
          reason: 'workflow_dispatch inputs make the workflow parameterized');
      expect(runName, isNotEmpty);
    });

    test('run-name carries no run-varying values', () {
      final noise = RegExp(r'run_id|run_number|timestamp|head_sha');
      expect(noise.allMatches(runName), isEmpty);
    });

    test('ci-heal scan: no literal prefix before the leading expression', () {
      expect(scannerPrefix(runName), isEmpty,
          reason: 'ci-heal flags "parameterized, first run-name token is '
              'literal ..." — the group key must be resolved by the leading '
              'expression itself, not prefixed by a literal');
    });

    test('leading expression resolves the anchor before any leg marker', () {
      expect(runName.startsWith(r'${'), isTrue,
          reason: 'the value must open with the group-key expression, '
              'not a literal');
      final ghAnchor = runName.indexOf("format('gh-{0}'");
      final prAnchor = runName.indexOf("format('pr-{0}'");
      final dispatchLeg = runName.indexOf("'workflow_dispatch'");
      final emojis = ['▶', '✅', '🔧', '🔍', '⚒']
          .map(runName.indexOf)
          .where((i) => i >= 0);
      expect(ghAnchor, greaterThan(-1), reason: 'gh- anchor token missing');
      expect(prAnchor, greaterThan(-1), reason: 'pr- anchor token missing');
      expect(ghAnchor, lessThan(dispatchLeg),
          reason: 'group key must be produced before the dispatch leg branch');
      for (final e in emojis) {
        expect(ghAnchor, lessThan(e),
            reason: 'group key must lead every leg/emoji literal');
      }
    });
  });

  group('run-name contract: Geo Probe leg (gh-55)', () {
    const geoPath = '.github/workflows/ci-geo.yml';
    final geoYaml = File(geoPath).readAsStringSync();
    final geoRunName = runNameValue(geoYaml);

    test('parameterized lane declares a run-name', () {
      expect(geoYaml, contains('inputs:'),
          reason: 'workflow_dispatch inputs make Geo Probe parameterized '
              '(the ci-heal scan keys on inputs:/issues:)');
      expect(geoRunName, isNotEmpty,
          reason: '"parameterized but NO run-name" is the exact gh-55 '
              'non-conformance the scan flags');
    });

    test('resolved title: first token is the stable geo-<region> group key',
        () {
      // Evaluate the template the way GitHub does for a dispatch
      // (region=eu): the FIRST space-delimited token of the RESOLVED
      // displayTitle is the group key the legs-health detector uses.
      final resolved = geoRunName
          .replaceAll(RegExp(r'\$\{\{\s*inputs\.region\s*\}\}'), 'eu')
          .replaceAll("'", '');
      final firstToken = resolved.trim().split(' ').first;
      expect(firstToken, 'geo-eu',
          reason: 'the group key must resolve BEFORE any leg marker — a '
              'malformed expression (e.g. a dropped `\${{` brace) renders '
              'literally and hides the parameter');
      expect(geoRunName, contains(r'inputs.region'),
          reason: 'the group key must embed the dispatch parameter '
              '(region), not a constant');
    });

    test('run-name carries no run-varying values', () {
      final noise = RegExp(r'run_id|run_number|timestamp|head_sha');
      expect(noise.allMatches(geoRunName), isEmpty);
    });

    test('ci-heal scan: leading group template passes the literal-prefix rule',
        () {
      expect(scanGroupPrefix(geoRunName),
          matches(RegExp(r'^[A-Za-z0-9_-]{1,6}$')),
          reason: 'the scan accepts the first quoted `{`-template whose '
              'literal prefix is a short stable tag (gh-, pr-, param-, geo-)');
    });

    test('legs-health grouping: one group per region, other regions never reset it',
        () {
      String groupKey(String displayTitle) => displayTitle.split(' ').first;
      final titles = [
        'geo-eu — geo probe',
        'geo-eu — geo probe',
        'geo-us — geo probe',
        'geo-ap — geo probe',
      ];
      expect(titles.map(groupKey).toSet(), hasLength(3),
          reason: 'one stable key per region: geo-eu, geo-us, geo-ap');
      expect(titles.where((t) => groupKey(t) == 'geo-eu'), hasLength(2),
          reason: 'both geo-eu runs land in ONE group — interleaved greens of '
              'other regions cannot reset the streak');
    });
  });

  group('ci-heal scan replay: every LEG_WORKFLOWS leg conforms (gh-55)', () {
    // Mirrors the "Run-name contract scan" step of ci-heal.yml: a leg
    // regressing to a missing/hidden group key goes red HERE before the
    // scanner has to file another heal issue.
    final legs = legWorkflows();

    test('ci-heal declares the parameterized legs under contract', () {
      expect(legs, containsAll(['AI Teammate', 'Params Drill', 'Geo Probe']),
          reason: 'the replay must cover the factory-owned leg lanes');
    });

    for (final leg in legs) {
      test('$leg: run-name contract ok', () {
        final file = workflowFileFor(leg);
        expect(file, isNotNull,
            reason: '$leg must map to a workflow file by its name: field');
        final legYaml = File(file!).readAsStringSync();
        final parameterized =
            legYaml.contains('inputs:') || legYaml.contains('issues:');
        if (!parameterized) return; // plain workflows may use the name
        final legRunName = runNameValue(legYaml);
        expect(legRunName, isNotEmpty,
            reason: '$leg is parameterized but has NO run-name — '
                'the exact gh-55 non-conformance');
        final prefix = scanGroupPrefix(legRunName);
        expect(prefix, isNotEmpty,
            reason: '$leg has no quoted `{`-template — group hidden');
        expect(prefix, matches(RegExp(r'^[A-Za-z0-9_-]{1,6}$')),
            reason: '$leg group template prefix must be a short stable tag');
        expect(RegExp(r'run_id|run_number|timestamp|head_sha')
            .allMatches(legRunName), isEmpty,
            reason: '$leg group token must not embed run-varying values');
      });
    }
  });

  group('legs-health grouping (displayTitle split on first space)', () {
    String groupKey(String displayTitle) => displayTitle.split(' ').first;

    test('conforming titles group runs per parameter (2+ runs per group)', () {
      final titles = [
        'gh-23 · ⚒️ dev: Fix the run-name',
        'gh-23 · ⚒️ dev: Follow-up tweak',
        'gh-24 · ⚒️ dev: Unrelated issue',
        'gh-23 · 🔍 review: Re-review',
        'pr-45 · ▶ review (SM)',
      ];
      expect(titles.map(groupKey).toSet(), hasLength(3),
          reason: 'one stable key per parameter: gh-23, gh-24, pr-45');
      expect(titles.where((t) => groupKey(t) == 'gh-23'), hasLength(3));
    });

    test('legacy titles (leg first) collapsed by leg, hiding the parameter',
        () {
      // The regression this contract prevents: every parameter shared one
      // group key, so interleaved greens reset raw streaks.
      final legacy = ['⚒️ dev · gh-23: A', '⚒️ dev · gh-24: B'];
      expect(legacy.map(groupKey).toSet(), hasLength(1));
    });
  });

  group('dedupe-gate compatibility', () {
    test('anchor token matches the gate regex in the leading position', () {
      RegExp gate(String t) => RegExp('(^|[^0-9])' + t + r'([^0-9]|$)');
      expect(gate('gh-23').hasMatch('gh-23 · ⚒️ dev: Fix the run-name'), isTrue);
      expect(gate('pr-45').hasMatch('pr-45 · ▶ review (SM)'), isTrue);
      expect(gate('gh-24').hasMatch('gh-23 · ⚒️ dev: Fix the run-name'),
          isFalse);
    });
  });
}
