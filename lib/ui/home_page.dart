import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:home_widget/home_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../data/task.dart';
import '../notify/notifier.dart';
import '../state/settings_store.dart';
import '../state/task_store.dart';
import '../update/update_checker.dart';
import '../util/format.dart';
import '../util/sound_fx.dart';
import '../widget/widget_sync.dart';
import 'calendar_sheet.dart';
import 'chevron.dart';
import 'day_money_section.dart';
import 'patch_notes.dart';
import 'task_editor.dart';
import 'theme.dart';
import 'tx_editor_page.dart';
import 'update_banner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenMoney});

  final VoidCallback? onOpenMoney;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _basePage = 10000;
  static const _settingsChannel = MethodChannel('esok/settings');

  late final PageController _controller;
  StreamSubscription<Uri?>? _widgetClicks;
  Timer? _updateTimer;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _basePage);
    WidgetsBinding.instance.addObserver(this);
    _widgetClicks = HomeWidget.widgetClicked.listen(_openFromWidget);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TaskNotifier.instance.requestPermissions().catchError((Object error) {
        debugPrint('Notification permission request failed: $error');
      });
      HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
        if (mounted) _openFromWidget(uri);
      });
      _updateTimer = Timer(const Duration(seconds: 2), _checkForUpdate);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();
    _updateTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_checkForUpdate());
    final store = context.read<TaskStore>();
    WidgetSync.drainPendingToggles(store).then((changed) async {
      if (changed) await WidgetSync.push();
      await store.refresh();
    });
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final result = await UpdateChecker.check();
      if (!mounted || result.update == null) return;
      await showUpdateAvailable(context, result.update!);
    } finally {
      _checkingUpdate = false;
    }
  }

  DateTime _dateForPage(int page) =>
      today().add(Duration(days: page - _basePage));

  int _pageForDate(DateTime date) => _basePage + daysBetween(today(), date);

  Future<void> _jumpTo(DateTime date) async {
    final page = _pageForDate(date).clamp(0, _basePage * 2);
    if (!_controller.hasClients) {
      await context.read<TaskStore>().selectDate(date);
      return;
    }
    await _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openCalendar() async {
    final store = context.read<TaskStore>();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (context) => CalendarSheet(initialDate: store.selectedDate),
    );
    if (picked != null) {
      await _jumpTo(picked);
    }
  }

  Future<void> _openEditor({Task? task, DateTime? date}) async {
    final store = context.read<TaskStore>();
    final result = await showModalBottomSheet<TaskEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (context) =>
          TaskEditorSheet(task: task, initialDate: date ?? store.selectedDate),
    );
    if (result == null || !mounted) return;

    if (result.deleted) {
      if (task == null) return;
      await store.delete(task.id);
      await TaskNotifier.instance.cancel(task.id);
      await WidgetSync.push();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tugas dihapus.'),
          action: SnackBarAction(
            label: 'Urungkan',
            textColor: const Color(0xFFE08A4B),
            onPressed: () async {
              await store.restore(task);
              await TaskNotifier.instance.schedule(task);
              await WidgetSync.push();
            },
          ),
        ),
      );
      return;
    }

    final saved = result.task;
    if (saved == null) return;

    final isNew = task == null;
    if (isNew) {
      await store.add(saved);
      await TaskNotifier.instance.schedule(saved);
    } else {
      await store.update(saved);
      await TaskNotifier.instance.reschedule(saved);
    }
    await WidgetSync.push();
    if (!mounted) return;
    await _jumpTo(saved.date);
  }

  Future<void> _toggle(Task task) async {
    final store = context.read<TaskStore>();
    final settings = context.read<SettingsStore>();
    final updated = await store.toggle(task);
    if (updated.isDone) {
      final dayTasks = await store.tasksFor(updated.date);
      final allDone =
          dayTasks.isNotEmpty && dayTasks.every((item) => item.isDone);
      if (settings.soundEnabled) {
        SoundFx.play(allDone ? settings.soundComplete : settings.soundCheck);
      }
      await TaskNotifier.instance.cancel(task.id);
    } else {
      if (settings.soundEnabled) SoundFx.play(settings.soundUncheck);
      await TaskNotifier.instance.schedule(updated);
    }
    await WidgetSync.push();
  }

  Future<void> _openFromWidget(Uri? uri) async {
    if (uri == null || uri.scheme != 'jadwal') return;

    if (uri.host == 'money') {
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'new') {
        if (!mounted) return;
        await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => TxEditorPage(
              initialDate: today(),
              initialKind: 'expense',
            ),
          ),
        );
      } else {
        widget.onOpenMoney?.call();
      }
      return;
    }

    if (uri.host == 'day') {
      if (uri.pathSegments.isEmpty) return;
      final date = DateTime.tryParse(uri.pathSegments.first);
      if (date != null) await _jumpTo(dateOnly(date));
      return;
    }

    if (uri.host != 'task' || uri.pathSegments.isEmpty) return;
    final store = context.read<TaskStore>();
    final task = await store.taskById(uri.pathSegments.first);
    if (task == null || !mounted) return;
    await _jumpTo(task.date);
    if (!mounted) return;
    await _openEditor(task: task);
  }

  Future<void> _openBatterySettings() async {
    try {
      await _settingsChannel.invokeMethod<void>('openBatterySettings');
    } catch (error) {
      debugPrint('openBatterySettings failed: $error');
    }
  }

  Future<void> _pinWidget() async {
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) {
        _showMessage(
          'Launcher ini tidak mendukung pemasangan widget dari aplikasi.',
        );
        return;
      }
      await HomeWidget.requestPinWidget(
        androidName: WidgetSync.androidProvider,
      );
    } catch (error) {
      _showMessage('Widget belum bisa dipasang.');
      debugPrint('requestPinWidget failed: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openReleaseNotes() async {
    var version = '1.1.0';
    var buildNumber = '2';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (error) {
      debugPrint('PackageInfo failed: $error');
    }
    if (!mounted) return;
    await showPatchNotes(context, version: version, buildNumber: buildNumber);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaskStore>();
    final selected = store.selectedDate;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: EsokColors.canvas,
        systemNavigationBarDividerColor: EsokColors.canvas,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 10, 0),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/brand/esok-wordmark.svg',
                      height: 26,
                      colorFilter: ColorFilter.mode(
                        EsokColors.ink,
                        BlendMode.srcIn,
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Pengaturan',
                      icon: Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: EsokColors.muted,
                      ),
                      color: EsokColors.surface,
                      surfaceTintColor: Colors.transparent,
                      onSelected: (value) {
                        if (value == 'alarms') {
                          TaskNotifier.instance.requestExactAlarms();
                        } else if (value == 'battery') {
                          _openBatterySettings();
                        } else if (value == 'widget') {
                          _pinWidget();
                        } else if (value == 'release_notes') {
                          _openReleaseNotes();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'alarms',
                          child: Text('Alarm & pengingat'),
                        ),
                        PopupMenuItem(
                          value: 'battery',
                          child: Text('Baterai tanpa batas'),
                        ),
                        PopupMenuItem(
                          value: 'widget',
                          child: Text('Pasang widget'),
                        ),
                        PopupMenuItem(
                          value: 'release_notes',
                          child: Text('Catatan rilis'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _DateNav(
                  date: selected,
                  count: store.tasks.length,
                  canGoBack: store.canGoPrevious,
                  onBack: () =>
                      _jumpTo(selected.subtract(const Duration(days: 1))),
                  onForward: () =>
                      _jumpTo(selected.add(const Duration(days: 1))),
                  onTapDate: _openCalendar,
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _basePage * 2 + 1,
                  onPageChanged: (index) {
                    context.read<TaskStore>().selectDate(_dateForPage(index));
                  },
                  itemBuilder: (context, index) {
                    final date = _dateForPage(index);
                    return _DayPane(
                      key: ValueKey(index),
                      date: date,
                      revision: store.revision,
                      atEarliest: date == store.earliestAllowedDate,
                      onToggle: _toggle,
                      onOpen: (task) => _openEditor(task: task),
                      onAdd: () => _openEditor(date: date),
                      onJumpToday: () => _jumpTo(today()),
                      onJumpNext: () =>
                          _jumpTo(date.add(const Duration(days: 1))),
                      onOpenMoney: widget.onOpenMoney,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: FloatingActionButton(
            onPressed: () => _openEditor(date: store.selectedDate),
            backgroundColor: EsokColors.accent,
            foregroundColor: EsokColors.fabText,
            elevation: 2,
            shape: const CircleBorder(),
            tooltip: 'Tambah tugas',
            child: const Icon(Icons.add, size: 24),
          ),
        ),
      ),
    );
  }
}

class _DateNav extends StatelessWidget {
  const _DateNav({
    required this.date,
    required this.count,
    required this.canGoBack,
    required this.onBack,
    required this.onForward,
    required this.onTapDate,
  });

  final DateTime date;
  final int count;
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onTapDate;

  @override
  Widget build(BuildContext context) {
    final sub = '${weekdayName(date)} · ${taskCountLabel(count)}';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          _NavButton(left: true, enabled: canGoBack, onTap: onBack),
          Expanded(
            child: InkWell(
              onTap: onTapDate,
              borderRadius: BorderRadius.circular(11),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  children: [
                    Text(
                      positionLabel(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.09,
                        color: EsokColors.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateTitle(date),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        letterSpacing: -0.02,
                        color: EsokColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: EsokColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _NavButton(left: false, onTap: onForward),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.left,
    required this.onTap,
    this.enabled = true,
  });

  final bool left;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.32,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: EsokChevron(left: left, size: 18)),
        ),
      ),
    );
  }
}

class _DayData {
  const _DayData({required this.tasks, required this.nextDayTasks});

  final List<Task> tasks;
  final List<Task> nextDayTasks;
}

class _DayPane extends StatefulWidget {
  const _DayPane({
    super.key,
    required this.date,
    required this.revision,
    required this.atEarliest,
    required this.onToggle,
    required this.onOpen,
    required this.onAdd,
    required this.onJumpToday,
    required this.onJumpNext,
    this.onOpenMoney,
  });

  final DateTime date;
  final int revision;
  final bool atEarliest;
  final Future<void> Function(Task) onToggle;
  final ValueChanged<Task> onOpen;
  final VoidCallback onAdd;
  final VoidCallback onJumpToday;
  final VoidCallback onJumpNext;
  final VoidCallback? onOpenMoney;

  @override
  State<_DayPane> createState() => _DayPaneState();
}

class _DayPaneState extends State<_DayPane> {
  late Future<_DayData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DayPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _load();
    }
  }

  void _load() {
    final store = context.read<TaskStore>();
    _future =
        Future.wait([
          store.tasksFor(widget.date),
          store.tasksFor(widget.date.add(const Duration(days: 1))),
        ]).then((results) {
          return _DayData(tasks: results[0], nextDayTasks: results[1]);
        });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DayData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const SizedBox.shrink();
        }
        final tasks = data.tasks;
        final undone = tasks.where((task) => !task.isDone).length;
        final isPast = widget.date.isBefore(today());

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 140),
          children: [
            if (tasks.isEmpty) _EmptyState(onAdd: widget.onAdd),
            for (var index = 0; index < tasks.length; index++)
              _TaskRow(
                task: tasks[index],
                showDivider: index != tasks.length - 1,
                onToggle: () => widget.onToggle(tasks[index]),
                onOpen: () => widget.onOpen(tasks[index]),
              ),
            if (isPast && undone > 0) ...[
              const SizedBox(height: 20),
              _LateNote(count: undone),
            ],
            const SizedBox(height: 22),
            _BottomRow(
              date: widget.date,
              nextDayTasks: data.nextDayTasks,
              atEarliest: widget.atEarliest,
              onJumpToday: widget.onJumpToday,
              onJumpNext: widget.onJumpNext,
            ),
            const SizedBox(height: 24),
            DayMoneySection(date: widget.date, onOpenMoney: widget.onOpenMoney),
          ],
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.showDivider,
    required this.onToggle,
    required this.onOpen,
  });

  final Task task;
  final bool showDivider;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: 17,
      height: 1.3,
      color: task.isDone ? EsokColors.muted : EsokColors.ink,
      decoration: task.isDone ? TextDecoration.lineThrough : null,
      decorationThickness: 1,
      decorationColor: EsokColors.muted,
    );

    return Column(
      children: [
        Semantics(
          label: '${task.title}, ${task.isDone ? 'selesai' : 'belum selesai'}',
          child: Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 48,
                  height: 64,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutQuart,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: task.isDone
                            ? EsokColors.done
                            : Colors.transparent,
                        border: Border.all(
                          color: task.isDone
                              ? EsokColors.done
                              : EsokColors.muted,
                          width: 1.5,
                        ),
                      ),
                      child: task.isDone
                          ? Icon(
                              Icons.check,
                              size: 13,
                              color: EsokColors.fabText,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onOpen,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutQuart,
                            style: titleStyle,
                            child: Text(task.title),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          timeText(task.scheduledTime),
                          style: TextStyle(
                            fontSize: 13,
                            color: EsokColors.muted,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _LateNote extends StatelessWidget {
  const _LateNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: EsokColors.lateSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: EsokColors.accent,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            '$count tugas belum dicentang',
            style: TextStyle(fontSize: 12, color: EsokColors.lateInk),
          ),
        ],
      ),
    );
  }
}

