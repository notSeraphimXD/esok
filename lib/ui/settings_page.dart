import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../backup/auto_backup.dart';
import '../data/database.dart';
import '../data/task_dao.dart';
import '../notify/notifier.dart';
import '../state/money_store.dart';
import '../state/settings_store.dart';
import '../update/update_checker.dart';
import '../widget/widget_sync.dart';
import 'data_page.dart';
import 'manage_accounts.dart';
import 'manage_categories.dart';
import 'sound_page.dart';
import 'theme.dart';
import 'update_banner.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _channel = MethodChannel('esok/settings');
  String _version = '—';
  DateTime? _lastBackup;
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    });
    AutoBackup.lastBackupAt().then((value) {
      if (!mounted) return;
      setState(() => _lastBackup = value);
    });
  }

  Future<void> _backupNow() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    final ok = await AutoBackup.runIfChanged(force: true);
    final at = await AutoBackup.lastBackupAt();
    if (!mounted) return;
    setState(() {
      _backupBusy = false;
      _lastBackup = at;
    });
    if (ok) {
      _message('Cadangan tersimpan di Download/Esok');
      return;
    }
    final message = AutoBackup.lastError ?? 'Gagal menulis cadangan.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Simpan manual',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DataPage()),
          ),
        ),
      ),
    );
  }

  String get _backupLabel {
    if (_backupBusy) return 'Menyimpan…';
    final at = _lastBackup;
    if (at == null) return 'Belum ada · ketuk untuk membuat';
    final stamp = DateFormat('d MMM, HH.mm', 'id_ID').format(at);
    return 'Terakhir $stamp · Download/Esok';
  }

  Future<void> _checkForUpdate() async {
    _message('Memeriksa pembaruan…');
    final result = await UpdateChecker.check(force: true);
    if (!mounted) return;
    if (result.update != null) {
      await showUpdateAvailable(context, result.update!);
      return;
    }
    _message(result.error ?? 'Kamu sudah memakai versi terbaru.');
  }

  Future<void> _openLeadDuration() async {
    final settings = context.read<SettingsStore>();
    final value = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (_) => _Sheet(
        title: 'Pengingat awal',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in const [
              (30, '30 menit sebelum tenggat'),
              (60, '1 jam sebelum tenggat'),
              (180, '3 jam sebelum tenggat'),
              (1440, '1 hari sebelum tenggat'),
            ])
              _SheetChoice(
                label: option.$2,
                selected: settings.leadMinutes == option.$1,
                onTap: () => Navigator.of(context).pop(option.$1),
              ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    await context.read<SettingsStore>().setLeadMinutes(value);
    await _reschedule();
  }

  Future<void> _reschedule() async {
    final settings = context.read<SettingsStore>();
    final db = await AppDatabase.open();
    final tasks = await TaskDao(db).all();
    TaskNotifier.instance.configureLead(
      enabled: settings.leadEnabled,
      minutes: settings.leadMinutes,
    );
    await TaskNotifier.instance.configureSound(
      settings.soundReminder.raw ?? 'coin',
    );
    await TaskNotifier.instance.rescheduleAll(tasks);
  }

  Future<void> _toggleLead(bool value) async {
    await context.read<SettingsStore>().setLeadEnabled(value);
    await _reschedule();
  }

  Future<void> _toggleHideAmounts(bool value) async {
    await context.read<SettingsStore>().setHideAmounts(value);
    await WidgetSync.push();
  }

  Future<void> _toggleSoundEnabled(bool value) async {
    await context.read<SettingsStore>().setSoundEnabled(value);
  }

  Future<void> _openExactAlarm() async {
    try {
      await _channel.invokeMethod<void>('openExactAlarmSettings');
    } catch (_) {
      _message('Pengaturan alarm presisi tidak tersedia.');
    }
  }

  Future<void> _editAiKey() async {
    final settings = context.read<SettingsStore>();
    final value = await _promptText(
      title: 'API key Gemini',
      hint: 'Tempel API key dari Google AI Studio',
      initial: settings.aiKey,
      obscure: true,
    );
    if (value == null) return;
    await settings.setAiKey(value.trim());
    if (mounted) {
      _message(
        value.trim().isEmpty
            ? 'API key dihapus.'
            : 'API key disimpan di perangkat ini.',
      );
    }
  }

  Future<void> _editAiModel() async {
    final settings = context.read<SettingsStore>();
    final value = await _promptText(
      title: 'Model Gemini',
      hint: 'gemini-3.5-flash',
      initial: settings.aiModel,
      obscure: false,
    );
    if (value == null) return;
    await settings.setAiModel(value);
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    required String initial,
    required bool obscure,
  }) {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: EsokColors.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: EsokColors.handle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: EsokColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(fontSize: 14, color: EsokColors.ink),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 13, color: EsokColors.muted),
                    filled: true,
                    fillColor: EsokColors.soft,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(controller.text),
                    style: FilledButton.styleFrom(
                      backgroundColor: EsokColors.accent,
                      foregroundColor: EsokColors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    child: const Text('Simpan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _openBattery() async {
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } catch (_) {
      _message('Pengaturan baterai tidak tersedia.');
    }
  }

  Future<void> _showFontLicense() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (context) => _Sheet(
        title: 'Lisensi font',
        child: Text(
          'Astoria digunakan hanya sebagai sumber desain wordmark dan tidak dibundel ke APK. Wordmark di aplikasi adalah jalur vektor.',
          style: TextStyle(
            fontSize: 13,
            height: 1.65,
            color: EsokColors.muted,
          ),
        ),
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String get _leadLabel {
    final settings = context.watch<SettingsStore>();
    if (!settings.leadEnabled) return 'Nonaktif';
    switch (settings.leadMinutes) {
      case 30:
        return '30 menit sebelum tenggat';
      case 180:
        return '3 jam sebelum tenggat';
      case 1440:
        return '1 hari sebelum tenggat';
      default:
        return '1 jam sebelum tenggat';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final store = context.watch<MoneyStore>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    EsokColors.useDark(isDark);
    final expenseCount = store.expenseCategories.length;
    final incomeCount = store.incomeCategories.length;
    final accountCount = store.activeAccounts.length;

    return Scaffold(
      backgroundColor: EsokColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
          children: [
            Text(
              'Setelan',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.02,
                color: EsokColors.ink,
              ),
            ),
            const _SectionLabel('Tampilan'),
            const SizedBox(height: 2),
            Text(
              'Tema',
              style: TextStyle(
                fontSize: 14.5,
                color: EsokColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Ikuti setelan Android secara default',
              style: TextStyle(fontSize: 11, color: EsokColors.muted),
            ),
            const SizedBox(height: 12),
            _ThemeSelector(
              value: settings.themeMode,
              onChanged: (mode) => context
                  .read<SettingsStore>()
                  .setThemeMode(mode),
            ),
            const _SectionLabel('Notifikasi'),
            _SettingsRow(
              title: 'Pengingat awal',
              subtitle: _leadLabel,
              onTap: settings.leadEnabled ? _openLeadDuration : null,
              trailing: _Toggle(
                value: settings.leadEnabled,
                onChanged: _toggleLead,
              ),
            ),
            _SettingsRow(
              title: 'Alarm presisi',
              subtitle: 'Diperlukan agar notifikasi tepat waktu',
              trailing: _Trailing('Atur ›'),
              onTap: _openExactAlarm,
            ),
            _SettingsRow(
              title: 'Optimasi baterai',
              subtitle: 'Agar One UI tidak menahan pengingat',
              trailing: _Trailing('Atur ›'),
              onTap: _openBattery,
            ),
            const _SectionLabel('Suara'),
            _SettingsRow(
              title: 'Efek suara',
              subtitle: 'Bunyi saat saldo berubah',
              trailing: _Toggle(
                value: settings.soundEnabled,
                onChanged: _toggleSoundEnabled,
              ),
            ),
            _SettingsRow(
              title: 'Suara & Notifikasi',
              subtitle: 'Nada pengingat, apresiasi, dan saldo',
              trailing: const _Trailing('›'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SoundPage()),
              ),
            ),
            const _SectionLabel('Data'),
            _SettingsRow(
              title: 'Kategori',
              trailing: _Trailing('$expenseCount · $incomeCount ›'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ManageCategoriesPage(initialKind: 'expense'),
                ),
              ),
            ),
            _SettingsRow(
              title: 'Sumber dana',
              trailing: _Trailing('$accountCount ›'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManageAccountsPage(),
                ),
              ),
            ),
            _SettingsRow(
              title: 'Ekspor & impor',
              trailing: _Trailing('›'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DataPage()),
              ),
            ),
            _SettingsRow(
              title: 'Cadangan otomatis',
              subtitle: _backupLabel,
              trailing: _backupBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const _Trailing('Sekarang ›'),
              onTap: _backupNow,
            ),
            const _SectionLabel('Pindai struk'),
            _SettingsRow(
              title: 'API key Gemini',
              subtitle: settings.aiReady
                  ? 'Tersimpan di perangkat ini'
                  : 'Belum diisi · pakai API key milikmu sendiri',
              trailing: const _Trailing('Atur ›'),
              onTap: _editAiKey,
            ),
            _SettingsRow(
              title: 'Model',
              subtitle: settings.aiModel,
              trailing: const _Trailing('Atur ›'),
              onTap: _editAiModel,
            ),
            const _SectionLabel('Widget'),
            _SettingsRow(
              title: 'Sembunyikan nominal',
              subtitle: 'Berlaku di widget uang',
              trailing: _Toggle(
                value: settings.hideAmounts,
                onChanged: _toggleHideAmounts,
              ),
            ),
            const _SectionLabel('Tentang'),
            _SettingsRow(
              title: 'Versi',
              trailing: _Trailing(_version),
            ),
            _SettingsRow(
              title: 'Periksa pembaruan',
              subtitle: 'Cek versi terbaru di GitHub',
              trailing: const _Trailing('Cek ›'),
              onTap: _checkForUpdate,
            ),
            _SettingsRow(
              title: 'Lisensi font',
              trailing: _Trailing('Astoria · personal ›'),
              onTap: _showFontLicense,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  int get _index => switch (value) {
    ThemeMode.light => 0,
    ThemeMode.system => 1,
    ThemeMode.dark => 2,
  };

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.of(context).disableAnimations;
    final duration = disabled
        ? Duration.zero
        : const Duration(milliseconds: 180);
    const labels = ['Terang', 'Sistem', 'Gelap'];
    const modes = [ThemeMode.light, ThemeMode.system, ThemeMode.dark];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final segment = (width - 8) / 3;
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: EsokColors.soft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutQuint,
                left: 4 + _index * segment,
                top: 4,
                bottom: 4,
                width: segment,
                child: Container(
                  decoration: BoxDecoration(
                    color: EsokColors.ink,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(modes[i]),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i != 1) ...[
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: i == 0
                                        ? const Color(0xFFFAF9F7)
                                        : const Color(0xFF14130F),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: EsokColors.muted.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _index == i
                                      ? EsokColors.canvas
                                      : EsokColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: disabled
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutQuint,
        width: 40,
        height: 23,
        decoration: BoxDecoration(
          color: value ? EsokColors.positive : EsokColors.line,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: disabled
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutQuint,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            decoration: BoxDecoration(
              color: EsokColors.surface,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3314120E),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: EsokColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14.5, color: EsokColors.ink),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: EsokColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  const _Trailing(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 11.5, color: EsokColors.muted),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.09,
          color: EsokColors.muted,
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EsokColors.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: EsokColors.handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: EsokColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SheetChoice extends StatelessWidget {
  const _SheetChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? EsokColors.accent : EsokColors.muted,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? EsokColors.ink : EsokColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
