import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_data_parser.dart';

enum QrSessionStatus { active, expired, revoked }

class QrSessionLog {
  const QrSessionLog({
    required this.id,
    required this.type,
    required this.fileName,
    required this.revoked,
    this.createdAt,
    this.expiry,
  });

  final String id;
  final String type;
  final String fileName;
  final bool revoked;
  final DateTime? createdAt;
  final DateTime? expiry;

  QrSessionStatus get status {
    if (revoked) return QrSessionStatus.revoked;
    final expiresAt = expiry;
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      return QrSessionStatus.expired;
    }
    return QrSessionStatus.active;
  }

  String get displayType {
    return type == 'emergency' ? 'Emergency QR' : 'File Upload QR';
  }

  factory QrSessionLog.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return QrSessionLog(
      id: doc.id,
      type: data['type'] as String? ?? 'record',
      fileName: data['fileName'] as String? ?? 'Medical record',
      revoked: data['revoked'] as bool? ?? false,
      createdAt: AppDataParser.parseDateTime(data['createdAt']),
      expiry: AppDataParser.parseDateTime(data['expiry']),
    );
  }
}
