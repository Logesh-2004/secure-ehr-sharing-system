class UserModel {
  const UserModel({
    required this.uid,
    required this.email,
    this.name = '',
    this.age = '',
    this.bloodGroup = '',
    this.allergies = '',
    this.chronicConditions = '',
    this.emergencyContact = '',
  });

  final String uid;
  final String email;
  final String name;
  final String age;
  final String bloodGroup;
  final String allergies;
  final String chronicConditions;
  final String emergencyContact;

  Map<String, dynamic> toProfileMap() {
    return {
      'name': name,
      'age': age,
      'bloodGroup': bloodGroup,
      'allergies': allergies,
      'chronicConditions': chronicConditions,
      'emergencyContact': emergencyContact,
    };
  }

  factory UserModel.fromProfile({
    required String uid,
    required String email,
    required Map<String, dynamic> data,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      name: data['name'] as String? ?? '',
      age: data['age']?.toString() ?? '',
      bloodGroup: data['bloodGroup'] as String? ?? '',
      allergies: data['allergies'] as String? ?? '',
      chronicConditions: data['chronicConditions'] as String? ?? '',
      emergencyContact: data['emergencyContact'] as String? ?? '',
    );
  }
}
