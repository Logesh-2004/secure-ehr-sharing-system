import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication auth = LocalAuthentication();

  Future<bool> authenticate({
    String reason = 'Verify your identity before scanning patient QR',
  }) async {
    final canCheck = await auth.canCheckBiometrics;
    final supported = await auth.isDeviceSupported();
    final biometrics = await auth.getAvailableBiometrics();

    if (!canCheck || !supported || biometrics.isEmpty) {
      return false;
    }

    return auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }
}
