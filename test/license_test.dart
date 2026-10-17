import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled LICENSE contains the MIT license', () async {
    final text = await rootBundle.loadString('LICENSE');
    expect(text, contains('MIT License'));
    expect(text, contains('faria2 contributors'));
  });
}
