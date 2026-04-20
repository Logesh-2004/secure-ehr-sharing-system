import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/wearable_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';

class WearableTab extends StatefulWidget {
  const WearableTab({super.key});

  @override
  State<WearableTab> createState() => _WearableTabState();
}

class _WearableTabState extends State<WearableTab> {
  final wearableService = WearableService();
  WearableSnapshot snapshot = const WearableSnapshot(
    connected: false,
    statusMessage: 'Connect Health Connect to import wearable data.',
  );
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _connect() async {
    await _runWearableAction(wearableService.connectAndRead);
  }

  Future<void> _refresh() async {
    await _runWearableAction(wearableService.readLatestSnapshot);
  }

  Future<void> _installHealthConnect() async {
    try {
      await wearableService.installOrUpdateHealthConnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Health Connect install flow opened.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _runWearableAction(
    Future<WearableSnapshot> Function() action,
  ) async {
    setState(() => loading = true);
    try {
      final next = await action();
      if (!mounted) return;
      setState(() => snapshot = next);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        snapshot = WearableSnapshot(
          connected: false,
          statusMessage: error.toString(),
        );
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastSynced = snapshot.lastSyncedAt == null
        ? 'Not synced yet'
        : DateFormat.yMMMd().add_jm().format(snapshot.lastSyncedAt!);

    final metrics = [
      _WearableMetric(
        label: 'Heart Rate',
        value: snapshot.heartRate == null
            ? 'Not Available'
            : '${snapshot.heartRate} bpm',
        icon: Icons.favorite_outline,
        caption: 'Latest recorded pulse',
        tint: const Color(0xFFE36A7A),
      ),
      _WearableMetric(
        label: 'Steps Today',
        value: snapshot.steps == null
            ? 'Not Available'
            : NumberFormat.decimalPattern().format(snapshot.steps),
        icon: Icons.directions_walk_outlined,
        caption: 'Daily movement progress',
        tint: const Color(0xFF0E7C86),
      ),
      _WearableMetric(
        label: 'Calories Burned',
        value: snapshot.caloriesBurned == null
            ? 'Not Available'
            : '${snapshot.caloriesBurned!.toStringAsFixed(0)} kcal',
        icon: Icons.local_fire_department_outlined,
        caption: 'Active calories today',
        tint: const Color(0xFFF08B49),
      ),
      _WearableMetric(
        label: 'Sleep Duration',
        value: snapshot.sleepMinutes == null
            ? 'Not Available'
            : _formatDuration(snapshot.sleepMinutes!),
        icon: Icons.bedtime_outlined,
        caption: 'Last 24 hours',
        tint: const Color(0xFF6C7CE7),
      ),
      _WearableMetric(
        label: 'Distance Walked',
        value: snapshot.distanceMeters == null
            ? 'Not Available'
            : '${(snapshot.distanceMeters! / 1000).toStringAsFixed(2)} km',
        icon: Icons.route_outlined,
        caption: 'Walking and running',
        tint: const Color(0xFF289C73),
      ),
      _WearableMetric(
        label: 'Blood Oxygen',
        value: snapshot.bloodOxygen == null
            ? 'Not Available'
            : '${snapshot.bloodOxygen!.toStringAsFixed(0)}%',
        icon: Icons.air_outlined,
        caption: 'Placeholder when device data is unavailable',
        tint: const Color(0xFF00A5B5),
      ),
      _WearableMetric(
        label: 'Active Minutes',
        value: snapshot.activeMinutes == null
            ? 'Not Available'
            : '${snapshot.activeMinutes} min',
        icon: Icons.fitness_center_outlined,
        caption: 'Exercise time today',
        tint: const Color(0xFF9169E7),
      ),
      _WearableMetric(
        label: 'Weight',
        value: snapshot.weightKg == null
            ? 'Not Available'
            : '${snapshot.weightKg!.toStringAsFixed(1)} kg',
        icon: Icons.monitor_weight_outlined,
        caption: 'Latest synced weight',
        tint: const Color(0xFF6A95D8),
      ),
      _WearableMetric(
        label: 'Hydration',
        value: snapshot.hydrationLiters == null
            ? 'Not Available'
            : '${snapshot.hydrationLiters!.toStringAsFixed(2)} L',
        icon: Icons.water_drop_outlined,
        caption: 'Water intake today',
        tint: const Color(0xFF34A0C8),
      ),
      _WearableMetric(
        label: 'Last Sync',
        value: lastSynced,
        icon: Icons.sync_outlined,
        caption: snapshot.connected ? 'Health Connect linked' : 'Awaiting sync',
        tint: AppTheme.primary,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Wearables',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  StatusBadge(
                    label: snapshot.connected ? 'Connected' : 'Not Connected',
                    color: snapshot.connected
                        ? AppTheme.accent
                        : AppTheme.danger,
                    icon: snapshot.connected
                        ? Icons.check_circle_outline
                        : Icons.sync_problem_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                snapshot.statusMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: _actionWidth(context),
                    child: FilledButton.icon(
                      onPressed: loading ? null : _connect,
                      icon: loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Connect'),
                    ),
                  ),
                  SizedBox(
                    width: _actionWidth(context),
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : _refresh,
                      icon: const Icon(Icons.sync),
                      label: const Text('Refresh'),
                    ),
                  ),
                  SizedBox(
                    width: _actionWidth(context),
                    child: OutlinedButton.icon(
                      onPressed: _installHealthConnect,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Install'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: _metricWidth(context),
                  height: 170,
                  child: MetricStatCard(
                    label: metric.label,
                    value: metric.value,
                    icon: metric.icon,
                    caption: metric.caption,
                    tint: metric.tint,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  double _metricWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 40;
    if (width > 1000) return (width - 28) / 3;
    if (width > 680) return (width - 14) / 2;
    return width;
  }

  double _actionWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 40;
    if (width > 920) return (width - 24) / 3;
    if (width > 640) return (width - 12) / 2;
    return width;
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (hours == 0) return '$remaining min';
    return '${hours}h ${remaining}m';
  }
}

class _WearableMetric {
  const _WearableMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.caption,
    required this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final String caption;
  final Color tint;
}
