// The sample PDF in this repository is a copy of the desktop's, and the golden files are made from
// the desktop's bytes: a copy that has fallen behind makes the golden tests fail for a wrong reason.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'desktop_repo.dart';

void main() {
  final theirs = '$desktopRepo/tests/fixtures/sample.pdf';

  test('the sample PDF is the desktop’s', () {
    expect(
      File(sampleFixture).readAsBytesSync(),
      File(theirs).readAsBytesSync(),
      reason: 'copy $theirs to $sampleFixture',
    );
  }, skip: skipWithout(theirs));
}
