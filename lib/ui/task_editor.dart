import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../data/task.dart';
import '../parse/quick_add.dart';
import '../util/format.dart';
import '../util/keyboard.dart';
import 'theme.dart';
import 'time_picker_sheet.dart';

class TaskEditorResult {
  const TaskEditorResult.save(Task value) : task = value, deleted = false;

  const TaskEditorResult.delete() : task = null, deleted = true;

  final Task? task;
  final bool deleted;
}

class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({super.key, required this.initialDate, this.task});

  final DateTime initialDate;
  final Task? task;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final FocusNode _notesFocus;
  late DateTime _date;
  String? _time;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '')
      ..addListener(_onTitleChanged);
    _notesController = TextEditingController(text: widget.task?.notes ?? '');
    _notesFocus = FocusNode();
    _date = widget.task?.date ?? dateOnly(widget.initialDate);
    _time = widget.task?.scheduledTime;
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onTitleChanged)
      ..dispose();
    _notesController.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _onTitleChanged() => setState(() {});

  Future<void> _pickDate() async {
    final parsed = parseQuickAdd(_titleController.text);
    if (parsed.dateFound) {
      _titleController.text = stripDatePhrase(_titleController.text);
      _titleController.selection = TextSelection.collapsed(
        offset: _titleController.text.length,
      );
      _date = parsed.date;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today().subtract(const Duration(days: 3650)),
      lastDate: today().add(const Duration(days: 3650)),
      helpText: 'Pilih tanggal',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null) {
      setState(() => _date = dateOnly(picked));
    }
  }

  Future<void> _pickTime() async {
    final parsed = parseQuickAdd(_titleController.text);
    if (parsed.timeFound) {
      _titleController.text = stripTimePhrase(_titleController.text);
      _titleController.selection = TextSelection.collapsed(
        offset: _titleController.text.length,
      );
      _time = parsed.time;
    }
    final initial = _time == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(
            hour: int.tryParse(_time!.split(':').first) ?? 9,
            minute: int.tryParse(_time!.split(':').last) ?? 0,
          );
    final picked = await showTimePickerSheet(context, initial: initial);
    if (picked != null) {
      final value =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() => _time = value);
    }
  }

  void _save() {
    final raw = _titleController.text.trim();
    if (raw.isEmpty) return;

    final parsed = parseQuickAdd(raw);
    final title = parsed.title.isEmpty ? raw : parsed.title;
    final finalDate = parsed.dateFound ? parsed.date : _date;
    final finalTime = parsed.timeFound ? parsed.time : _time;
    final notes = _notesController.text.trim();

    final task = Task(
      id: widget.task?.id ?? const Uuid().v4(),
      title: title,
      scheduledDate: dateKey(finalDate),
      scheduledTime: finalTime,
      notes: notes.isEmpty ? null : notes,
      isDone: widget.task?.isDone ?? false,
      createdAt:
          widget.task?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );

    Navigator.of(context).pop(TaskEditorResult.save(task));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final parsed = parseQuickAdd(_titleController.text);
    final canSave = _titleController.text.trim().isNotEmpty;
    final isEditing = widget.task != null;
    final effectiveDate = parsed.dateFound ? parsed.date : _date;
    final effectiveTime = parsed.timeFound ? parsed.time : _time;

    return Container(
      decoration: BoxDecoration(
        color: EsokColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 10, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: EsokColors.handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEditing ? 'Ubah tugas' : 'Tugas baru',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.01,
                      color: EsokColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                  color: EsokColors.muted,
                  tooltip: 'Tutup',
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onTapAlwaysCalled: true,
              onTap: () => showSoftKeyboard(),
              onSubmitted: (_) => _save(),
              style: TextStyle(fontSize: 17, color: EsokColors.ink),
              decoration: _fieldDecoration(hint: 'Apa yang perlu dikerjakan?'),
            ),
            if (parsed.dateFound || parsed.timeFound)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  [
                    if (parsed.dateFound) positionLabel(parsed.date),
                    if (parsed.timeFound) timeText(parsed.time),
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: EsokColors.accent,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _PickerChip(
                    icon: Icons.calendar_today_outlined,
                    label: dateTitle(effectiveDate),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickerChip(
                    icon: Icons.schedule,
                    label: effectiveTime == null
                        ? 'Tambah jam'
                        : timeText(effectiveTime),
                    muted: effectiveTime == null,
                    onTap: _pickTime,
                    onClear: effectiveTime == null
                        ? null
                        : () {
                            if (parsed.timeFound) {
                              _titleController.text = stripTimePhrase(
                                _titleController.text,
                              );
                              _titleController.selection =
                                  TextSelection.collapsed(
                                    offset: _titleController.text.length,
                                  );
                            }
                            setState(() => _time = null);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              focusNode: _notesFocus,
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onTapAlwaysCalled: true,
              onTap: () => showSoftKeyboard(focusNode: _notesFocus),
              style: TextStyle(fontSize: 15, color: EsokColors.ink),
              decoration: _fieldDecoration(hint: 'Catatan (opsional)'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: EsokColors.accent,
                  disabledBackgroundColor: const Color(0xFFD8CFC6),
                  foregroundColor: EsokColors.fabText,
                  disabledForegroundColor: EsokColors.fabText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Simpan'),
              ),
            ),
            if (isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(const TaskEditorResult.delete()),
                  style: TextButton.styleFrom(
                    foregroundColor: EsokColors.muted,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('Hapus tugas'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: EsokColors.muted, fontSize: 16),
      filled: true,
      fillColor: EsokColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: EsokColors.ink, width: 1.5),
      ),
    );
  }
}

class _PickerChip extends StatelessWidget {
  const _PickerChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.muted = false,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EsokColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 16, color: EsokColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: muted ? EsokColors.muted : EsokColors.ink,
                    ),
                  ),
                ),
                if (onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: EsokColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
