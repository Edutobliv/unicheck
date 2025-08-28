import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proyecto_carnet/main.dart'; // donde está CarnetPage

void main() {
  testWidgets('Renderiza la pantalla de Carnet', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CarnetPage()));

    // Verifica que el título se muestre
    expect(find.text('Carnet Digital'), findsOneWidget);

    // No verificamos QR ni red (evitamos dependencias externas en tests)
  });
}
