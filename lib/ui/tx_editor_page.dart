import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../ai/receipt_scanner.dart';
import '../data/account.dart';
import '../data/category.dart';
import '../data/money_transaction.dart';
import '../data/task.dart';
import '../state/money_store.dart';
import '../state/settings_store.dart';
import '../util/format.dart';
import '../util/sound_fx.dart';
import 'category_icon.dart';
import 'items_sheet.dart';
import 'manage_accounts.dart';
import 'theme.dart';

class TxEditorPage extends StatefulWidget {
  const TxEditorPage({
    super.key,
    this.transaction,
    this.initialDate,
    this.initialKind = 'expense',
  });

  final MoneyTransaction? transaction;
  final DateTime? initialDate;
  final String initialKind;

  @override
  State<TxEditorPage> createState() => _TxEditorPageState();
}

class _TxEditorPageState extends State<TxEditorPage> {
  late String _kind;
  late DateTime _date;
  int _amount = 0;
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  String? _detail;
  late final TextEditingController _noteController;
  bool _creatingCategory = false;
  final _categoryNameController = TextEditingController();
  String? _categoryError;
  bool _saving = false;
  bool _scanning = false;

  bool get _isEditing => widget.transaction != null;
  bool get _isTransfer => _kind == 'transfer';

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    _kind = transaction?.kind ?? widget.initialKind;
    _amount = transaction?.amount.abs() ?? 0;
    _categoryId = transaction?.categoryId;
    _accountId = transaction?.accountId;
    _toAccountId = transaction?.toAccountId;
    _detail = transaction?.detail;
    _date = transaction == null
        ? dateOnly(widget.initialDate ?? today())
        : DateTime.parse(transaction.date);
    _noteController = TextEditingController(text: transaction?.note ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelections());
  }

  @override
  void dispose() {
    _noteController.dispose();
    _categoryNameController.dispose();
    super.dispose();
  }

  void _ensureSelections() {
    final store = context.read<MoneyStore>();
    final categories = _kind == 'income'
        ? store.incomeCategories
        : store.expenseCategories;
    final accounts = store.activeAccounts;
    var changed = false;
    if (!_isTransfer &&
        (_categoryId == null ||
            !categories.any((category) => category.id == _categoryId))) {
      _categoryId = categories.isEmpty ? null : categories.first.id;
      changed = true;
    }
    if (_accountId == null ||
        !accounts.any((account) => account.id == _accountId)) {
      _accountId = accounts.isEmpty ? null : accounts.first.id;
      changed = true;
    }
    if (_isTransfer &&
        (_toAccountId == null ||
            !accounts.any((account) => account.id == _toAccountId) ||
            _toAccountId == _accountId)) {
      final other = accounts
          .where((account) => account.id != _accountId)
          .firstOrNull;
      _toAccountId = other?.id;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _pressKey(String key) {
    HapticFeedback.lightImpact();
    if (key == 'back') {
      setState(() => _amount = _amount ~/ 10);
      return;
    }
    if (key == '000') {
      if (_amount == 0) return;
      setState(() {
        final next = _amount * 1000;
        _amount = next > 999999999999 ? 999999999999 : next;
      });
      return;
    }
    final digit = int.tryParse(key);
    if (digit == null) return;
    setState(() {
      final next = _amount * 10 + digit;
      _amount = next > 999999999999 ? 999999999999 : next;
    });
  }

  void _changeKind(String kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _creatingCategory = false;
      _categoryError = null;
      if (kind == 'transfer') {
        _categoryId = null;
      } else {
        final store = context.read<MoneyStore>();
        final categories = kind == 'income'
            ? store.incomeCategories
            : store.expenseCategories;
        _categoryId = categories.isEmpty ? null : categories.first.id;
      }
    });
    _ensureSelections();
  }

  Future<void> _pickDate() async {
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

  Future<void> _pickAccount({required bool to}) async {
    final store = context.read<MoneyStore>();
    final accounts = store.activeAccounts;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (_) => _WalletSheet(
        title: to ? 'Ke sumber dana' : 'Dari sumber dana',
        accounts: accounts,
        selectedId: to ? _toAccountId : _accountId,
        excludedId: to ? _accountId : null,
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == '__manage__') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ManageAccountsPage()),
      );
      if (!mounted) return;
      final refreshed = context.read<MoneyStore>().activeAccounts;
      setState(() {
        if (!refreshed.any((account) => account.id == _accountId)) {
          _accountId = refreshed.isEmpty ? null : refreshed.first.id;
        }
        if (to && !refreshed.any((account) => account.id == _toAccountId)) {
          _toAccountId = refreshed
              .where((account) => account.id != _accountId)
              .firstOrNull
              ?.id;
        }
      });
      return;
    }
    setState(() {
      if (to) {
        _toAccountId = selected;
      } else {
        _accountId = selected;
        if (_isTransfer && _toAccountId == selected) {
          _toAccountId = accounts
              .where((account) => account.id != selected)
              .firstOrNull
              ?.id;
        }
      }
    });
  }

  Future<void> _addCategoryInline() async {
    final name = _categoryNameController.text.trim();
    if (name.isEmpty) return;
    try {
      final category = await context.read<MoneyStore>().addCategory(
        name,
        _kind,
      );
      if (!mounted) return;
      setState(() {
        _categoryId = category.id;
        _creatingCategory = false;
        _categoryError = null;
        _categoryNameController.clear();
      });
    } on NameConflictException {
      if (!mounted) return;
      setState(() => _categoryError = 'Kategori itu sudah ada.');
    }
  }

  bool get _canSave {
    if (_amount <= 0) return false;
    if (_isTransfer) {
      return _accountId != null &&
          _toAccountId != null &&
          _accountId != _toAccountId;
    }
    return _categoryId != null && _accountId != null;
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      final store = context.read<MoneyStore>();
      final settings = context.read<SettingsStore>();
      final note = _noteController.text.trim();
      final transaction = MoneyTransaction(
        id: widget.transaction?.id ?? const Uuid().v4(),
        amount: _amount,
        kind: _kind,
        categoryId: _isTransfer ? null : _categoryId,
        accountId: _accountId!,
        toAccountId: _isTransfer ? _toAccountId : null,
        date: dateKey(_date),
        note: note.isEmpty ? null : note,
        detail: _detail,
        createdAt:
            widget.transaction?.createdAt ??
            DateTime.now().millisecondsSinceEpoch,
      );
      final previous = widget.transaction;
      var delta = balanceDeltaOf(transaction);
      if (previous != null) delta -= balanceDeltaOf(previous);

      if (_isEditing) {
        await store.updateTransaction(transaction);
      } else {
        await store.addTransaction(transaction);
      }
      if (delta != 0 && settings.soundEnabled) {
        SoundFx.play(delta > 0 ? settings.soundUp : settings.soundDown);
      }
      if (mounted) Navigator.of(context).pop(transaction.date);
    } catch (error, stack) {
      debugPrint('Simpan transaksi gagal: $error\n$stack');
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Gagal menyimpan. Coba lagi.');
    }
  }

  Future<void> _delete() async {
    final transaction = widget.transaction;
    if (transaction == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EsokColors.canvas,
        title: const Text('Hapus transaksi?'),
        content: const Text('Transaksi ini akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<MoneyStore>().deleteTransaction(transaction.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _scanReceipt() async {
    final settings = context.read<SettingsStore>();
    final store = context.read<MoneyStore>();
    if (!settings.aiReady) {
      _toast('Isi API key dulu di Setelan → Pindai struk.');
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (_) => const _ScanSourceSheet(),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      isScrollControlled: true,
      builder: (_) => _ScanConfirmSheet(file: file),
    );
    if (proceed != true || !mounted) return;

    setState(() => _scanning = true);
    try {
      final result = await ReceiptScanner.scan(
        image: file,
        apiKey: settings.aiKey,
        model: settings.aiModel,
        expenseCategories: store.expenseCategories,
        incomeCategories: store.incomeCategories,
      );
      if (!mounted) return;
      if (result.transaksi.isEmpty) {
        _toast('Nominal tidak terbaca. Coba foto yang lebih jelas.');
        return;
      }

      ScanTransaction? chosen;
      if (result.transaksi.length == 1) {
        chosen = result.transaksi.first;
      } else {
        chosen = await showModalBottomSheet<ScanTransaction>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: const Color(0x5214120E),
          isScrollControlled: true,
          builder: (_) => _ScanRowsSheet(transactions: result.transaksi),
        );
      }
      if (chosen == null || !mounted) return;
      _applyScan(store, chosen);
    } on ReceiptScanException catch (error) {
      _toast(error.message);
    } catch (error) {
      _toast('Gagal memindai struk.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyScan(MoneyStore store, ScanTransaction scan) {
    final newKind = scan.arah == 'masuk' ? 'income' : 'expense';
    final pool = newKind == 'income'
        ? store.incomeCategories
        : store.expenseCategories;
    String? categoryId;
    final wanted = scan.kategori?.toLowerCase().trim();
    if (wanted != null && wanted.isNotEmpty) {
      for (final category in pool) {
        if (category.name.toLowerCase().trim() == wanted) {
          categoryId = category.id;
          break;
        }
      }
    }
    if (categoryId == null) {
      final fallbackId = newKind == 'income' ? 'cat-inc-lain' : 'cat-exp-lain';
      for (final category in pool) {
        if (category.id == fallbackId) {
          categoryId = category.id;
          break;
        }
      }
      categoryId ??= pool.isEmpty ? null : pool.last.id;
    }

    setState(() {
      _kind = newKind;
      _amount = scan.nominal > 999999999999 ? 999999999999 : scan.nominal;
      _categoryId = categoryId;
      if (scan.tanggal != null) _date = scan.tanggal!;
      _noteController.text = _summaryForScan(scan);
      _detail = _formatDetail(scan.barang);
      _creatingCategory = false;
    });
    _toast('Terisi dari pindai — periksa sebelum menyimpan.');
  }

  String _summaryForScan(ScanTransaction scan) {
    final pihak = scan.pihak?.trim();
    final catatan = scan.catatan?.trim();
    if (scan.barang.isNotEmpty) {
      return '${pihak ?? 'Hasil pindai'} · ${scan.barang.length} item';
    }
    if (pihak != null && pihak.isNotEmpty) {
      if (catatan != null && catatan.isNotEmpty) return '$pihak · $catatan';
      return pihak;
    }
    if (catatan != null && catatan.isNotEmpty) return catatan;
    return 'Hasil pindai';
  }

  String? _formatDetail(List<ScanItem> items) {
    if (items.isEmpty) return null;
    final lines = <String>[];
    for (final item in items) {
      final name = item.jelas?.trim().isNotEmpty == true
          ? item.jelas!.trim()
          : item.asli;
      lines.add('${item.qty}× $name — ${numberText(item.harga)}');
    }
    return lines.join('\n');
  }

  void _showItems() {
    final detail = _detail;
    if (detail == null || detail.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      isScrollControlled: true,
      builder: (_) => ItemsSheet(detail: detail, total: _amount),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MoneyStore>();
    final categories = _kind == 'income'
        ? store.incomeCategories
        : store.expenseCategories;
    final accounts = store.activeAccounts;
    final selectedCategory = categories
        .where((category) => category.id == _categoryId)
        .firstOrNull;
    final selectedAccount = accounts
        .where((account) => account.id == _accountId)
        .firstOrNull;
    final selectedToAccount = accounts
        .where((account) => account.id == _toAccountId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: EsokColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxHeight >= 640;
            final categoryGrid = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _CategoryGrid(
                categories: categories,
                selectedId: _categoryId,
                onSelect: (id) => setState(() => _categoryId = id),
                onNew: () => setState(() {
                  _creatingCategory = true;
                  _categoryError = null;
                }),
              ),
            );

            final children = <Widget>[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      _isEditing ? 'Ubah' : 'Catat',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: EsokColors.ink,
                      ),
                    ),
                    if (!_isTransfer)
                      Positioned(
                        right: 8,
                        child: _scanning
                            ? const SizedBox(
                                width: 36,
                                height: 36,
                                child: Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : GestureDetector(
                                onTap: _scanReceipt,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.photo_camera_outlined,
                                    size: 19,
                                    color: EsokColors.muted,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Segments(
                  selected: _kind,
                  onChanged: _changeKind,
                ),
              ),
              const SizedBox(height: 14),
              if (!_isTransfer) ...[
                if (roomy)
                  Expanded(child: categoryGrid)
                else
                  SizedBox(height: 158, child: categoryGrid),
                if (_creatingCategory) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _InlineCategory(
                      controller: _categoryNameController,
                      error: _categoryError,
                      onCancel: () => setState(() {
                        _creatingCategory = false;
                        _categoryNameController.clear();
                        _categoryError = null;
                      }),
                      onSave: _addCategoryInline,
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _WalletPill(
                          label: selectedAccount?.name ?? 'Sumber dana',
                          onTap: () => _pickAccount(to: false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: _NoteField(
                          controller: _noteController,
                          detail: _detail,
                          onShowDetail: _showItems,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WalletPill(
                        label: 'Dari ${selectedAccount?.name ?? '—'}',
                        onTap: () => _pickAccount(to: false),
                      ),
                      const SizedBox(height: 8),
                      _WalletPill(
                        label: 'Ke ${selectedToAccount?.name ?? '—'}',
                        onTap: () => _pickAccount(to: true),
                      ),
                      const SizedBox(height: 8),
                      _NoteField(
                        controller: _noteController,
                        detail: _detail,
                        onShowDetail: _showItems,
                      ),
                    ],
                  ),
                ),
                if (roomy) const Spacer() else const SizedBox(height: 8),
              ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: EsokColors.soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isTransfer
                            ? 'PINDAH'
                            : (selectedCategory?.name ?? 'JUMLAH')
                                  .toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.06,
                          color: EsokColors.muted,
                        ),
                      ),
                    ),
                    Text(
                      'Rp ${numberText(_amount)}',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.02,
                        color: _amount == 0
                            ? EsokColors.disabled
                            : EsokColors.ink,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _DateChip(
                      label: 'Hari ini',
                      selected: _date == today(),
                      onTap: () => setState(() => _date = today()),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: _DateChip(
                      label: 'Kemarin',
                      selected:
                          _date == today().subtract(const Duration(days: 1)),
                      onTap: () => setState(
                        () => _date = today().subtract(
                          const Duration(days: 1),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: EsokColors.soft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 15,
                            color: EsokColors.ink,
                          ),
                          if (_date != today() &&
                              _date !=
                                  today().subtract(
                                    const Duration(days: 1),
                                  )) ...[
                            const SizedBox(width: 6),
                            Text(
                              shortDateTitle(_date),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: EsokColors.ink,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: _Keypad(onKey: _pressKey),
            ),
            if (_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: TextButton(
                  onPressed: _delete,
                  style: TextButton.styleFrom(
                    foregroundColor: EsokColors.lateInk,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('Hapus transaksi'),
                ),
              ),
              _BottomActions(
                canSave: _canSave,
                saving: _saving,
                onCancel: () => Navigator.of(context).pop(),
                onSave: _save,
              ),
            ];

            final column = Column(children: children);
            if (roomy) return column;
            return SingleChildScrollView(child: column);
          },
        ),
      ),
    );
  }
}

class _ScanSourceSheet extends StatelessWidget {
  const _ScanSourceSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EsokColors.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
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
              'Pindai struk',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: EsokColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Foto langsung atau pilih dari galeri',
              style: TextStyle(fontSize: 11, color: EsokColors.muted),
            ),
            const SizedBox(height: 8),
            const _ScanSourceRow(
              icon: Icons.photo_camera_outlined,
              label: 'Kamera',
              source: ImageSource.camera,
            ),
            Divider(height: 1, color: EsokColors.line),
            const _ScanSourceRow(
              icon: Icons.photo_library_outlined,
              label: 'Galeri',
              source: ImageSource.gallery,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSourceRow extends StatelessWidget {
  const _ScanSourceRow({
    required this.icon,
    required this.label,
    required this.source,
  });

  final IconData icon;
  final String label;
  final ImageSource source;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(source),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Icon(icon, size: 19, color: EsokColors.muted),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: EsokColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanConfirmSheet extends StatelessWidget {
  const _ScanConfirmSheet({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              'Foto siap dipindai',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: EsokColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pastikan nominal total terlihat jelas',
              style: TextStyle(fontSize: 11, color: EsokColors.muted),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                file,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.auto_awesome, size: 17),
                label: const Text('Scan dengan AI'),
                style: FilledButton.styleFrom(
                  backgroundColor: EsokColors.accent,
                  foregroundColor: EsokColors.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: EsokColors.muted,
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('Ganti foto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  static const _values = ['expense', 'income', 'transfer'];
  static const _labels = ['Keluar', 'Masuk', 'Pindah'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: EsokColors.track,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(_values[i]),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected == _values[i]
                        ? EsokColors.canvas
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: selected == _values[i]
                        ? [
                            BoxShadow(
                              color: EsokColors.ink.withValues(alpha: 0.06),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    _labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected == _values[i]
                          ? EsokColors.ink
                          : EsokColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onNew,
  });

  final List<MoneyCategory> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: categories.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 70,
      ),
      itemBuilder: (context, index) {
        if (index == categories.length) {
          return _CategoryTile(
            onTap: onNew,
            selected: false,
            newTile: true,
            label: 'Baru',
          );
        }
        final category = categories[index];
        return _CategoryTile(
          onTap: () => onSelect(category.id),
          selected: category.id == selectedId,
          icon: CategoryIconView(category: category, size: 20),
          label: category.name,
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.onTap,
    required this.selected,
    this.icon,
    this.label,
    this.newTile = false,
  });

  final VoidCallback onTap;
  final bool selected;
  final Widget? icon;
  final String? label;
  final bool newTile;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        decoration: BoxDecoration(
          color: selected ? EsokColors.canvas : EsokColors.soft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? EsokColors.ink
                : newTile
                ? EsokColors.lineStrong
                : Colors.transparent,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (newTile)
              Icon(Icons.add, size: 19, color: EsokColors.muted)
            else
              icon ?? const SizedBox.shrink(),
            const SizedBox(height: 5),
            Text(
              label ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                color: selected ? EsokColors.ink : EsokColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineCategory extends StatelessWidget {
  const _InlineCategory({
    required this.controller,
    required this.error,
    required this.onCancel,
    required this.onSave,
  });

  final TextEditingController controller;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
      decoration: BoxDecoration(
        color: EsokColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: EsokColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => onSave(),
            style: TextStyle(fontSize: 14, color: EsokColors.ink),
            decoration: InputDecoration(
              hintText: 'Nama kategori baru',
              errorText: error,
              hintStyle: TextStyle(fontSize: 14, color: EsokColors.muted),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              filled: true,
              fillColor: EsokColors.soft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: EsokColors.ink, width: 1.2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: EsokColors.muted,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: onSave,
                style: TextButton.styleFrom(
                  foregroundColor: EsokColors.accent,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Tambah'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletPill extends StatelessWidget {
  const _WalletPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: EsokColors.soft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 16,
              color: EsokColors.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: EsokColors.ink),
              ),
            ),
            Icon(Icons.chevron_right, size: 15, color: EsokColors.muted),
          ],
        ),
      ),
    );
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({
    required this.controller,
    required this.detail,
    required this.onShowDetail,
  });

  final TextEditingController controller;
  final String? detail;
  final VoidCallback onShowDetail;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _editNote() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5214120E),
      builder: (_) => _NoteEditorSheet(initialValue: widget.controller.text),
    );
    if (!mounted || result == null) return;
    widget.controller.text = result;
    widget.controller.selection = TextSelection.collapsed(
      offset: result.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDetail = widget.detail != null && widget.detail!.isNotEmpty;
    final note = widget.controller.text.trim();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: EsokColors.soft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _editNote,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  note.isEmpty ? 'Catatan' : note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: note.isEmpty ? EsokColors.muted : EsokColors.ink,
                  ),
                ),
              ),
            ),
          ),
          if (hasDetail)
            GestureDetector(
              onTap: widget.onShowDetail,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 18,
                  color: EsokColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteEditorSheet extends StatefulWidget {
  const _NoteEditorSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
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
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: EsokColors.handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Catatan transaksi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: EsokColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 15, color: EsokColors.ink),
                decoration: InputDecoration(
                  hintText: 'Tulis catatan…',
                  hintStyle: TextStyle(color: EsokColors.muted),
                  filled: true,
                  fillColor: EsokColors.soft,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: EsokColors.ink, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: EsokColors.ink,
                          side: BorderSide(color: EsokColors.lineStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(_controller.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: EsokColors.accent,
                          foregroundColor: EsokColors.fabText,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        child: const Text('Simpan'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: selected ? EsokColors.ink : EsokColors.soft,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? EsokColors.canvas : EsokColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '000',
    '0',
    'back',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < 4; row++) ...[
          if (row > 0) const SizedBox(height: 7),
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: 7),
                Expanded(
                  child: _KeyButton(
                    value: _keys[row * 3 + col],
                    onTap: onKey,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.value, required this.onTap});

  final String value;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final isBack = value == 'back';
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: EsokColors.soft,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: isBack
            ? Icon(
                Icons.backspace_outlined,
                size: 19,
                color: EsokColors.muted,
              )
            : Text(
                value,
                style: TextStyle(
                  fontSize: value == '000' ? 13 : 19,
                  fontWeight: FontWeight.w500,
                  color: value == '000'
                      ? EsokColors.muted
                      : EsokColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.canSave,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          children: [
            Expanded(
              flex: 10,
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: saving ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EsokColors.ink,
                    side: BorderSide(color: EsokColors.lineStrong),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: const Text('Batal'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 14,
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: canSave && !saving ? onSave : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: EsokColors.accent,
                    foregroundColor: EsokColors.onAccent,
                    disabledBackgroundColor: EsokColors.soft,
                    disabledForegroundColor: EsokColors.disabled,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: Text(saving ? 'Menyimpan…' : 'Simpan'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanRowsSheet extends StatefulWidget {
  const _ScanRowsSheet({required this.transactions});

  final List<ScanTransaction> transactions;

  @override
  State<_ScanRowsSheet> createState() => _ScanRowsSheetState();
}

class _ScanRowsSheetState extends State<_ScanRowsSheet> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: BoxDecoration(
        color: EsokColors.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
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
              'Pilih transaksi',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: EsokColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gambar berisi ${widget.transactions.length} baris. Pilih satu.',
              style: TextStyle(
                fontSize: 11.5,
                color: EsokColors.muted,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.transactions.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: EsokColors.line),
                itemBuilder: (context, index) {
                  final scan = widget.transactions[index];
                  final selected = index == _selected;
                  final incoming = scan.arah == 'masuk';
                  return GestureDetector(
                    onTap: () => setState(() => _selected = index),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: selected
                                ? EsokColors.accent
                                : EsokColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  scan.pihak ??
                                      scan.catatan ??
                                      'Transaksi ${index + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: EsokColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    if (scan.tanggal != null)
                                      shortDateTitle(scan.tanggal!),
                                    incoming ? 'Masuk' : 'Keluar',
                                    if (scan.kategori != null) scan.kategori!,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: EsokColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${incoming ? '+' : '−'}${numberText(scan.nominal)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: incoming
                                  ? EsokColors.positive
                                  : EsokColors.negative,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: widget.transactions.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                        widget.transactions[_selected],
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: EsokColors.accent,
                  foregroundColor: EsokColors.onAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: const Text('Pakai baris terpilih'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSheet extends StatelessWidget {
  const _WalletSheet({
    required this.title,
    required this.accounts,
    required this.selectedId,
    this.excludedId,
  });

  final String title;
  final List<Account> accounts;
  final String? selectedId;
  final String? excludedId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EsokColors.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
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
            const SizedBox(height: 8),
            for (final account in accounts)
              if (account.id != excludedId)
                InkWell(
                  onTap: () => Navigator.of(context).pop(account.id),
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        Icon(
                          selectedId == account.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: selectedId == account.id
                              ? EsokColors.accent
                              : EsokColors.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            account.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: EsokColors.ink,
                            ),
                          ),
                        ),
                        Text(
                          accountTypeLabel(account.type),
                          style: TextStyle(
                            fontSize: 11,
                            color: EsokColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const Divider(),
            TextButton(
              onPressed: () => Navigator.of(context).pop('__manage__'),
              style: TextButton.styleFrom(
                foregroundColor: EsokColors.accent,
                alignment: Alignment.centerLeft,
              ),
              child: const Text('Kelola sumber dana'),
            ),
          ],
        ),
      ),
    );
  }
}
