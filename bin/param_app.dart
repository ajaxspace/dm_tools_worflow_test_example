// Params-drill probe for the self-heal group detector.
// Prints OK for healthy modes; exits 1 for 'bad' — the drill breaks a lane
// by DISPATCHING this workflow with mode=bad.
// The commented line below is the "normal variant": the human drill-fix is
// uncommenting it (and commenting the throw) — exercising the manual triage
// path of the group detector (needs-human issues stay unassigned).
void main(List<String> args) {
  final mode = args.isNotEmpty ? args.first : 'good';
  if (mode == 'bad') {
    // Drill failure: the wrong branch is active. The normal variant:
    // print('mode=$mode — all good');
    throw StateError('mode=$mode — drill failure (wrong branch active)');
  }
  print('mode=$mode — all good');
}
