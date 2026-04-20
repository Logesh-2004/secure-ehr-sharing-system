import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth_service.dart';
import '../../core/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';
import '../logs/access_logs_tab.dart';
import '../scanner/scanner_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Clinician Dashboard'),
          actions: [
            IconButton(
              tooltip: 'Logout',
              onPressed: AuthService().logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  child: const TabBar(
                    tabs: [
                      Tab(text: 'Workspace'),
                      Tab(text: 'Logs'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Expanded(
                child: TabBarView(children: [_OverviewTab(), AccessLogsTab()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final firebase = FirebaseService();
    final user = auth.currentUser;
    final clinicianId = user?.uid;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                title: 'Signed In Clinician',
                subtitle:
                    'Keep this workspace private before unlocking the scanner.',
              ),
              const SizedBox(height: 18),
              InfoRow(
                label: 'Email',
                value: user?.email ?? 'Unknown clinician',
                leading: Icons.mail_outline,
              ),
              InfoRow(
                label: 'Clinician ID',
                value: clinicianId ?? 'Unavailable',
                leading: Icons.badge_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (clinicianId != null)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: firebase.accessLogsForClinician(clinicianId),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? const [];
              final count = docs.length;
              final timestamps =
                  docs
                      .map((doc) => doc.data()['timestamp'])
                      .whereType<Timestamp>()
                      .map((value) => value.toDate())
                      .toList()
                    ..sort((a, b) => b.compareTo(a));
              final lastAccess = timestamps.isEmpty
                  ? 'No access logged yet'
                  : DateFormat.yMMMd().add_jm().format(timestamps.first);

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: _cardWidth(context),
                    height: 160,
                    child: MetricStatCard(
                      label: 'Verified accesses',
                      value: '$count',
                      icon: Icons.verified_outlined,
                      caption: 'Successful patient scans',
                      tint: AppTheme.primary,
                    ),
                  ),
                  SizedBox(
                    width: _cardWidth(context),
                    height: 160,
                    child: MetricStatCard(
                      label: 'Last access',
                      value: lastAccess,
                      icon: Icons.schedule_outlined,
                      caption: 'Most recent clinician log',
                      tint: AppTheme.accent,
                    ),
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(
                title: 'Scanner',
                subtitle:
                    'Unlock biometrics, scan one patient at a time, and retry manually when you are ready.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScannerScreen()),
                  );
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Patient QR'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                title: 'Workflow Notes',
                subtitle:
                    'The scanner now gives explicit status updates from camera initialization through final access handling.',
              ),
              SizedBox(height: 18),
              InfoRow(
                label: 'File access',
                value:
                    'Image uploads preview directly after validation. PDF uploads show file details with an open action when bytes or a URL are available.',
                leading: Icons.insert_drive_file_outlined,
              ),
              InfoRow(
                label: 'Emergency access',
                value:
                    'Emergency scans surface blood group, allergies, and emergency contact details in focused cards.',
                leading: Icons.emergency_outlined,
              ),
              InfoRow(
                label: 'Access logs',
                value:
                    'Successful access events are written to Firestore and shown in the clinician logs tab.',
                leading: Icons.history_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }

  double _cardWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 40;
    if (width > 720) return (width - 16) / 2;
    return width;
  }
}
