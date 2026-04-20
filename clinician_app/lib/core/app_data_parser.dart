import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class AppDataParser {
  const AppDataParser._();

  static DateTime? parseDateTime(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return _fromEpoch(value);
    if (value is double) return _fromEpoch(value.toInt());
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return null;

      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;

      final epoch = int.tryParse(raw);
      if (epoch != null) return _fromEpoch(epoch);

      final normalized = raw.replaceAll('/', '-');
      return DateTime.tryParse(normalized);
    }
    return null;
  }

  static Uint8List? parseBytes(Object? value) {
    if (value == null) return null;
    if (value is Blob) return value.bytes;
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is List<dynamic>) {
      final ints = value.whereType<int>().toList();
      return ints.isEmpty ? null : Uint8List.fromList(ints);
    }
    if (value is String) {
      final payload = value.startsWith('data:') && value.contains(',')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      try {
        return base64Decode(payload);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static int parseInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static String stringValue(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String prettifyKey(String key) {
    final normalized = key
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .trim();

    if (normalized.isEmpty) return key;
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  static DateTime? _fromEpoch(int value) {
    try {
      final isSecondsPrecision = value.abs() < 100000000000;
      final millis = isSecondsPrecision ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return null;
    }
  }
}
