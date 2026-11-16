import 'package:material_ui/material_ui.dart';

import '../update/update_checker.dart';
import 'theme.dart';

Future<void> showUpdateAvailable(
  BuildContext context,
  UpdateInfo info,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentMaterialBanner();
  await UpdateChecker.markPrompted(info.version);
  if (!context.mounted) return;

  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: EsokColors.surface,
      dividerColor: EsokColors.line,
      leading: Icon(
        Icons.system_update_alt,
        size: 22,
        color: EsokColors.accent,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Versi ${info.version} tersedia',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: EsokColors.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Kamu memakai ${info.currentVersion}. Buka halaman rilis '
            'untuk mengunduh APK terbaru.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: EsokColors.muted,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            messenger.hideCurrentMaterialBanner();
            final opened = await UpdateChecker.openRelease(info.url);
            if (!opened && context.mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Tidak bisa membuka browser.'),
                ),
              );
            }
          },
          child: const Text('Lihat rilis'),
        ),
        TextButton(
          onPressed: () => messenger.hideCurrentMaterialBanner(),
          child: const Text('Nanti'),
        ),
      ],
      forceActionsBelow: true,
    ),
  );
}
