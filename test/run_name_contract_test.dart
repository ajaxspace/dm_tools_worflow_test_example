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

/// The folded (`>-`) run-name scalar unfolded the way YAML folds:
/// continuation lines joined with single spaces.
String runNameValue(String yaml) {
  final lines = yaml.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('run-name:'));
  if (start < 0) return '';
  final block = lines
      .sublist(start + 1)
      .takeWhile((l) => l.trim().isEmpty || l.startsWith(' '))
      .toList();
  return block.map((l) => l.trim()).join(' ');
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
