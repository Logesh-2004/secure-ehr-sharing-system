import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CqepToken {
  const CqepToken({
    required this.version,
    required this.type,
    required this.sessionId,
    required this.uid,
    required this.expiry,
    required this.nonce,
    required this.signature,
  });

  final String version;
  final String type;
  final String sessionId;
  final String uid;
  final DateTime expiry;
  final String nonce;
  final String signature;

  bool get isExpired => DateTime.now().isAfter(expiry);

  String get signingPayload {
    return '$version|$type|$sessionId|$uid|${expiry.millisecondsSinceEpoch}|$nonce';
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'type': type,
      'sessionId': sessionId,
      'uid': uid,
      'expiry': expiry.millisecondsSinceEpoch,
      'nonce': nonce,
      'signature': signature,
    };
  }
}

class EncryptionService {
  EncryptionService._();

  static const String _secretKey = String.fromEnvironment(
    'CQEP_SHARED_SECRET',
    defaultValue: 'NUCLEUS_PROTOCOL_SECRET_KEY_CHANGE_ME',
  );

  static String generateSecureToken({
    required String type,
    required String sessionId,
    required String uid,
    required DateTime expiry,
    required String nonce,
  }) {
    final unsigned = CqepToken(
      version: 'CQEP-1',
      type: type,
      sessionId: sessionId,
      uid: uid,
      expiry: expiry,
      nonce: nonce,
      signature: '',
    );
    final signature = _sign(unsigned.signingPayload);

    return base64UrlEncode(
      utf8.encode(
        jsonEncode(
          CqepToken(
            version: unsigned.version,
            type: unsigned.type,
            sessionId: unsigned.sessionId,
            uid: unsigned.uid,
            expiry: unsigned.expiry,
            nonce: unsigned.nonce,
            signature: signature,
          ).toJson(),
        ),
      ),
    );
  }

  static String generateNonce([int byteLength = 24]) {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(byteLength, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(bytes);
  }

  static CqepToken? parseToken(String token) {
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(token)));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final expiryMillis = data['expiry'];
      if (expiryMillis is! int) return null;

      return CqepToken(
        version: data['version'] as String? ?? '',
        type: data['type'] as String? ?? '',
        sessionId: data['sessionId'] as String? ?? '',
        uid: data['uid'] as String? ?? '',
        expiry: DateTime.fromMillisecondsSinceEpoch(expiryMillis),
        nonce: data['nonce'] as String? ?? '',
        signature: data['signature'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static bool verifyToken(String token) {
    final parsed = parseToken(token);
    if (parsed == null) return false;
    if (parsed.version != 'CQEP-1') return false;
    if (parsed.sessionId.isEmpty ||
        parsed.uid.isEmpty ||
        parsed.nonce.isEmpty) {
      return false;
    }
    if (parsed.isExpired) return false;

    final expectedSignature = _sign(parsed.signingPayload);
    return _constantTimeEquals(expectedSignature, parsed.signature);
  }

  static String _sign(String payload) {
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    return hmac.convert(utf8.encode(payload)).toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);

    if (aBytes.length != bBytes.length) return false;

    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }

    return diff == 0;
  }
}
