import 'dart:io';

import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

class WearableSnapshot {
  const WearableSnapshot({
    required this.connected,
    required this.statusMessage,
    this.heartRate,
    this.steps,
    this.caloriesBurned,
    this.sleepMinutes,
    this.distanceMeters,
    this.bloodOxygen,
    this.activeMinutes,
    this.weightKg,
    this.hydrationLiters,
    this.lastSyncedAt,
  });

  final bool connected;
  final String statusMessage;
  final int? heartRate;
  final int? steps;
  final double? caloriesBurned;
  final int? sleepMinutes;
  final double? distanceMeters;
  final double? bloodOxygen;
  final int? activeMinutes;
  final double? weightKg;
  final double? hydrationLiters;
  final DateTime? lastSyncedAt;
}

class WearableService {
  WearableService({Health? health}) : _health = health ?? Health();

  final Health _health;

  static const _requiredTypes = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
  ];
  static const _requiredPermissions = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];
  static const _optionalTypes = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.EXERCISE_TIME,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.WEIGHT,
    HealthDataType.WATER,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];
  static const _optionalPermissions = [
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];
  static const _sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  Future<WearableSnapshot> connectAndRead() async {
    final availability = await _healthConnectAvailability();
    if (availability != null) return availability;

    await _health.configure();

    if (Platform.isAndroid) {
      final activityRecognition = await Permission.activityRecognition
          .request();
      if (!activityRecognition.isGranted) {
        return const WearableSnapshot(
          connected: false,
          statusMessage: 'Allow Physical activity permission to read steps.',
        );
      }
    }

    final granted = await _health.requestAuthorization(
      _requiredTypes,
      permissions: _requiredPermissions,
    );
    if (!granted) {
      return const WearableSnapshot(
        connected: false,
        statusMessage: 'Health Connect permission was not granted.',
      );
    }

    await _health.requestAuthorization(
      _optionalTypes,
      permissions: _optionalPermissions,
    );

    return readLatestSnapshot();
  }

  Future<WearableSnapshot> readLatestSnapshot() async {
    final availability = await _healthConnectAvailability();
    if (availability != null) return availability;

    await _health.configure();

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final yesterday = now.subtract(const Duration(hours: 24));
    final lastWeek = now.subtract(const Duration(days: 7));

    final hasPermissions = await _health.hasPermissions(
      _requiredTypes,
      permissions: _requiredPermissions,
    );
    if (hasPermissions != true) {
      return const WearableSnapshot(
        connected: false,
        statusMessage: 'Tap Connect Health Connect to grant access.',
      );
    }

    final steps = await _health.getTotalStepsInInterval(startOfDay, now);
    final heartRatePoints = await _safeRead(
      startTime: yesterday,
      endTime: now,
      types: const [HealthDataType.HEART_RATE],
    );
    final caloriePoints = await _safeRead(
      startTime: startOfDay,
      endTime: now,
      types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
    );
    final distancePoints = await _safeRead(
      startTime: startOfDay,
      endTime: now,
      types: const [HealthDataType.DISTANCE_DELTA],
    );
    final activeMinutePoints = await _safeRead(
      startTime: startOfDay,
      endTime: now,
      types: const [HealthDataType.EXERCISE_TIME],
    );
    final bloodOxygenPoints = await _safeRead(
      startTime: yesterday,
      endTime: now,
      types: const [HealthDataType.BLOOD_OXYGEN],
    );
    final weightPoints = await _safeRead(
      startTime: lastWeek,
      endTime: now,
      types: const [HealthDataType.WEIGHT],
    );
    final hydrationPoints = await _safeRead(
      startTime: startOfDay,
      endTime: now,
      types: const [HealthDataType.WATER],
    );
    final sleepPoints = await _safeRead(
      startTime: yesterday,
      endTime: now,
      types: _sleepTypes,
    );

    return WearableSnapshot(
      connected: true,
      heartRate: _latestNumeric(heartRatePoints)?.round(),
      steps: steps,
      caloriesBurned: _sumNumeric(caloriePoints),
      distanceMeters: _sumNumeric(distancePoints),
      activeMinutes: _sumNumeric(activeMinutePoints)?.round(),
      bloodOxygen: _latestNumeric(bloodOxygenPoints),
      weightKg: _latestNumeric(weightPoints),
      hydrationLiters: _sumNumeric(hydrationPoints),
      sleepMinutes: _sleepDurationMinutes(sleepPoints),
      lastSyncedAt: now,
      statusMessage: 'Connected to Health Connect.',
    );
  }

  Future<void> installOrUpdateHealthConnect() async {
    await _health.installHealthConnect();
  }

  Future<WearableSnapshot?> _healthConnectAvailability() async {
    if (!Platform.isAndroid) return null;

    final status = await _health.getHealthConnectSdkStatus();
    if (status == HealthConnectSdkStatus.sdkAvailable) return null;

    return WearableSnapshot(
      connected: false,
      statusMessage: switch (status) {
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
          'Install or update Health Connect, then grant app permissions.',
        _ => 'Health Connect is not available on this device.',
      },
    );
  }

  Future<List<HealthDataPoint>> _safeRead({
    required DateTime startTime,
    required DateTime endTime,
    required List<HealthDataType> types,
  }) async {
    try {
      return await _health.getHealthDataFromTypes(
        types: types,
        startTime: startTime,
        endTime: endTime,
      );
    } catch (_) {
      return const [];
    }
  }

  double? _latestNumeric(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;

    final sorted = [...points]..sort((a, b) => b.dateTo.compareTo(a.dateTo));
    for (final point in sorted) {
      final value = point.value;
      if (value is NumericHealthValue) {
        return value.numericValue.toDouble();
      }
    }
    return null;
  }

  double? _sumNumeric(List<HealthDataPoint> points) {
    var total = 0.0;
    var found = false;
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) {
        total += value.numericValue.toDouble();
        found = true;
      }
    }
    return found ? total : null;
  }

  int? _sleepDurationMinutes(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;
    var totalMinutes = 0;
    for (final point in points) {
      totalMinutes += point.dateTo.difference(point.dateFrom).inMinutes;
    }
    return totalMinutes == 0 ? null : totalMinutes;
  }
}
