import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

import '../core/app_data_parser.dart';

class MedicalRecordModel {
  const MedicalRecordModel({
    required this.id,
    required this.fileName,
    required this.category,
    required this.downloadUrl,
    required this.storagePath,
    required this.contentType,
    required this.size,
    this.fileBytes,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String category;
  final String downloadUrl;
  final String storagePath;
  final String contentType;
  final int size;
  final Uint8List? fileBytes;
  final DateTime? createdAt;

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf =>
      contentType == 'application/pdf' ||
      fileName.toLowerCase().endsWith('.pdf');

  factory MedicalRecordModel.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    return MedicalRecordModel(
      id: doc.id,
      fileName: data['fileName'] as String? ?? 'Medical record',
      category: data['category'] as String? ?? 'General',
      downloadUrl: data['downloadUrl'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      contentType: data['contentType'] as String? ?? 'application/octet-stream',
      size: AppDataParser.parseInt(data['size']),
      fileBytes: AppDataParser.parseBytes(data['fileData']),
      createdAt: AppDataParser.parseDateTime(data['createdAt']),
    );
  }
}
