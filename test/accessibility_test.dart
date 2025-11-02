import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proyecto_carnet/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Carnet photo exposes alt text and button role', (tester) async {
    final semantics = SemanticsTester(tester);

    await tester.pumpWidget(const MaterialApp(home: CarnetPage()));
    await tester.pump();

    expect(
      semantics,
      includesNodeWith(
        label: 'Actualizar foto del carnet',
        flags: <SemanticsFlag>[SemanticsFlag.isButton],
      ),
    );

    expect(
      semantics,
      includesNodeWith(
        label: 'Foto del estudiante',
        flags: <SemanticsFlag>[SemanticsFlag.isImage],
      ),
    );

    semantics.dispose();
  });
}
