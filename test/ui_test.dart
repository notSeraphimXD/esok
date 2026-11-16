import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/ui/patch_notes.dart';
import 'package:jadwal/ui/theme.dart';
import 'package:jadwal/ui/time_picker_sheet.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('time picker returns the selected time', (tester) async {
    TimeOfDay? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: EsokTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showTimePickerSheet(
                    context,
                    initial: const TimeOfDay(hour: 9, minute: 0),
                  );
                },
                child: const Text('Buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih jam'), findsOneWidget);
    expect(find.text('09.00'), findsOneWidget);

    await tester.tap(find.text('Pilih'));
    await tester.pumpAndSettle();
    expect(result, const TimeOfDay(hour: 9, minute: 0));
  });

  testWidgets('patch notes show version and latest release', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: EsokTheme.light(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PatchNotesSheet(version: '1.9.5', buildNumber: '16'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catatan rilis'), findsOneWidget);
    expect(find.text('Versi 1.9.5 (16)'), findsOneWidget);
    expect(find.text('Terbaru'), findsOneWidget);
    expect(
      find.text(
        'Notifikasi dalam aplikasi saat versi baru tersedia di GitHub Releases, dengan tombol buka halaman rilis.',
      ),
      findsOneWidget,
    );
  });
}
