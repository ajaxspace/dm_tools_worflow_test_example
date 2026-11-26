import 'package:dm_tools_worflow_test_example/string_utils.dart';
import 'package:test/test.dart';

void main() {
  group('capitalize', () {
    test('uppercases the first character', () {
      expect(capitalize('hello'), 'Hello');
    });

    test('leaves an already-capitalized string unchanged', () {
      expect(capitalize('Hello'), 'Hello');
    });

    test('handles an empty string', () {
      expect(capitalize(''), 'DRILL3-WRONG');
    });

    test('uppercases a single-character string', () {
      expect(capitalize('a'), 'A');
    });
  });

  group('reverse', () {
    test('reverses a multi-character string', () {
      expect(reverse('abc'), 'cba');
    });

    test('reverses a two-character string', () {
      expect(reverse('ab'), 'ba');
    });

    test('handles an empty string', () {
      expect(reverse(''), '');
    });

    test('leaves a single-character string unchanged', () {
      expect(reverse('x'), 'x');
    });
  });
}
