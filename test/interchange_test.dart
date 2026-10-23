// PLAN step 2.6, the machine-checkable half: marks written by the desktop (every fifth sentence of
// each page, from PDF.js) must be found again on the phone's raw strings (PDFium), and marks the
// phone writes must be a notes file the desktop reads. The desktop's half runs with
//   node <scratch>/interchange.mts check <pdf> <file>
// The PDFs live in the desktop repository; the test is skipped where it is not checked out.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfreader/document_text.dart';
import 'package:pdfreader/shared/marks.dart';
import 'package:pdfreader/shared/notes.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'desktop_repo.dart';

final files = {
  'sample': sampleFixture,
  'centric': '$desktopRepo/docs/sample_pdfs/centric_2026_1_10_30003.pdf',
};

void main() {
  setUpAll(pdfrxInitialize);

  for (final MapEntry(key: name, value: path) in files.entries) {
    group(name, () {
      late PdfDocument document;
      late DocumentText text;

      setUp(() async {
        document = await PdfDocument.openFile(path);
        text = DocumentText(document);
      });
      tearDown(() => document.dispose());

      test('the phone finds every mark the desktop wrote', () async {
        final notes = parseNotes(
          jsonDecode(File('test/golden/notes-desktop-$name.json').readAsStringSync()),
        )!;
        final raw = {for (var n = 1; n <= text.pageCount; n++) n: (await text.page(n)).text.raw};
        final found = anchorMarks(notes.annotations, raw);
        final lost = [
          for (final a in notes.annotations)
            if (!found.containsKey(a.id)) a,
        ];
        // ignore: avoid_print
        print('INTERCHANGE $name desktop to phone: found ${found.length} of ${notes.annotations.length}');
        for (final a in lost.take(8)) {
          // ignore: avoid_print
          print('  lost p${a.page} ${jsonEncode(a.text.length > 60 ? a.text.substring(0, 60) : a.text)}');
        }
        expect(lost, isEmpty);
      }, skip: File(path).existsSync() ? false : 'needs $path');

      test('writes a notes file for the desktop to read: a mark over every fifth sentence', () async {
        final marks = <Annotation>[];
        for (var page = 1; page <= text.pageCount; page++) {
          final loaded = await text.page(page);
          final utterances = await text.utterances(page);
          for (var k = 0; k < utterances.length; k += 5) {
            final ranges = utterances[k].ranges;
            final mark = newMark(
              page: page,
              start: ranges.first.$1,
              end: ranges.last.$2,
              raw: loaded.text.raw,
              blocks: loaded.blocks,
              kind: MarkKind.highlight,
              color: HighlightColor.yellow,
              id: 'phone-$page-$k',
              created: '2026-10-21T00:00:00.000Z',
            );
            if (mark != null) marks.add(mark);
          }
        }
        final out = File('${Directory.systemTemp.path}/notes-phone-$name.json');
        out.writeAsStringSync(encodeNotes(NotesFile(notes: '', annotations: marks)));
        // ignore: avoid_print
        print('INTERCHANGE $name phone wrote ${marks.length} marks to ${out.path}');
        expect(parseNotes(jsonDecode(out.readAsStringSync()))!.annotations, hasLength(marks.length));
      }, skip: File(path).existsSync() ? false : 'needs $path');
    }, skip: skipWithout(path));
  }
}
