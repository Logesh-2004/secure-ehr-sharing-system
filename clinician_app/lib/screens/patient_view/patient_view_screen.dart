import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_data_parser.dart';
import '../../core/document_launcher_service.dart';
import '../../core/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';

class PatientViewScreen extends StatelessWidget {
  const PatientViewScreen({required this.result, super.key});

  final PatientAccessResult result;

  @override
  Widget build(BuildContext context) {
    final isEmergency = result.isEmergency;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEmergency ? 'Emergency Data' : 'Patient Record'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GradientHeroCard(
            badge: isEmergency ? 'Emergency Access' : 'Authorized Record',
            title: isEmergency
                ? 'Critical patient details are ready for review.'
                : 'Validated patient file access is now open.',
            subtitle: isEmergency
                ? 'Review core emergency information carefully before acting.'
                : 'Use only the data returned for this secure QR session.',
            icon: isEmergency
                ? Icons.emergency_outlined
                : Icons.folder_shared_outlined,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: SelectableText(
                'Patient UID: ${result.patientUid}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (isEmergency) ...[
            _EmergencySection(data: result.emergency),
          ] else ...[
            if (result.profile.isNotEmpty)
              _ProfileSection(data: result.profile),
            const SizedBox(height: 16),
            _RecordSection(result: result),
          ],
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where(
      (entry) =>
          entry.value != null && entry.value.toString().trim().isNotEmpty,
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Patient Profile',
            subtitle: 'These profile fields were available for this session.',
          ),
          const SizedBox(height: 18),
          ...entries.map(
            (entry) => InfoRow(
              label: AppDataParser.prettifyKey(entry.key),
              value: _formatValue(entry.value),
              leading: Icons.person_outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencySection extends StatelessWidget {
  const _EmergencySection({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                title: 'Emergency Summary',
                subtitle:
                    'The following details are intended for rapid triage access.',
              ),
              const SizedBox(height: 18),
              InfoRow(
                label: 'Blood Group',
                value: AppDataParser.stringValue(
                  data['bloodGroup'],
                  fallback: 'Not Available',
                ),
                leading: Icons.bloodtype_outlined,
              ),
              InfoRow(
                label: 'Allergies',
                value: AppDataParser.stringValue(
                  data['allergies'],
                  fallback: 'Not Available',
                ),
                leading: Icons.warning_amber_outlined,
              ),
              InfoRow(
                label: 'Emergency Contact',
                value: AppDataParser.stringValue(
                  data['emergencyContact'],
                  fallback: 'Not Available',
                ),
                leading: Icons.call_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordSection extends StatelessWidget {
  const _RecordSection({required this.result});

  final PatientAccessResult result;

  @override
  Widget build(BuildContext context) {
    final launcher = const DocumentLauncherService();
    final created = result.recordCreatedAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(result.recordCreatedAt!);

    Future<void> openDocument() async {
      try {
        if (result.fileBytes != null) {
          await launcher.openDocumentBytes(
            bytes: result.fileBytes!,
            fileName: result.fileName,
          );
          return;
        }
        if (result.downloadUrl.isNotEmpty) {
          await launcher.openExternalUrl(result.downloadUrl);
          return;
        }
        throw StateError('No document bytes or download URL were available.');
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Authorized Record',
            subtitle:
                'Only the file linked to the validated QR session is shown here.',
          ),
          const SizedBox(height: 18),
          if (result.isImage && result.fileBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.memory(
                result.fileBytes!,
                width: double.infinity,
                height: 240,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Icon(
                    result.isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.description_outlined,
                    size: 46,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    result.isPdf
                        ? 'PDF record ready to open'
                        : 'Record metadata available',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          InfoRow(
            label: 'File Name',
            value: result.fileName,
            leading: Icons.description_outlined,
          ),
          InfoRow(
            label: 'Category',
            value: AppDataParser.stringValue(
              result.record['category'],
              fallback: 'General',
            ),
            leading: Icons.category_outlined,
          ),
          InfoRow(
            label: 'Content Type',
            value: result.contentType,
            leading: Icons.file_present_outlined,
          ),
          InfoRow(
            label: 'Created',
            value: created,
            leading: Icons.schedule_outlined,
          ),
          InfoRow(
            label: 'Size',
            value: _formatFileSize(result.fileSize),
            leading: Icons.data_usage_outlined,
          ),
          const SizedBox(height: 12),
          if (result.isPdf || result.downloadUrl.isNotEmpty)
            FilledButton.icon(
              onPressed: openDocument,
              icon: const Icon(Icons.open_in_new_outlined),
              label: Text(result.isPdf ? 'Open PDF' : 'Open / Download'),
            ),
        ],
      ),
    );
  }
}

String _formatValue(Object? value) {
  final timestamp = AppDataParser.parseDateTime(value);
  if (timestamp != null) {
    return DateFormat.yMMMd().add_jm().format(timestamp);
  }
  return AppDataParser.stringValue(value, fallback: 'Not Available');
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return 'Unknown size';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
