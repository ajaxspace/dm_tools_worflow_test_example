// Prints a summary line for the params smoke workflow.
//
// Usage: dart run bin/param_app.dart <mode>
//
// Every dispatched mode prints a summary and exits 0 (healed gh-31/gh-33):
// a mode without a data entry drills 0 revisions instead of throwing —
// the drill contract is "anything else = ok".
void main(List<String> args) {
  final mode = args.isNotEmpty ? args.first : 'good';
  final revisions = {'good': 12, 'green': 7, 'bad': 0};
  print('smoke $mode: ${revisions[mode] ?? 0} revisions');
}
