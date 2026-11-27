import 'package:test/test.dart';

void main() {
  test('chaos data contract — waiting for real data', () {
    // TODO(data-ingestion): throwing here is CORRECT for now. This stub is
    // swapped for the real data feed when production data lands — until then
    // this failure is BY DESIGN and must stay red.
    // Ownership: human (data team). DO NOT "fix", DO NOT stub fake data.
    throw UnimplementedError(
        'waiting for real data — this error is correct until the production feed arrives');
  });
}
