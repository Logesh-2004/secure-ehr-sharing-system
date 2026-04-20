import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/auth_service.dart';
import '../../core/firebase_service.dart';
import '../../widgets/app_surfaces.dart';
import '../../widgets/custom_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final bloodController = TextEditingController();
  final allergyController = TextEditingController();
  final chronicController = TextEditingController();
  final emergencyController = TextEditingController();

  final authService = AuthService();
  final firebase = FirebaseService();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    ageController.dispose();
    bloodController.dispose();
    allergyController.dispose();
    chronicController.dispose();
    emergencyController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = authService.currentUser?.uid;
    if (uid == null) return;

    final profile = await firebase.profileDoc(uid).get();
    Map<String, dynamic>? data = profile.data();

    if (data == null) {
      final legacy = await firebase.userDoc(uid).get();
      data = legacy.data()?['profile'] as Map<String, dynamic>?;
    }

    if (!mounted || data == null) return;
    setState(() {
      nameController.text = data?['name'] as String? ?? '';
      ageController.text = data?['age']?.toString() ?? '';
      bloodController.text = data?['bloodGroup'] as String? ?? '';
      allergyController.text = data?['allergies'] as String? ?? '';
      chronicController.text = data?['chronicConditions'] as String? ?? '';
      emergencyController.text = data?['emergencyContact'] as String? ?? '';
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = authService.currentUser;
    if (user == null) return;

    setState(() => isLoading = true);

    final profile = {
      'name': nameController.text.trim(),
      'age': ageController.text.trim(),
      'bloodGroup': bloodController.text.trim(),
      'allergies': allergyController.text.trim(),
      'chronicConditions': chronicController.text.trim(),
      'emergencyContact': emergencyController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await firebase.userDoc(user.uid).set({
        'email': user.email,
        'patientId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await firebase.profileDoc(user.uid).set(profile, SetOptions(merge: true));
      await firebase.emergencyDoc(user.uid).set({
        'bloodGroup': bloodController.text.trim(),
        'allergies': allergyController.text.trim(),
        'emergencyContact': emergencyController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved securely')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientId = authService.currentUser?.uid ?? 'Unavailable';

    return Scaffold(
      appBar: AppBar(title: const Text('Patient Profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final fieldWidth = wide
                  ? (constraints.maxWidth - 56) / 2
                  : constraints.maxWidth;

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  GradientHeroCard(
                    badge: 'Profile & Emergency Data',
                    title:
                        'Keep your care details ready before every QR share.',
                    subtitle:
                        'Accurate blood group, allergy, and emergency contact details help clinicians respond quickly.',
                    icon: Icons.person_pin_circle_outlined,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SelectableText(
                        'Patient ID: $patientId',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          title: 'Health Profile',
                          subtitle:
                              'These details also feed your emergency access card.',
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: fieldWidth,
                              child: _buildField('Full Name', nameController),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _buildField(
                                'Age',
                                ageController,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _buildField(
                                'Blood Group',
                                bloodController,
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _buildField(
                                'Emergency Contact',
                                emergencyController,
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _buildField(
                                'Allergies',
                                allergyController,
                                maxLines: 3,
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: _buildField(
                                'Chronic Conditions',
                                chronicController,
                                maxLines: 3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        CustomButton(
                          label: 'Save Profile',
                          icon: Icons.verified_user_outlined,
                          isLoading: isLoading,
                          onPressed: _saveProfile,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: (value) =>
          value == null || value.trim().isEmpty ? 'Required field' : null,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}
