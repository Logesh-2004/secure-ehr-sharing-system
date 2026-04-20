import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/auth_service.dart';
import '../../core/biometric_service.dart';
import '../../core/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_surfaces.dart';
import '../patient_view/patient_view_screen.dart';

enum ScannerStage {
  locked,
  initializingCamera,
  cameraReady,
  scanning,
  qrDetected,
  validatingToken,
  fetchingPatientData,
  accessGranted,
  qrExpired,
  invalidToken,
  revokedAccess,
  networkError,
  cameraPermissionDenied,
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final firebase = FirebaseService();
  final auth = AuthService();
  final biometric = BiometricService();

  bool validating = false;
  bool scannerUnlocked = false;
  String? lastScannedToken;
  ScannerStage stage = ScannerStage.locked;
  String statusDetail = 'Verify biometrics to unlock QR scanning.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_handleControllerState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockScanner());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_handleControllerState);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!scannerUnlocked || validating) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (_shouldResumeScanner) {
          unawaited(_startScanner(resetLastToken: false));
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(controller.stop());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  bool get _shouldResumeScanner {
    return stage == ScannerStage.scanning ||
        stage == ScannerStage.cameraReady ||
        stage == ScannerStage.initializingCamera;
  }

  void _handleControllerState() {
    if (!mounted) return;

    final error = controller.value.error;
    if (error != null) {
      if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        _setStage(
          ScannerStage.cameraPermissionDenied,
          'Allow camera access to continue secure scanning.',
        );
      } else {
        _setStage(
          ScannerStage.networkError,
          error.errorDetails?.message ??
              'Camera initialization failed. Retry the scanner.',
        );
      }
    }
  }

  Future<void> _unlockScanner() async {
    _setStage(
      ScannerStage.locked,
      'Verify biometrics before scanning patient QR codes.',
    );

    final allowed = await biometric.authenticate(
      reason: 'Verify biometrics before scanning patient QR',
    );
    if (!mounted) return;

    if (!allowed) {
      _setStage(
        ScannerStage.locked,
        'Biometric verification is required before scanning.',
      );
      return;
    }

    setState(() => scannerUnlocked = true);
    await _startScanner();
  }

  Future<void> _startScanner({bool resetLastToken = true}) async {
    if (resetLastToken) {
      lastScannedToken = null;
    }

    _setStage(
      ScannerStage.initializingCamera,
      'Preparing camera and autofocus for secure QR detection.',
    );

    try {
      await controller.start();
      if (!mounted) return;
      setState(() => validating = false);
      _setStage(ScannerStage.cameraReady, 'Camera ready.');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      if (controller.value.isRunning && !validating) {
        _setStage(
          ScannerStage.scanning,
          'Scanning for QR. Align the code inside the guide box.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      _handleScannerError(error);
    }
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (validating || !scannerUnlocked) return;

    String? rawToken;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        rawToken = value;
        break;
      }
    }

    if (rawToken == null || rawToken == lastScannedToken) return;
    lastScannedToken = rawToken;

    final clinicianUid = auth.currentUser?.uid;
    if (clinicianUid == null) return;

    setState(() => validating = true);
    _setStage(
      ScannerStage.qrDetected,
      'QR detected. Pausing scanner while validation begins.',
    );
    await controller.stop();

    try {
      final result = await firebase.validateAndFetchPatientData(
        rawToken: rawToken,
        clinicianUid: clinicianUid,
        onProgress: (progress) {
          if (!mounted) return;
          switch (progress) {
            case PatientAccessProgress.validatingToken:
              _setStage(
                ScannerStage.validatingToken,
                'Validating token integrity and session status.',
              );
              break;
            case PatientAccessProgress.fetchingPatientData:
              _setStage(
                ScannerStage.fetchingPatientData,
                'Fetching patient data and authorized file details.',
              );
              break;
            case PatientAccessProgress.loggingAccess:
              _setStage(
                ScannerStage.accessGranted,
                'Access granted. Preparing the patient view.',
              );
              break;
          }
        },
      );

      if (!mounted) return;
      _setStage(
        ScannerStage.accessGranted,
        'Access granted. Review the patient details, then retry when ready.',
      );

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PatientViewScreen(result: result)),
      );

      if (!mounted) return;
      setState(() => validating = false);
      _setStage(
        ScannerStage.accessGranted,
        'Access granted. Tap retry to scan the next QR.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => validating = false);
      _handleScannerError(error);
    }
  }

  void _handleScannerError(Object error) {
    if (error is TokenValidationException) {
      final message = error.message;
      final lower = message.toLowerCase();
      if (lower.contains('expired')) {
        _setStage(
          ScannerStage.qrExpired,
          'QR expired. Ask the patient to generate a fresh code.',
        );
      } else if (lower.contains('revoked')) {
        _setStage(
          ScannerStage.revokedAccess,
          'This session was revoked and can no longer be used.',
        );
      } else {
        _setStage(ScannerStage.invalidToken, message);
      }
    } else if (error is FirebaseException) {
      _setStage(
        ScannerStage.networkError,
        'Network error while validating access. Check connectivity and retry.',
      );
    } else if (error is MobileScannerException) {
      if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        _setStage(
          ScannerStage.cameraPermissionDenied,
          'Camera permission denied. Enable it in settings and retry.',
        );
      } else {
        _setStage(
          ScannerStage.networkError,
          error.errorDetails?.message ??
              'Scanner error. Retry the camera when ready.',
        );
      }
    } else {
      _setStage(ScannerStage.networkError, error.toString());
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(statusDetail)));
  }

  void _setStage(ScannerStage nextStage, String detail) {
    if (!mounted) return;
    setState(() {
      stage = nextStage;
      statusDetail = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Secure QR')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              SectionCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _stageColor(stage).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(_stageIcon(stage), color: _stageColor(stage)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _stageLabel(stage),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              StatusBadge(
                                label: _stageLabel(stage),
                                color: _stageColor(stage),
                                icon: _stageIcon(stage),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            statusDetail,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppTheme.muted),
                          ),
                          if (_showBusyIndicator(stage)) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(minHeight: 6),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ScannerViewport(
                  stage: stage,
                  child: _buildScannerBody(),
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: controller,
                builder: (context, scannerState, _) {
                  final canUseCameraControls = scannerState.isInitialized;
                  final torchOn = scannerState.torchState == TorchState.on;

                  return Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: validating
                              ? null
                              : scannerUnlocked
                              ? () => _startScanner()
                              : _unlockScanner,
                          icon: Icon(
                            scannerUnlocked
                                ? Icons.refresh_outlined
                                : Icons.fingerprint,
                          ),
                          label: Text(
                            scannerUnlocked ? 'Retry Scan' : 'Verify & Scan',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: canUseCameraControls
                            ? () => controller.switchCamera()
                            : null,
                        icon: const Icon(Icons.cameraswitch_outlined),
                        tooltip: 'Switch camera',
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: canUseCameraControls
                            ? () => controller.toggleTorch()
                            : null,
                        icon: Icon(
                          torchOn
                              ? Icons.flash_on_outlined
                              : Icons.flash_off_outlined,
                        ),
                        tooltip: 'Toggle torch',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerBody() {
    if (!scannerUnlocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint, size: 72, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Verify biometrics to unlock QR scanning.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final scanWindow = _scanWindow(constraints.biggest);
        return MobileScanner(
          controller: controller,
          scanWindow: scanWindow,
          onDetect: _handleDetection,
          errorBuilder: (context, error, _) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorDetails?.message ?? error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                ),
              ),
            );
          },
          overlayBuilder: (context, boxConstraints) {
            return _ScannerOverlay(
              scanWindow: _scanWindow(boxConstraints.biggest),
            );
          },
          placeholderBuilder: (context, _) => const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  Rect _scanWindow(Size size) {
    final width = size.width * 0.74;
    final height = width;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 8),
      width: width,
      height: height,
    );
  }

  bool _showBusyIndicator(ScannerStage stage) {
    return stage == ScannerStage.initializingCamera ||
        stage == ScannerStage.qrDetected ||
        stage == ScannerStage.validatingToken ||
        stage == ScannerStage.fetchingPatientData ||
        stage == ScannerStage.scanning;
  }

  IconData _stageIcon(ScannerStage stage) {
    switch (stage) {
      case ScannerStage.locked:
        return Icons.fingerprint;
      case ScannerStage.initializingCamera:
        return Icons.camera_alt_outlined;
      case ScannerStage.cameraReady:
        return Icons.verified_outlined;
      case ScannerStage.scanning:
        return Icons.qr_code_scanner;
      case ScannerStage.qrDetected:
        return Icons.qr_code_2_outlined;
      case ScannerStage.validatingToken:
        return Icons.verified_user_outlined;
      case ScannerStage.fetchingPatientData:
        return Icons.cloud_download_outlined;
      case ScannerStage.accessGranted:
        return Icons.lock_open_outlined;
      case ScannerStage.qrExpired:
        return Icons.schedule_outlined;
      case ScannerStage.invalidToken:
        return Icons.error_outline;
      case ScannerStage.revokedAccess:
        return Icons.block_outlined;
      case ScannerStage.networkError:
        return Icons.wifi_off_outlined;
      case ScannerStage.cameraPermissionDenied:
        return Icons.no_photography_outlined;
    }
  }

  Color _stageColor(ScannerStage stage) {
    switch (stage) {
      case ScannerStage.accessGranted:
      case ScannerStage.cameraReady:
      case ScannerStage.scanning:
        return AppTheme.accent;
      case ScannerStage.qrExpired:
        return Colors.orange.shade700;
      case ScannerStage.invalidToken:
      case ScannerStage.revokedAccess:
      case ScannerStage.networkError:
      case ScannerStage.cameraPermissionDenied:
        return AppTheme.danger;
      case ScannerStage.locked:
      case ScannerStage.initializingCamera:
      case ScannerStage.qrDetected:
      case ScannerStage.validatingToken:
      case ScannerStage.fetchingPatientData:
        return AppTheme.primary;
    }
  }

  String _stageLabel(ScannerStage stage) {
    switch (stage) {
      case ScannerStage.locked:
        return 'Scanner locked';
      case ScannerStage.initializingCamera:
        return 'Initializing camera...';
      case ScannerStage.cameraReady:
        return 'Camera ready';
      case ScannerStage.scanning:
        return 'Scanning for QR...';
      case ScannerStage.qrDetected:
        return 'QR detected';
      case ScannerStage.validatingToken:
        return 'Validating token...';
      case ScannerStage.fetchingPatientData:
        return 'Fetching patient data...';
      case ScannerStage.accessGranted:
        return 'Access granted';
      case ScannerStage.qrExpired:
        return 'QR expired';
      case ScannerStage.invalidToken:
        return 'Invalid token';
      case ScannerStage.revokedAccess:
        return 'Revoked access';
      case ScannerStage.networkError:
        return 'Network error';
      case ScannerStage.cameraPermissionDenied:
        return 'Camera permission needed';
    }
  }
}

class _ScannerViewport extends StatelessWidget {
  const _ScannerViewport({required this.stage, required this.child});

  final ScannerStage stage;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF081E2E), Color(0xFF103349)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withOpacity(0.18),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.46),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  stage == ScannerStage.scanning
                      ? 'Place the QR inside the guide box'
                      : 'Secure scanning status stays visible here',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.scanWindow});

  final Rect scanWindow;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScannerOverlayPainter(scanWindow: scanWindow),
      child: const SizedBox.expand(),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({required this.scanWindow});

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.42);
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, const Radius.circular(24)),
      );

    canvas.drawPath(
      Path.combine(PathOperation.difference, path, cutout),
      overlayPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(24)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}
