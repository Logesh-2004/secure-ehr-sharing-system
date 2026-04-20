import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth_service.dart';
import '../../core/firebase_service.dart';
import '../../models/access_log_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/loading_widget.dart';

class AccessLogsTab extends StatelessWidget {
  const AccessLogsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      return const LoadingWidget(message: 'Waiting for authentication...');
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseService().accessLogsForClinician(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              EmptyStateCard(
                title: 'Unable to load clinician logs',
                message: snapshot.error.toString(),
                icon: Icons.error_outline,
              ),
            ],
          );
        }

        if (!snapshot.hasData) {
          return const LoadingWidget(message: 'Loading access logs...');
        }

        final logs = snapshot.data!.docs.map(AccessLogModel.fromDoc).toList()
          ..sort((a, b) {
            final aTime =
                a.accessedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime =
                b.accessedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const GradientHeroCard(
              badge: 'Access Logs',
              title: 'Track each verified patient access session.',
              subtitle:
                  'These logs come from Firestore and summarize who was accessed, what type of access was granted, and when it happened.',
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: 20),
            if (logs.isEmpty)
              const EmptyStateCard(
                title: 'No access logs yet',
                message:
                    'Once a patient QR is successfully validated, the event will appear here automatically.',
                icon: Icons.history_outlined,
              )
            else
              Column(
                children: logs.map((log) => _AccessLogCard(log: log)).toList(),
              ),
          ],
        );
      },
    );
  }
}

class _AccessLogCard extends StatelessWidget {
  const _AccessLogCard({required this.log});

  final AccessLogModel log;

  @override
  Widget build(BuildContext context) {
    final timestamp = log.accessedAt == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(log.accessedAt!);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    log.accessType == 'emergency'
                        ? Icons.emergency_outlined
                        : Icons.insert_drive_file_outlined,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Patient ${log.patientUid}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.accessTypeLabel,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: log.validationStatus,
                  color: AppTheme.accent,
                  icon: Icons.check_circle_outline,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            InfoRow(
              label: 'Patient ID',
              value: log.patientUid,
              leading: Icons.badge_outlined,
            ),
            InfoRow(
              label: 'Access Type',
              value: log.accessTypeLabel,
              leading: Icons.lock_open_outlined,
            ),
            InfoRow(
              label: 'File Name',
              value: log.fileName,
              leading: Icons.description_outlined,
            ),
            InfoRow(
              label: 'Time Accessed',
              value: timestamp,
              leading: Icons.schedule_outlined,
            ),
            InfoRow(
              label: 'Validation Status',
              value: log.validationStatus,
              leading: Icons.fact_check_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
