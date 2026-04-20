import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/biometric_service.dart';
import '../../core/firebase_service.dart';
import '../../core/qr_service.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/qr_session_panel.dart';

class EmergencyTab extends StatefulWidget {
  const EmergencyTab({super.key});

  @override
  State<EmergencyTab> createState() => _EmergencyTabState();
}

class _EmergencyTabState extends State<EmergencyTab> {
  final _formKey = GlobalKey<FormState>();
  final bloodController = TextEditingController();
  final allergyController = TextEditingController();
  final contactController = TextEditingController();

  final auth = AuthService();
  final biometric = BiometricService();
  final firebase = FirebaseService();
  final qrService = QrService();

  String? emergencyToken;
  String? sessionId;
  bool saving = false;
  bool generating = false;
  int secondsRemaining = 0;
  Timer? countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadEmergencyProfile();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    bloodController.dispose();
    allergyController.dispose();
    contactController.dispose();
    super.dispose();
  }

  Future<void> _loadEmergencyProfile() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final doc = await firebase.emergencyDoc(uid).get();
    Map<String, dynamic>? data = doc.data();

    if (data == null) {
      final profileDoc = await firebase.profileDoc(uid).get();
      data = profileDoc.data();
    }

    if (!mounted || data == null) return;
    setState(() {
      bloodController.text = data?['bloodGroup'] as String? ?? '';
      allergyController.text = data?['allergies'] as String? ?? '';
      contactController.text = data?['emergencyContact'] as String? ?? '';
    });
  }

  Future<bool> _saveEmergencyProfile() async {
    if (!_formKey.currentState!.validate()) return false;

    final uid = auth.currentUser?.uid;
    if (uid == null) return false;

    setState(() => saving = true);
    try {
      await firebase.emergencyDoc(uid).set({
        'bloodGroup': bloodController.text.trim(),
        'allergies': allergyController.text.trim(),
        'emergencyContact': contactController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _showMessage('Emergency profile saved.');
      return true;
    } catch (error) {
      _showMessage(error.toString());
      return false;
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _generateEmergencyQr() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    final saved = await _saveEmergencyProfile();
    if (!saved) return;

    final allowed = await biometric.authenticate(
      reason: 'Verify biometrics to generate your emergency QR',
    );
    if (!allowed) {
      _showMessage('Biometric verification is required before generating QR.');
      return;
    }

    setState(() => generating = true);
    try {
      final result = await qrService.createEmergencySession(uid: uid);
      setState(() {
        emergencyToken = result.token;
        sessionId = result.sessionId;
        secondsRemaining = result.expiry
            .difference(DateTime.now())
            .inSeconds
            .clamp(0, 60)
            .toInt();
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
      emergencyToken = null;
      sessionId = null;
      secondsRemaining = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const GradientHeroCard(
            badge: 'Emergency Readiness',
            title: 'Prepare a rapid-access emergency QR before it is needed.',
            subtitle:
                'This bundle is designed for critical moments and should include the essentials a clinician needs immediately.',
            icon: Icons.emergency_outlined,
          ),
          const SizedBox(height: 20),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  title: 'Emergency Data',
                  subtitle:
                      'These fields are stored securely and used when you generate an emergency QR.',
                ),
                const SizedBox(height: 20),
                _field(
                  'Blood Group',
                  bloodController,
                  Icons.bloodtype_outlined,
                ),
                const SizedBox(height: 16),
                _field(
                  'Allergies',
                  allergyController,
                  Icons.warning_amber_outlined,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _field(
                  'Emergency Contact',
                  contactController,
                  Icons.call_outlined,
                ),
                const SizedBox(height: 20),
                CustomButton(
                  label: 'Save Emergency Data',
                  icon: Icons.health_and_safety_outlined,
                  isLoading: saving,
                  onPressed: _saveEmergencyProfile,
                ),
                const SizedBox(height: 12),
                CustomButton(
                  label: 'Verify Biometrics and Generate Emergency QR',
                  icon: Icons.fingerprint,
                  isLoading: generating,
                  onPressed: _generateEmergencyQr,
                ),
              ],
            ),
          ),
          if (emergencyToken != null) ...[
            const SizedBox(height: 20),
            QrSessionPanel(
              token: emergencyToken!,
              secondsRemaining: secondsRemaining,
              title: 'Emergency QR ready',
              subtitle: 'Share only with an active clinician in urgent care.',
              onRevoke: _expireQr,
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Required field' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
