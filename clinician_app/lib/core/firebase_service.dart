import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_data_parser.dart';
import 'encryption_service.dart';

enum PatientAccessProgress {
  validatingToken,
  fetchingPatientData,
  loggingAccess,
}

class PatientAccessResult {
  const PatientAccessResult({
    required this.patientUid,
    required this.accessType,
    this.profile = const {},
    this.emergency = const {},
    this.record = const {},
  });

  final String patientUid;
  final String accessType;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> emergency;
  final Map<String, dynamic> record;

  bool get isEmergency => accessType == 'emergency';

  String get fileName =>
      AppDataParser.stringValue(record['fileName'], fallback: 'Medical record');

  String get contentType => AppDataParser.stringValue(
    record['contentType'],
    fallback: 'application/octet-stream',
  );

  Uint8List? get fileBytes => AppDataParser.parseBytes(record['fileData']);

  String get downloadUrl => AppDataParser.stringValue(record['downloadUrl']);

  int get fileSize => AppDataParser.parseInt(record['size']);

  DateTime? get recordCreatedAt =>
      AppDataParser.parseDateTime(record['createdAt']);

  bool get isImage => contentType.startsWith('image/');

  bool get isPdf =>
      contentType == 'application/pdf' ||
      fileName.toLowerCase().endsWith('.pdf');
}

class TokenValidationException implements Exception {
  const TokenValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> accessLogsForClinician(
    String clinicianUid,
  ) {
    return _firestore
        .collection('access_logs')
        .where('clinicianUid', isEqualTo: clinicianUid)
        .snapshots();
  }

  Future<PatientAccessResult> validateAndFetchPatientData({
    required String rawToken,
    required String clinicianUid,
    void Function(PatientAccessProgress progress)? onProgress,
  }) async {
    onProgress?.call(PatientAccessProgress.validatingToken);

    if (!EncryptionService.verifyToken(rawToken)) {
      throw const TokenValidationException('Invalid or expired CQEP token.');
    }

    final token = EncryptionService.parseToken(rawToken);
    if (token == null) {
      throw const TokenValidationException('Malformed CQEP token.');
    }

    final sessionRef = _firestore
        .collection('qr_sessions')
        .doc(token.sessionId);
    final sessionSnapshot = await sessionRef.get();
    if (!sessionSnapshot.exists) {
      throw const TokenValidationException('QR session was not found.');
    }

    final session = sessionSnapshot.data()!;
    final storedExpiry = AppDataParser.parseDateTime(session['expiry']);
    final storedNonce = session['nonce'] as String?;
    final revoked = session['revoked'] as bool? ?? false;
    final storedUid = session['uid'] as String?;
    final storedType = session['type'] as String?;

    if (revoked) {
      throw const TokenValidationException('QR session is revoked.');
    }
    if (storedUid != token.uid || storedType != token.type) {
      throw const TokenValidationException('Token does not match the session.');
    }
    if (storedNonce != token.nonce) {
      throw const TokenValidationException('Token nonce does not match.');
    }
    if (storedExpiry == null || DateTime.now().isAfter(storedExpiry)) {
      await sessionRef.set({
        'revoked': true,
        'revokedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      throw const TokenValidationException('QR session has expired.');
    }

    onProgress?.call(PatientAccessProgress.fetchingPatientData);

    final patientUid = token.uid;
    final profileSnapshot = await _firestore
        .collection('users')
        .doc(patientUid)
        .collection('profile')
        .doc('data')
        .get();
    final profile = profileSnapshot.data() ?? {};

    late final PatientAccessResult result;
    if (token.type == 'emergency') {
      final emergencySnapshot = await _firestore
          .collection('users')
          .doc(patientUid)
          .collection('emergency')
          .doc('data')
          .get();
      result = PatientAccessResult(
        patientUid: patientUid,
        accessType: 'emergency',
        emergency: emergencySnapshot.data() ?? {},
      );
    } else if (token.type == 'record') {
      final recordId = session['recordId'] as String?;
      if (recordId == null || recordId.isEmpty) {
        throw const TokenValidationException(
          'Record session is missing recordId.',
        );
      }

      final recordSnapshot = await _firestore
          .collection('users')
          .doc(patientUid)
          .collection('medical_records')
          .doc(recordId)
          .get();
      if (!recordSnapshot.exists) {
        throw const TokenValidationException(
          'Authorized record was not found.',
        );
      }

      result = PatientAccessResult(
        patientUid: patientUid,
        accessType: 'file',
        profile: profile,
        record: recordSnapshot.data() ?? {},
      );
    } else {
      throw const TokenValidationException('Unsupported QR session type.');
    }

    onProgress?.call(PatientAccessProgress.loggingAccess);

    await _firestore.collection('access_logs').add({
      'patientUid': patientUid,
      'clinicianUid': clinicianUid,
      'timestamp': FieldValue.serverTimestamp(),
      'accessType': result.accessType,
      'fileName': result.isEmergency ? 'Emergency QR' : result.fileName,
      'validationStatus': 'Access Granted',
      'sessionId': token.sessionId,
    });

    await sessionRef.set({
      'revoked': true,
      'revokedAt': FieldValue.serverTimestamp(),
      'accessedAt': FieldValue.serverTimestamp(),
      'accessedBy': clinicianUid,
    }, SetOptions(merge: true));

    return result;
  }
}
