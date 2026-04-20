import 'package:clinician_app/core/encryption_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CQEP token parser rejects malformed data', () {
    expect(EncryptionService.parseToken('not-a-token'), isNull);
  });
}
