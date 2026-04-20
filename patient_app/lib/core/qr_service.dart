import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_data_parser.dart';
import 'encryption_service.dart';
import 'firebase_service.dart';

class QrSessionResult {
  const QrSessionResult({
    required this.sessionId,
    required this.token,
    required this.expiry,
  });

  final String sessionId;
  final String token;
  final DateTime expiry;
}

class QrService {
  QrService({FirebaseService? firebaseService})
    : _firebase = firebaseService ?? FirebaseService();

  static const Duration qrLifetime = Duration(seconds: 60);

  final FirebaseService _firebase;

  Stream<QuerySnapshot<Map<String, dynamic>>> sessionsForUser(String uid) {
    return _firebase.qrSessions.where('uid', isEqualTo: uid).snapshots();
  }

  Future<QrSessionResult> createRecordSession({
    required String uid,
    required String recordId,
    required String fileName,
  }) {
    return _createSession(
      uid: uid,
      type: 'record',
      fileName: fileName,
      recordId: recordId,
    );
  }

  Future<QrSessionResult> createEmergencySession({required String uid}) {
    return _createSession(
      uid: uid,
      type: 'emergency',
      fileName: 'Emergency QR',
    );
  }

  Future<void> revokeSession(String sessionId) {
    return _firebase.qrSessions.doc(sessionId).set({
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> revokeExpiredSessionsForUser(String uid) async {
    final sessions = await _firebase.qrSessions
        .where('uid', isEqualTo: uid)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in sessions.docs) {
      final data = doc.data();
      final revoked = data['revoked'] as bool? ?? false;
      final expiry = AppDataParser.parseDateTime(data['expiry']);
      if (revoked || expiry == null || expiry.isAfter(DateTime.now())) {
        continue;
      }
      batch.update(doc.reference, {
        'revoked': true,
        'revokedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<QrSessionResult> _createSession({
    required String uid,
    required String type,
    required String fileName,
    String? recordId,
  }) async {
    final expiry = DateTime.now().add(qrLifetime);
    final nonce = EncryptionService.generateNonce();
    final doc = _firebase.qrSessions.doc();

    await doc.set({
      'sessionId': doc.id,
      'uid': uid,
      'fileName': fileName,
      'recordId': recordId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiry': Timestamp.fromDate(expiry),
      'revoked': false,
      'type': type,
      'nonce': nonce,
    });

    final token = EncryptionService.generateSecureToken(
      type: type,
      sessionId: doc.id,
      uid: uid,
      expiry: expiry,
      nonce: nonce,
    );

    return QrSessionResult(sessionId: doc.id, token: token, expiry: expiry);
  }
}
