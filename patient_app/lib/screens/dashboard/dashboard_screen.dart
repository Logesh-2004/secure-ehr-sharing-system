import 'package:flutter/material.dart';

import 'emergency_tab.dart';
import 'log_tab.dart';
import 'upload_qr_tab.dart';
import 'wearable_tab.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(title: const Text('Patient Dashboard')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  child: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Upload & QR'),
                      Tab(text: 'Emergency'),
                      Tab(text: 'Wearables'),
                      Tab(text: 'Logs'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Expanded(
                child: TabBarView(
                  children: [
                    UploadQrTab(),
                    EmergencyTab(),
                    WearableTab(),
                    LogTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
