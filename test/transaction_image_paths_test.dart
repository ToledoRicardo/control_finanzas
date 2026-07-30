import 'package:flutter_test/flutter_test.dart';
import 'package:control_finanzas/models/transaction.dart';

void main() {
  group('FinancialTransaction image paths', () {
    test('serializa y recupera las rutas de imágenes correctamente', () {
      final transaction = FinancialTransaction(
        id: 7,
        categoryId: 1,
        amount: 150,
        description: 'Compra de referencia',
        date: DateTime(2026, 7, 29),
        type: 'expense',
        imagePaths: const ['photos/1.jpg', 'photos/2.jpg'],
      );

      final map = transaction.toMap();
      final restored = FinancialTransaction.fromMap(map);

      expect(restored.imagePaths, ['photos/1.jpg', 'photos/2.jpg']);
    });
  });
}
