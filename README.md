# Esok

Catatan harian dan buku kas dalam satu aplikasi Android.
Tanpa akun, tanpa cloud — seluruh data tinggal di HP.

Versi terbaru **1.9.6** · [Releases](../../releases)

## Fitur

- **Catatan per hari** dengan jam opsional. Geser untuk pindah hari, ketuk tanggal untuk membuka kalender bulanan.
- **Pengingat** sebelum tenggat, bisa diatur 30 menit sampai 1 hari.
- **Pindai foto** struk dan tangkapan layar M-Banking dengan AI: arah, nominal, kategori, hingga rincian barang terisi sendiri.
- **Buku kas**: pengeluaran, pemasukan, pindah dompet, saldo per dompet, dan koreksi saldo.
- **Widget** catatan dan ringkasan uang — bisa dicentang langsung dari layar utama.
- **Cadangan otomatis** ke `Download/Esok/esok-backup.json`, tetap ada walau aplikasi dihapus.
- **Notifikasi pembaruan** di dalam aplikasi saat ada rilis baru di GitHub.
- **Tema** terang, gelap, atau ikut sistem.

## Memasang

1. Buka halaman [Releases](../../releases).
2. Unduh berkas `.apk`.
3. Buka berkasnya, lalu izinkan pemasangan bila diminta.

Pasang menimpa versi lama — data tidak hilang.

## Build

```powershell
flutter pub get
flutter build apk --release --split-per-abi
```

Hasilnya ada di `build/app/outputs/flutter-apk/`.

## Struktur

```
lib/
  data/    model dan SQLite: tugas, kategori, dompet, transaksi
  state/   TaskStore, MoneyStore, SettingsStore
  ui/      layar Hari, Uang, Setelan, editor transaksi
  ai/      pindai struk dan mutasi
  backup/  ekspor, impor, cadangan otomatis
  widget/  jembatan ke widget Android
android/app/src/main/kotlin/   widget native dan receiver
assets/  font, ikon kategori, suara
```

## Catatan

- SQLite adalah sumber kebenaran. Widget menerima salinan JSON, dan centang dari widget diterapkan ke database saat aplikasi dibuka.
- Versi database 5 — menambah kolom rincian barang pada transaksi.
- Dibuat untuk pemakaian pribadi.
