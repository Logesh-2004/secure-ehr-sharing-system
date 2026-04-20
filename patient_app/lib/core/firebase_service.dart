import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  FirebaseService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get qrSessions {
    return _firestore.collection('qr_sessions');
  }

  CollectionReference<Map<String, dynamic>> get accessLogs {
    return _firestore.collection('access_logs');
  }

  DocumentReference<Map<String, dynamic>> userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> profileDoc(String uid) {
    return userDoc(uid).collection('profile').doc('data');
  }

  DocumentReference<Map<String, dynamic>> emergencyDoc(String uid) {
    return userDoc(uid).collection('emergency').doc('data');
  }

  CollectionReference<Map<String, dynamic>> medicalRecords(String uid) {
    return userDoc(uid).collection('medical_records');
  }
}
