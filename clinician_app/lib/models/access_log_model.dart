import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_data_parser.dart';

class AccessLogModel {
  const AccessLogModel({
    required this.id,
    required this.patientUid,
    required this.accessType,
    required this.validationStatus,
    required this.fileName,
    this.accessedAt,
  });

  final String id;
  final String patientUid;
  final String accessType;
  final String validationStatus;
  final String fileName;
  final DateTime? accessedAt;

  String get accessTypeLabel {
    return accessType == 'emergency' ? 'Emergency' : 'File';
  }

  factory AccessLogModel.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AccessLogModel(
      id: doc.id,
      patientUid: AppDataParser.stringValue(
        data['patientUid'],
        fallback: 'Unknown patient',
      ),
      accessType: AppDataParser.stringValue(
        data['accessType'],
        fallback: 'file',
      ),
      validationStatus: AppDataParser.stringValue(
        data['validationStatus'],
        fallback: 'Access Granted',
      ),
      fileName: AppDataParser.stringValue(
        data['fileName'],
        fallback: 'Emergency bundle',
      ),
      accessedAt: AppDataParser.parseDateTime(
        data['timestamp'] ?? data['accessedAt'],
      ),
    );
  }
}
