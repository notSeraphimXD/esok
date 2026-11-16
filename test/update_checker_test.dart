import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/update/update_checker.dart';

void main() {
  test('normalizes release tags', () {
    expect(UpdateChecker.normalizeVersion('v1.9.5'), '1.9.5');
    expect(UpdateChecker.normalizeVersion('1.9.5+16'), '1.9.5');
    expect(UpdateChecker.normalizeVersion('  V1.9.5-beta  '), '1.9.5');
  });

  test('compares semantic versions', () {
    expect(UpdateChecker.isNewerVersion('1.9.5', '1.9.4'), isTrue);
    expect(UpdateChecker.isNewerVersion('v1.10.0', '1.9.9'), isTrue);
    expect(UpdateChecker.isNewerVersion('1.9.4', '1.9.4'), isFalse);
    expect(UpdateChecker.isNewerVersion('1.9.4', '1.9.5'), isFalse);
    expect(UpdateChecker.isNewerVersion('1.9.4+16', '1.9.4'), isFalse);
  });
}
