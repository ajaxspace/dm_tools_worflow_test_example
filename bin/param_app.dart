// Prints a summary line for the params smoke workflow.
//
// Usage: dart run bin/param_app.dart <mode>
void main(List<String> args) {
  final mode = args.isNotEmpty ? args.first : 'good';
  final revisions = {'good': 12, 'green': 7};
  if (!revisions.containsKey(mode)) {
    throw StateError('no data for mode: $mode');
  }
  print('smoke $mode: ${revisions[mode]} revisions');
}