class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.date,
    required this.nextDayTasks,
    required this.atEarliest,
    required this.onJumpToday,
    required this.onJumpNext,
  });

  final DateTime date;
  final List<Task> nextDayTasks;
  final bool atEarliest;
  final VoidCallback onJumpToday;
  final VoidCallback onJumpNext;

  @override
  Widget build(BuildContext context) {
    final isToday = date == today();
    final next = date.add(const Duration(days: 1));

    if (atEarliest) {
      return _BottomCard(
        label: 'Tidak ada catatan sebelum ini',
        action: 'KE HARI INI',
        onTap: onJumpToday,
      );
    }

    if (isToday) {
      return _BottomCard(
        label:
            'Besok, ${shortDateTitle(next)} · ${taskCountLabel(nextDayTasks.length)}',
        boldPrefix: 'Besok, ${shortDateTitle(next)}',
        action: 'LIHAT',
        onTap: onJumpNext,
      );
    }

    return _BottomCard(
      label:
          '${weekdayName(next)}, ${shortDateTitle(next)} · ${taskCountLabel(nextDayTasks.length)}',
      action: 'KE HARI INI',
      onTap: onJumpToday,
    );
  }
}

class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.label,
    required this.action,
    required this.onTap,
    this.boldPrefix,
  });

  final String label;
  final String action;
  final VoidCallback onTap;
  final String? boldPrefix;

  @override
  Widget build(BuildContext context) {
    final prefix = boldPrefix;
    return Material(
      color: EsokColors.soft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: EsokColors.inkSoft,
                    ),
                    children: [
                      if (prefix != null)
                        TextSpan(
                          text: prefix,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      if (prefix != null)
                        TextSpan(text: label.substring(prefix.length)),
                      if (prefix == null) TextSpan(text: label),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$action ›',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.03,
                  color: EsokColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Belum ada jadwal.',
              style: TextStyle(fontSize: 14, color: EsokColors.muted),
            ),
          ),
          TextButton(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              foregroundColor: EsokColors.accent,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Tambah satu'),
          ),
        ],
      ),
    );
  }
}
