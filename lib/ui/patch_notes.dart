import 'package:material_ui/material_ui.dart';

import 'theme.dart';

Future<void> showPatchNotes(
  BuildContext context, {
  required String version,
  required String buildNumber,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x5214120E),
    builder: (context) =>
        PatchNotesSheet(version: version, buildNumber: buildNumber),
  );
}

class PatchNotesSheet extends StatelessWidget {
  const PatchNotesSheet({
    super.key,
    required this.version,
    required this.buildNumber,
  });

  final String version;
  final String buildNumber;

  static const _releases = [
    (
      version: '1.9.7',
      date: '16 Nov 2026',
      notes: [
        'Catatan transaksi ditulis langsung ke transaksi saat diketik, sehingga tidak hilang ketika ditekan Simpan.',
      ],
    ),
    (
      version: '1.9.6',
      date: '16 Nov 2026',
      notes: [
        'Catatan di form Uang sekarang dibuka lewat editor dengan keyboard yang langsung muncul.',
        'Keyboard muncul lagi saat field judul atau catatan tugas diketuk setelah ditutup dengan tombol Back.',
      ],
    ),
    (
      version: '1.9.5',
      date: '16 Nov 2026',
      notes: [
        'Notifikasi dalam aplikasi saat versi baru tersedia di GitHub Releases, dengan tombol buka halaman rilis.',
        'Baris “Periksa pembaruan” di Setelan untuk mengecek versi terbaru kapan saja.',
      ],
    ),
    (
      version: '1.9.4',
      date: '16 Nov 2026',
      notes: [
        'Widget tugas bisa di-scroll, jadi semua catatan bisa dilihat dan dicentang tanpa membuka aplikasi.',
      ],
    ),
    (
      version: '1.9.3',
      date: '16 Nov 2026',
      notes: [
        'Suara khusus saat semua tugas di satu hari selesai, bisa diatur di Setelan → Suara.',
      ],
    ),
    (
      version: '1.9.2',
      date: '16 Nov 2026',
      notes: [
        'Bunyi centang di widget mengikuti nada yang dipilih, termasuk suara impor dan pilihan Diam.',
      ],
    ),
    (
      version: '1.9.1',
      date: '16 Nov 2026',
      notes: [
        'Rute widget memakai action HomeWidget: +/badan widget uang dan judul widget tugas membuka layar yang benar.',
        'Cadangan otomatis memberi umpan balik, memverifikasi berkas, dan menyediakan jalur simpan manual.',
      ],
    ),
    (
      version: '1.9.0',
      date: '16 Nov 2026',
      notes: [
        'Pindai AI mengisi arah Keluar/Masuk dan bisa memilih baris dari mutasi ganda.',
        'Rincian barang struk disimpan terpisah dari catatan ringkas.',
        'Widget memilih hari terdekat yang punya catatan dan membuka layar yang tepat saat diketuk.',
        'Perbaikan transaksi hasil pindai yang tidak terlihat setelah disimpan.',
        'Perbaikan tinggi kolom catatan agar sejajar dengan pill dompet.',
      ],
    ),
    (
      version: '1.8.0',
      date: '14 Nov 2026',
      notes: [
        'Cadangan otomatis harian ke Download/Esok/esok-backup.json.',
        'Cadangan hanya ditulis bila data berubah.',
        'Pulihkan cadangan saat aplikasi dipasang ulang.',
      ],
    ),
    (
      version: '1.6.0',
      date: '14 Nov 2026',
      notes: [
        'Efek suara untuk centang tugas, transaksi, dan widget.',
        'Halaman Suara: pilih nada pengingat, centang, dan saldo masuk/keluar.',
        'Impor berkas suara sendiri dari penyimpanan.',
        'Kirim notifikasi tes dari halaman Suara.',
      ],
    ),
    (
      version: '1.5.0',
      date: '14 Nov 2026',
      notes: [
        'Total dana di tab Uang; saldo per dompet dihitung dari dana awal + transaksi.',
        'Ubah dana awal dan koreksi saldo dari Sumber dana.',
        'Koreksi saldo tidak mengubah laporan masuk/keluar bulanan.',
      ],
    ),
    (
      version: '1.4.0',
      date: '14 Nov 2026',
      notes: [
        'Widget uang 2×2 dan 4×1: pengeluaran hari ini dan bulan ini.',
        'Sembunyikan nominal di widget lewat Setelan → Widget.',
        'Widget mengikuti tema terang/gelap sistem Android.',
      ],
    ),
    (
      version: '1.3.0',
      date: '14 Nov 2026',
      notes: [
        'Tiga tab: Hari, Uang, dan Setelan.',
        'Tema Terang · Sistem · Gelap, berlaku seketika dan tersimpan.',
        'Nominal keluar merah, masuk hijau; tanda +/− selalu ada.',
        'Ikon kategori, kategori Minuman, dan fallback huruf.',
        'Form transaksi baru: grid kategori, dompet + catatan, dan aksi bawah.',
        'Pengingat awal bisa diatur 30 menit sampai 1 hari.',
      ],
    ),
    (
      version: '1.2.0',
      date: '14 Nov 2026',
      notes: [
        'Tab Uang: catat pengeluaran, pemasukan, dan pindah antar dompet.',
        'Ringkasan bulanan, riwayat per hari, dan ringkasan uang di tab Hari.',
        'Kategori dan sumber dana bisa ditambah langsung dari form.',
        'Ekspor/impor JSON, ekspor CSV, dan hapus semua data.',
        'Tanggal terpilih di pemilih tanggal memakai outline, angkanya tetap terbaca.',
      ],
    ),
    (
      version: '1.1.0',
      date: '14 Nov 2026',
      notes: [
        'Fokus pada catatan meminta ulang keyboard, membantu saat Gboard sempat tidak muncul.',
        'Pengingat waktu tidak mengubah status tugas. Centang tetap manual.',
        'Menu izin notifikasi dihapus; izin diminta sekali lewat dialog Android.',
        'Pemilih jam baru dengan roda jam dan menit.',
        'Menu catatan rilis ini.',
      ],
    ),
    (
      version: '1.0.0',
      date: '13 Nov 2026',
      notes: [
        'Rilis awal: daftar harian, quick add, kalender, notifikasi, dan widget.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: EsokColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
          child: Column(
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
                      'Catatan rilis',
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
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: EsokColors.soft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Versi $version ($buildNumber)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: EsokColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              for (var i = 0; i < _releases.length; i++) ...[
                if (i > 0) const SizedBox(height: 22),
                _ReleaseBlock(
                  version: _releases[i].version,
                  date: _releases[i].date,
                  notes: _releases[i].notes,
                  isLatest: i == 0,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Dibuat untuk pemakaian pribadi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: EsokColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseBlock extends StatelessWidget {
  const _ReleaseBlock({
    required this.version,
    required this.date,
    required this.notes,
    required this.isLatest,
  });

  final String version;
  final String date;
  final List<String> notes;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              version,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: EsokColors.ink,
              ),
            ),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: EsokColors.lateSurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Terbaru',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: EsokColors.accent,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: EsokColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: EsokColors.muted,
                  ),
                ),
                Expanded(
                  child: Text(
                    note,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: EsokColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
