import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth_service.dart';
import '../../core/qr_service.dart';
import '../../models/log_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/loading_widget.dart';

class LogTab extends StatefulWidget {
  const LogTab({super.key});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> {
  final auth = AuthService();
  final qrService = QrService();

  @override
  void initState() {
    super.initState();
    _revokeExpiredSessions();
  }

  Future<void> _revokeExpiredSessions() async {
    final uid = auth.currentUser?.uid;
    if (uid != null) {
      await qrService.revokeExpiredSessionsForUser(uid);
    }
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
        stream: qrService.sessionsForUser(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                EmptyStateCard(
                  title: 'Unable to load logs',
                  message: snapshot.error.toString(),
                  icon: Icons.error_outline,
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const LoadingWidget(message: 'Loading QR sessions...');
          }

          final logs = snapshot.data!.docs.map(QrSessionLog.fromDoc).toList()
            ..sort((a, b) {
              final aTime =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const GradientHeroCard(
                badge: 'QR Activity',
                title: 'Review every secure sharing session in one place.',
                subtitle:
                    'Older records with string dates and newer Firestore timestamps are both handled safely.',
                icon: Icons.history_toggle_off_outlined,
              ),
              const SizedBox(height: 20),
              if (logs.isEmpty)
                const EmptyStateCard(
                  title: 'No QR sessions yet',
                  message:
                      'Generated upload and emergency QR sessions will appear here with status tracking.',
                  icon: Icons.qr_code_2_outlined,
                )
              else
                Column(
                  children: logs.map((log) => _LogCard(log: log)).toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});

  final QrSessionLog log;

  @override
  Widget build(BuildContext context) {
    final status = log.status;

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
                    color: _statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_iconFor(log), color: _statusColor(status)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.displayType,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.type == 'emergency'
                            ? 'Emergency access bundle'
                            : 'Shared medical record session',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: _statusLabel(status),
                  color: _statusColor(status),
                  icon: _statusIcon(status),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            InfoRow(
              label: 'QR Type',
              value: log.displayType,
              leading: Icons.qr_code_2_outlined,
            ),
            if (log.type != 'emergency')
              InfoRow(
                label: 'File Name',
                value: log.fileName,
                leading: Icons.description_outlined,
              ),
            InfoRow(
              label: 'Created',
              value: _timestamp(log.createdAt),
              leading: Icons.schedule_outlined,
            ),
            InfoRow(
              label: 'Status',
              value: _statusLabel(status),
              leading: _statusIcon(status),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(QrSessionLog log) {
    return log.type == 'emergency'
        ? Icons.emergency_share_outlined
        : Icons.insert_drive_file_outlined;
  }

  String _timestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Date unavailable';
    return DateFormat.yMMMd().add_jm().format(timestamp);
  }

  String _statusLabel(QrSessionStatus status) {
    switch (status) {
      case QrSessionStatus.active:
        return 'Active';
      case QrSessionStatus.expired:
        return 'Expired';
      case QrSessionStatus.revoked:
        return 'Revoked';
    }
  }

  IconData _statusIcon(QrSessionStatus status) {
    switch (status) {
      case QrSessionStatus.active:
        return Icons.check_circle_outline;
      case QrSessionStatus.expired:
        return Icons.schedule_outlined;
      case QrSessionStatus.revoked:
        return Icons.block_outlined;
    }
  }

  Color _statusColor(QrSessionStatus status) {
    switch (status) {
      case QrSessionStatus.active:
        return AppTheme.accent;
      case QrSessionStatus.expired:
        return Colors.orange.shade700;
      case QrSessionStatus.revoked:
        return AppTheme.danger;
    }
  }
}
