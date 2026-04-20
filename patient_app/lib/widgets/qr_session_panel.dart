import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/qr_service.dart';
import '../theme/app_theme.dart';
import 'app_surfaces.dart';

class QrSessionPanel extends StatelessWidget {
  const QrSessionPanel({
    required this.token,
    required this.secondsRemaining,
    required this.title,
    required this.subtitle,
    required this.onRevoke,
    super.key,
  });

  final String token;
  final int secondsRemaining;
  final String title;
  final String subtitle;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = QrService.qrLifetime.inSeconds;
    final progress = (secondsRemaining / totalSeconds).clamp(0.0, 1.0);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: title,
            subtitle: subtitle,
            action: StatusBadge(
              label: secondsRemaining > 0 ? 'Active' : 'Expired',
              color: secondsRemaining > 0 ? AppTheme.accent : AppTheme.danger,
              icon: secondsRemaining > 0
                  ? Icons.check_circle_outline
                  : Icons.timer_off_outlined,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.primary.withOpacity(0.08)),
              ),
              child: QrImageView(data: token, size: 220),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Expires in $secondsRemaining seconds',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: onRevoke,
                icon: const Icon(Icons.block_outlined),
                label: const Text('Revoke'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppTheme.primary.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.25 ? AppTheme.accent : AppTheme.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
