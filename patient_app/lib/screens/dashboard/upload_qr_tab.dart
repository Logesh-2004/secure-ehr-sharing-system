import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth_service.dart';
import '../../core/biometric_service.dart';
import '../../core/firebase_service.dart';
import '../../core/qr_service.dart';
import '../../models/medical_record_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/qr_session_panel.dart';

class UploadQrTab extends StatefulWidget {
  const UploadQrTab({super.key});

  @override
  State<UploadQrTab> createState() => _UploadQrTabState();
}

class _UploadQrTabState extends State<UploadQrTab> {
  static const _categories = [
    'Lab Report',
    'Prescription',
    'Discharge Summary',
    'Imaging',
    'Insurance',
    'General',
  ];

  final auth = AuthService();
  final biometric = BiometricService();
  final firebase = FirebaseService();
  final qrService = QrService();

  String category = _categories.first;
  String? qrToken;
  String? sessionId;
  String? selectedRecordId;
  String? activeRecordName;
  bool uploading = false;
  bool generating = false;
  int secondsRemaining = 0;
  Timer? countdownTimer;

  @override
  void initState() {
    super.initState();
    _revokeExpiredSessions();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _revokeExpiredSessions() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    await qrService.revokeExpiredSessionsForUser(uid);
  }

  Future<void> _uploadRecord() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showMessage('Could not read the selected file bytes.');
      return;
    }

    setState(() => uploading = true);
    try {
      if (_byteLength(bytes) > 750 * 1024) {
        _showMessage(
          'Selected file is too large for free Firestore storage. Choose a smaller file under 750 KB.',
        );
        return;
      }

      final contentType = _contentTypeFor(file.name);
      final doc = firebase.medicalRecords(uid).doc();

      await doc.set({
        'recordId': doc.id,
        'fileName': file.name,
        'category': category,
        'contentType': contentType,
        'fileFormat': _fileFormatFor(contentType),
        'size': _byteLength(bytes),
        'fileData': Blob(bytes),
        'storagePath': '',
        'downloadUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'uploadedVia': 'firestore_blob',
      });

      setState(() {
        selectedRecordId = doc.id;
        activeRecordName = file.name;
      });
      _showMessage(
        'Medical record uploaded. Verify biometrics to generate QR.',
      );
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _generateQrForRecord(MedicalRecordModel record) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final allowed = await biometric.authenticate(
      reason: 'Verify biometrics to generate this medical record QR',
    );
    if (!allowed) {
      _showMessage('Biometric consent is required before sharing.');
      return;
    }

    setState(() {
      generating = true;
      selectedRecordId = record.id;
      activeRecordName = record.fileName;
    });

    try {
      final result = await qrService.createRecordSession(
        uid: uid,
        recordId: record.id,
        fileName: record.fileName,
      );

      setState(() {
        qrToken = result.token;
        sessionId = result.sessionId;
        secondsRemaining = _secondsUntil(result.expiry);
      });
      _startTimer();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  void _startTimer() {
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (secondsRemaining <= 1) {
        timer.cancel();
        _expireQr();
      } else {
        setState(() => secondsRemaining--);
      }
    });
  }

  Future<void> _expireQr() async {
    final activeSessionId = sessionId;
    if (activeSessionId != null) {
      await qrService.revokeSession(activeSessionId);
    }
    if (!mounted) return;
    setState(() {
      qrToken = null;
      sessionId = null;
      secondsRemaining = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      return const LoadingWidget(message: 'Waiting for authentication...');
    }

    return RefreshIndicator(
      onRefresh: _revokeExpiredSessions,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firebase.medicalRecords(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                EmptyStateCard(
                  title: 'Unable to load records',
                  message: snapshot.error.toString(),
                  icon: Icons.error_outline,
                ),
              ],
            );
          }

          if (!snapshot.hasData) {
            return const LoadingWidget(message: 'Loading records...');
          }

          final records =
              snapshot.data!.docs.map(MedicalRecordModel.fromDoc).toList()
                ..sort((a, b) {
                  final aTime =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bTime =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bTime.compareTo(aTime);
                });
          final selectedRecord = _selectedRecord(records);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              GradientHeroCard(
                badge: 'Medical Records Vault',
                title: 'Upload a PDF or image, then share a one-minute QR.',
                subtitle:
                    'Every QR session is short-lived, biometric-gated, and revocable on demand.',
                icon: Icons.folder_shared_outlined,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    StatusBadge(
                      label:
                          '${records.length} stored record${records.length == 1 ? '' : 's'}',
                      color: AppTheme.accent,
                      icon: Icons.inventory_2_outlined,
                    ),
                    StatusBadge(
                      label: category,
                      color: Colors.white,
                      icon: Icons.category_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      title: 'Add or Select a Record',
                      subtitle:
                          'Images render with preview support for clinicians. PDFs keep file metadata for secure viewing.',
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      items: _categories
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: uploading
                          ? null
                          : (value) => setState(() => category = value!),
                      decoration: const InputDecoration(
                        labelText: 'Record Category',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    CustomButton(
                      label: 'Upload PDF or Image',
                      icon: Icons.upload_file_outlined,
                      isLoading: uploading,
                      onPressed: _uploadRecord,
                    ),
                    const SizedBox(height: 16),
                    if (selectedRecord != null) ...[
                      _RecordPreviewCard(record: selectedRecord),
                      const SizedBox(height: 16),
                    ],
                    CustomButton(
                      label: selectedRecord == null
                          ? 'Select a Record to Generate QR'
                          : 'Verify Biometrics and Generate QR',
                      icon: Icons.fingerprint,
                      isLoading: generating,
                      onPressed: selectedRecord == null
                          ? null
                          : () => _generateQrForRecord(selectedRecord),
                    ),
                  ],
                ),
              ),
              if (qrToken != null) ...[
                const SizedBox(height: 20),
                QrSessionPanel(
                  token: qrToken!,
                  secondsRemaining: secondsRemaining,
                  title: 'Secure QR ready',
                  subtitle: activeRecordName ?? 'Medical record',
                  onRevoke: _expireQr,
                ),
              ],
              const SizedBox(height: 20),
              const SectionTitle(
                title: 'Stored Records',
                subtitle:
                    'Tap any card to select it before creating a secure QR session.',
              ),
              const SizedBox(height: 12),
              if (records.isEmpty)
                const EmptyStateCard(
                  title: 'No records uploaded yet',
                  message:
                      'Upload a lab report, prescription, discharge summary, or imaging file to start secure sharing.',
                  icon: Icons.folder_open_outlined,
                )
              else
                Column(
                  children: records
                      .map(
                        (record) => _RecordListCard(
                          record: record,
                          selected: selectedRecordId == record.id,
                          onTap: () {
                            setState(() {
                              selectedRecordId = record.id;
                              activeRecordName = record.fileName;
                            });
                          },
                          onGenerate: generating
                              ? null
                              : () => _generateQrForRecord(record),
                        ),
                      )
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }

  MedicalRecordModel? _selectedRecord(List<MedicalRecordModel> records) {
    if (records.isEmpty || selectedRecordId == null) return null;
    for (final record in records) {
      if (record.id == selectedRecordId) return record;
    }
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  String _fileFormatFor(String contentType) {
    if (contentType == 'application/pdf') return 'pdf';
    if (contentType.startsWith('image/')) return 'image';
    return 'file';
  }

  int _byteLength(Uint8List bytes) => bytes.lengthInBytes;

  int _secondsUntil(DateTime expiry) {
    return expiry.difference(DateTime.now()).inSeconds.clamp(0, 60).toInt();
  }
}

class _RecordPreviewCard extends StatelessWidget {
  const _RecordPreviewCard({required this.record});

  final MedicalRecordModel record;

  @override
  Widget build(BuildContext context) {
    final created = record.createdAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(record.createdAt!);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primary.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  record.isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: AppTheme.primaryDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected record',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.fileName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: record.category,
                color: AppTheme.accent,
                icon: Icons.label_outline,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (record.isImage && record.fileBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(
                record.fileBytes!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    record.isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.description_outlined,
                    size: 38,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    record.isPdf
                        ? 'PDF ready for secure QR access'
                        : 'Preview unavailable for this file',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          InfoRow(
            label: 'Created',
            value: created,
            leading: Icons.schedule_outlined,
          ),
          InfoRow(
            label: 'Size',
            value: _formatFileSize(record.size),
            leading: Icons.data_usage_outlined,
          ),
        ],
      ),
    );
  }
}

class _RecordListCard extends StatelessWidget {
  const _RecordListCard({
    required this.record,
    required this.selected,
    required this.onTap,
    required this.onGenerate,
  });

  final MedicalRecordModel record;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext context) {
    final created = record.createdAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(record.createdAt!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SectionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary.withOpacity(0.14)
                          : AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      record.isPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.image_outlined,
                      color: selected ? AppTheme.primaryDark : AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.fileName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${record.category} • $created',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle, color: AppTheme.accent),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: StatusBadge(
                      label: _formatFileSize(record.size),
                      color: AppTheme.primary,
                      icon: Icons.storage_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onGenerate,
                      icon: const Icon(Icons.qr_code_2_outlined),
                      label: const Text('Generate QR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
