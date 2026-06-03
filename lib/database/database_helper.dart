import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../models/shopping_cart_item.dart';
import '../models/subcategory.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const String _dbFileName = 'chronowealth.db';

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbFileName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> closeDatabase() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
  }

  Future<Database> reopenDatabase() async {
    await closeDatabase();
    _database = await _initDB(_dbFileName);
    return _database!;
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Agregar nuevas tablas sin modificar las existentes
      const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
      const textType = 'TEXT NOT NULL';
      const realType = 'REAL NOT NULL';

      // Tabla de gastos predefinidos (luz, agua, etc.)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS expense_templates (
          id $idType,
          name $textType,
          icon $textType,
          color $textType,
          defaultAmount REAL,
          "order" INTEGER NOT NULL
        )
      ''');

      // Tabla de items del carrito de compras
      await db.execute('''
        CREATE TABLE IF NOT EXISTS shopping_cart_items (
          id $idType,
          productName $textType,
          price $realType,
          quantity INTEGER NOT NULL DEFAULT 1,
          dateAdded $textType,
          notes TEXT
        )
      ''');

      // Insertar gastos predefinidos
      await _insertDefaultExpenseTemplates(db);
    }

    if (oldVersion < 3) {
      const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
      const textType = 'TEXT NOT NULL';
      const intType = 'INTEGER NOT NULL';

      // Tabla de subcategorías (movimientos personalizados)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS subcategories (
          id $idType,
          categoryId $intType,
          name $textType,
          balance REAL NOT NULL DEFAULT 0.0,
          icon TEXT,
          color TEXT,
          "order" $intType,
          createdDate $textType,
          FOREIGN KEY (categoryId) REFERENCES categories (id) ON DELETE CASCADE
        )
      ''');

      // Agregar columna subcategoryId a transactions (nullable para compatibilidad)
      await db.execute('''
        ALTER TABLE transactions ADD COLUMN subcategoryId INTEGER
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          id INTEGER PRIMARY KEY,
          passwordEnabled INTEGER NOT NULL DEFAULT 0,
          password TEXT
        )
      ''');

      await _ensureDefaultSettings(db);
    }

    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE transactions ADD COLUMN excludeFromTotal INTEGER NOT NULL DEFAULT 0
      ''');
    }

    if (oldVersion < 6) {
      await db.execute('''
        ALTER TABLE subcategories ADD COLUMN isInterestBearing INTEGER NOT NULL DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE subcategories ADD COLUMN interestRate REAL NOT NULL DEFAULT 0.0
      ''');
      await db.execute('''
        ALTER TABLE subcategories ADD COLUMN lastInterestApplied TEXT
      ''');

      await db.execute('''
        ALTER TABLE transactions ADD COLUMN isInterestBearing INTEGER NOT NULL DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE transactions ADD COLUMN interestRate REAL NOT NULL DEFAULT 0.0
      ''');
      await db.execute('''
        ALTER TABLE transactions ADD COLUMN interestLastApplied TEXT
      ''');
    }

    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS interest_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subcategoryId INTEGER NOT NULL,
          transactionId INTEGER,
          interestAmount REAL NOT NULL,
          appliedRate REAL NOT NULL,
          appliedAt TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'auto',
          createdAt TEXT NOT NULL,
          FOREIGN KEY (subcategoryId) REFERENCES subcategories (id) ON DELETE CASCADE,
          FOREIGN KEY (transactionId) REFERENCES transactions (id) ON DELETE SET NULL
        )
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const realType = 'REAL NOT NULL';

    await db.execute('''
      CREATE TABLE categories (
        id $idType,
        name $textType,
        icon $textType,
        color $textType,
        "order" $intType
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id $idType,
        categoryId $intType,
        subcategoryId INTEGER,
        amount $realType,
        description $textType,
        date $textType,
        type $textType,
        excludeFromTotal INTEGER NOT NULL DEFAULT 0,
        isInterestBearing INTEGER NOT NULL DEFAULT 0,
        interestRate REAL NOT NULL DEFAULT 0.0,
        interestLastApplied TEXT,
        FOREIGN KEY (categoryId) REFERENCES categories (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de gastos predefinidos
    await db.execute('''
      CREATE TABLE expense_templates (
        id $idType,
        name $textType,
        icon $textType,
        color $textType,
        defaultAmount REAL,
        "order" $intType
      )
    ''');

    // Tabla de items del carrito
    await db.execute('''
      CREATE TABLE shopping_cart_items (
        id $idType,
        productName $textType,
        price $realType,
        quantity $intType DEFAULT 1,
        dateAdded $textType,
        notes TEXT
      )
    ''');

    // Tabla de subcategorías (movimientos)
    await db.execute('''
      CREATE TABLE subcategories (
        id $idType,
        categoryId $intType,
        name $textType,
        balance REAL NOT NULL DEFAULT 0.0,
        icon TEXT,
        color TEXT,
        "order" $intType,
        createdDate $textType,
        isInterestBearing INTEGER NOT NULL DEFAULT 0,
        interestRate REAL NOT NULL DEFAULT 0.0,
        lastInterestApplied TEXT,
        FOREIGN KEY (categoryId) REFERENCES categories (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE interest_logs (
        id $idType,
        subcategoryId $intType,
        transactionId INTEGER,
        interestAmount REAL NOT NULL,
        appliedRate REAL NOT NULL,
        appliedAt $textType,
        source TEXT NOT NULL DEFAULT 'auto',
        createdAt $textType,
        FOREIGN KEY (subcategoryId) REFERENCES subcategories (id) ON DELETE CASCADE,
        FOREIGN KEY (transactionId) REFERENCES transactions (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY,
        passwordEnabled INTEGER NOT NULL DEFAULT 0,
        password TEXT
      )
    ''');

    // Insertar datos predeterminados
    await _insertDefaultCategories(db);
    await _insertDefaultExpenseTemplates(db);
    await _ensureDefaultSettings(db);
  }

  Future<void> _insertDefaultExpenseTemplates(Database db) async {
    final defaultExpenses = [
      {'name': 'Luz', 'icon': 'lightbulb', 'color': 'FFFFD700', 'defaultAmount': 500.0, 'order': 1},
      {'name': 'Agua', 'icon': 'water_drop', 'color': 'FF2196F3', 'defaultAmount': 200.0, 'order': 2},
      {'name': 'Gas', 'icon': 'local_fire_department', 'color': 'FFFF5722', 'defaultAmount': 300.0, 'order': 3},
      {'name': 'Internet', 'icon': 'wifi', 'color': 'FF9C27B0', 'defaultAmount': 400.0, 'order': 4},
      {'name': 'Teléfono', 'icon': 'phone', 'color': 'FF4CAF50', 'defaultAmount': 300.0, 'order': 5},
      {'name': 'Renta', 'icon': 'home', 'color': 'FF795548', 'defaultAmount': 5000.0, 'order': 6},
      {'name': 'Despensa', 'icon': 'shopping_cart', 'color': 'FFFF9800', 'defaultAmount': 0.0, 'order': 7},
      {'name': 'Transporte', 'icon': 'directions_car', 'color': 'FF607D8B', 'defaultAmount': 500.0, 'order': 8},
    ];

    for (var expense in defaultExpenses) {
      await db.insert('expense_templates', expense, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _insertDefaultCategories(Database db) async {
    final defaultCategories = [
      {'name': 'Cuentas Bancarias', 'icon': 'account_balance', 'color': 'FF4A90E2', 'order': 1},
      {'name': 'Inversiones', 'icon': 'trending_up', 'color': 'FF50C878', 'order': 2},
      {'name': 'Criptomonedas', 'icon': 'currency_bitcoin', 'color': 'FFF7931A', 'order': 3},
      {'name': 'Trading', 'icon': 'show_chart', 'color': 'FFFF6B6B', 'order': 4},
      {'name': 'Préstamos', 'icon': 'handshake', 'color': 'FF9B59B6', 'order': 5},
      {'name': 'Propiedades', 'icon': 'home', 'color': 'FF34495E', 'order': 6},
      {'name': 'Efectivo', 'icon': 'payments', 'color': 'FF2ECC71', 'order': 7},
      {'name': 'Acciones', 'icon': 'show_chart', 'color': 'FF5DADE2', 'order': 8},
      {'name': 'Otros Activos', 'icon': 'inventory_2', 'color': 'FF95A5A6', 'order': 9},
    ];

    for (var category in defaultCategories) {
      await db.insert('categories', category);
    }
  }

  // CRUD para Categorías
  Future<FinancialCategory> createCategory(FinancialCategory category) async {
    final db = await database;
    final id = await db.insert('categories', category.toMap());
    return category.copyWith(id: id);
  }

  Future<List<FinancialCategory>> readAllCategories() async {
    final db = await database;
    const orderBy = '"order" ASC';
    final result = await db.query('categories', orderBy: orderBy);
    return result.map((json) => FinancialCategory.fromMap(json)).toList();
  }

  Future<FinancialCategory?> readCategory(int id) async {
    final db = await database;
    final maps = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return FinancialCategory.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<int> updateCategory(FinancialCategory category) async {
    final db = await database;
    return db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD para Subcategorías
  Future<Subcategory> createSubcategory(Subcategory subcategory) async {
    final db = await database;
    final id = await db.insert('subcategories', subcategory.toMap());
    return subcategory.copyWith(id: id);
  }

  Future<List<Subcategory>> readSubcategoriesByCategory(int categoryId) async {
    final db = await database;
    final result = await db.query(
      'subcategories',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: '"order" ASC',
    );
    return result.map((json) => Subcategory.fromMap(json)).toList();
  }

  Future<List<Subcategory>> readAllSubcategories() async {
    final db = await database;
    final result = await db.query('subcategories', orderBy: '"order" ASC');
    return result.map((json) => Subcategory.fromMap(json)).toList();
  }

  Future<Subcategory?> readSubcategory(int id) async {
    final db = await database;
    final maps = await db.query(
      'subcategories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Subcategory.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateSubcategory(Subcategory subcategory) async {
    final db = await database;
    return await db.update(
      'subcategories',
      subcategory.toMap(),
      where: 'id = ?',
      whereArgs: [subcategory.id],
    );
  }

  Future<int> deleteSubcategory(int id) async {
    final db = await database;
    return await db.delete(
      'subcategories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD para Transacciones
  Future<FinancialTransaction> createTransaction(FinancialTransaction transaction) async {
    final db = await database;
    final id = await db.insert('transactions', transaction.toMap());
    return transaction.copyWith(id: id);
  }

  Future<List<FinancialTransaction>> readAllTransactions() async {
    final db = await database;
    const orderBy = 'date DESC';
    final result = await db.query('transactions', orderBy: orderBy);
    return result.map((json) => FinancialTransaction.fromMap(json)).toList();
  }

  Future<List<FinancialTransaction>> readTransactionsByCategory(int categoryId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: 'date DESC',
    );
    return result.map((json) => FinancialTransaction.fromMap(json)).toList();
  }

  Future<List<FinancialTransaction>> readTransactionsBySubcategory(int subcategoryId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'subcategoryId = ?',
      whereArgs: [subcategoryId],
      orderBy: 'date DESC',
    );
    return result.map((json) => FinancialTransaction.fromMap(json)).toList();
  }

  Future<FinancialTransaction?> readTransaction(int id) async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return FinancialTransaction.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<int> updateTransaction(FinancialTransaction transaction) async {
    final db = await database;
    return db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Obtener balance por categoría
  Future<double> getCategoryBalance(int categoryId) async {
    final db = await database;
    final transactionResult = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'income' THEN amount ELSE -amount END) as balance
      FROM transactions
      WHERE categoryId = ? AND (subcategoryId IS NULL OR subcategoryId = 0)
    ''', [categoryId]);

    final movementResult = await db.rawQuery('''
      SELECT SUM(balance) as total
      FROM subcategories
      WHERE categoryId = ?
    ''', [categoryId]);

    final txnBalance = (transactionResult.first['balance'] as num?)?.toDouble() ?? 0.0;
    final movementBalance = (movementResult.first['total'] as num?)?.toDouble() ?? 0.0;
    return txnBalance + movementBalance;
  }

  // Obtener balance total
  Future<double> getTotalBalance() async {
    final db = await database;
    final transactionResult = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'income' THEN amount ELSE -amount END) as balance
      FROM transactions
      WHERE excludeFromTotal = 0 AND (subcategoryId IS NULL OR subcategoryId = 0)
    ''');

    final movementResult = await db.rawQuery('''
      SELECT SUM(balance) as total
      FROM subcategories
    ''');

    final excludedMovementResult = await db.rawQuery('''
      SELECT 
        SUM(CASE WHEN type = 'income' THEN amount ELSE -amount END) as balance
      FROM transactions
      WHERE excludeFromTotal = 1 AND subcategoryId IS NOT NULL AND subcategoryId != 0
    ''');

    final txnBalance = (transactionResult.first['balance'] as num?)?.toDouble() ?? 0.0;
    final movementBalance = (movementResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final excludedMovementBalance =
        (excludedMovementResult.first['balance'] as num?)?.toDouble() ?? 0.0;

    return txnBalance + movementBalance - excludedMovementBalance;
  }

  // CRUD para Shopping Cart Items
  Future<int> addCartItem(ShoppingCartItem item) async {
    final db = await database;
    return await db.insert('shopping_cart_items', item.toMap());
  }

  Future<List<ShoppingCartItem>> getAllCartItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('shopping_cart_items', orderBy: 'dateAdded DESC');
    return List.generate(maps.length, (i) => ShoppingCartItem.fromMap(maps[i]));
  }

  Future<int> updateCartItem(ShoppingCartItem item) async {
    final db = await database;
    return await db.update('shopping_cart_items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> deleteCartItem(int id) async {
    final db = await database;
    return await db.delete('shopping_cart_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearCart() async {
    final db = await database;
    return await db.delete('shopping_cart_items');
  }

  Future<double> getCartTotal() async {
    final db = await database;
    final result = await db.rawQuery('SELECT SUM(price * quantity) as total FROM shopping_cart_items');
    return (result.first['total'] as double?) ?? 0.0;
  }

  Future<double> applyInterestForSubcategory(int subcategoryId, {String source = 'auto'}) async {
    final db = await database;
    final accountRows = await db.query(
      'subcategories',
      where: 'id = ? AND isInterestBearing = 1 AND interestRate > 0',
      whereArgs: [subcategoryId],
      limit: 1,
    );

    if (accountRows.isEmpty) {
      return 0.0;
    }

    final account = accountRows.first;
    final double balance = (account['balance'] as num?)?.toDouble() ?? 0.0;
    final double rate = (account['interestRate'] as num?)?.toDouble() ?? 0.0;

    final now = DateTime.now();
    final DateTime todayNoon = DateTime(now.year, now.month, now.day, 12);
    final DateTime targetCutoff = now.isAfter(todayNoon)
        ? todayNoon
        : todayNoon.subtract(const Duration(days: 1));

    if (balance <= 0 || rate <= 0) {
      await db.update(
        'subcategories',
        {
          'lastInterestApplied': targetCutoff.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [subcategoryId],
      );
      return 0.0;
    }

    final String? createdDateRaw = account['createdDate'] as String?;
    final DateTime createdDate = createdDateRaw != null
        ? DateTime.tryParse(createdDateRaw) ?? DateTime.now()
        : DateTime.now();
    final String? lastAppliedRaw = account['lastInterestApplied'] as String?;
    DateTime baseline = lastAppliedRaw != null && lastAppliedRaw.isNotEmpty
        ? DateTime.tryParse(lastAppliedRaw) ?? createdDate
        : createdDate;
    baseline = DateTime(baseline.year, baseline.month, baseline.day, 12);

    if (!targetCutoff.isAfter(baseline)) {
      return 0.0;
    }

    final int days = targetCutoff.difference(baseline).inDays;
    if (days <= 0) {
      return 0.0;
    }

    // GAT es tasa efectiva anual, la tasa diaria correcta es:
    // dailyRate = (1 + GAT/100)^(1/365) - 1
    final double dailyRate = pow(1 + rate / 100, 1.0 / 365).toDouble() - 1.0;
    final double growthFactor = pow(1 + dailyRate, days).toDouble();
    final double newBalance = balance * growthFactor;
    final double interestEarned = newBalance - balance;
    final double interestToApply = interestEarned <= 0 ? 0.0 : interestEarned;

    final double roundedBalance = double.parse(newBalance.toStringAsFixed(2));
    final double roundedInterest = double.parse(interestToApply.toStringAsFixed(2));

    await db.update(
      'subcategories',
      {
        'balance': roundedBalance,
        'lastInterestApplied': targetCutoff.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [subcategoryId],
    );

    int? transactionId;

    if (roundedInterest > 0) {
      final transactionRows = await db.query(
        'transactions',
        where: 'subcategoryId = ? AND type = ? AND isInterestBearing = 1',
        whereArgs: [subcategoryId, 'income'],
        orderBy: 'date DESC',
        limit: 1,
      );

      if (transactionRows.isNotEmpty) {
        final transaction = transactionRows.first;
        final double currentAmount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
        final double updatedAmount = double.parse((currentAmount + roundedInterest).toStringAsFixed(2));

        await db.update(
          'transactions',
          {
            'amount': updatedAmount,
            'interestLastApplied': targetCutoff.toIso8601String(),
            'interestRate': rate,
          },
          where: 'id = ?',
          whereArgs: [transaction['id']],
        );
        transactionId = transaction['id'] as int?;
      }
    }

    if (roundedInterest > 0) {
      await db.insert('interest_logs', {
        'subcategoryId': subcategoryId,
        'transactionId': transactionId,
        'interestAmount': roundedInterest,
        'appliedRate': rate,
        'appliedAt': targetCutoff.toIso8601String(),
        'source': source,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }

    return roundedInterest;
  }

  Future<void> applyPendingInterest() async {
    final db = await database;
    final interestAccounts = await db.query(
      'subcategories',
      columns: ['id'],
      where: 'isInterestBearing = 1 AND interestRate > 0',
    );

    for (final account in interestAccounts) {
      final int? subcategoryId = account['id'] as int?;
      if (subcategoryId == null) {
        continue;
      }
      await applyInterestForSubcategory(subcategoryId, source: 'auto');
    }
  }

  // CRUD para Expense Templates
  Future<List<Map<String, dynamic>>> getAllExpenseTemplates() async {
    final db = await database;
    return await db.query('expense_templates', orderBy: '"order" ASC');
  }

  Future<int> updateExpenseTemplate(int id, Map<String, dynamic> template) async {
    final db = await database;
    return await db.update('expense_templates', template, where: 'id = ?', whereArgs: [id]);
  }

  // Obtener estadísticas de gastos
  Future<double> getTotalExpenses({DateTime? startDate, DateTime? endDate}) async {
    final db = await database;
    String query = 'SELECT SUM(amount) as total FROM transactions WHERE type = "expense" AND excludeFromTotal = 0';
    List<dynamic> args = [];

    if (startDate != null) {
      query += ' AND date >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      query += ' AND date <= ?';
      args.add(endDate.toIso8601String());
    }

    final result = await db.rawQuery(query, args);
    return (result.first['total'] as double?) ?? 0.0;
  }

  Future<double> getTotalIncome({DateTime? startDate, DateTime? endDate}) async {
    final db = await database;
    String query = 'SELECT SUM(amount) as total FROM transactions WHERE type = "income" AND excludeFromTotal = 0';
    List<dynamic> args = [];

    if (startDate != null) {
      query += ' AND date >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      query += ' AND date <= ?';
      args.add(endDate.toIso8601String());
    }

    final result = await db.rawQuery(query, args);
    return (result.first['total'] as double?) ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getFrequentExpenses({int limit = 5}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT description, COUNT(*) as frequency, AVG(amount) as avgAmount, SUM(amount) as totalAmount
      FROM transactions
      WHERE type = "expense" AND excludeFromTotal = 0
      GROUP BY description
      ORDER BY frequency DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory({DateTime? startDate, DateTime? endDate}) async {
    final db = await database;
    String query = '''
      SELECT c.name, c.icon, c.color, SUM(t.amount) as total
      FROM transactions t
      JOIN categories c ON t.categoryId = c.id
      WHERE t.type = "expense" AND t.excludeFromTotal = 0
    ''';
    List<dynamic> args = [];

    if (startDate != null) {
      query += ' AND t.date >= ?';
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      query += ' AND t.date <= ?';
      args.add(endDate.toIso8601String());
    }

    query += ' GROUP BY c.id ORDER BY total DESC';

    return await db.rawQuery(query, args);
  }

  // Configuración y seguridad de la aplicación
  Future<Map<String, dynamic>> getAppSettings() async {
    final db = await database;
    await _ensureDefaultSettings(db);
    final result = await db.query('app_settings', limit: 1);
    if (result.isNotEmpty) {
      return result.first;
    }
    return {
      'id': 1,
      'passwordEnabled': 0,
      'password': null,
    };
  }

  Future<bool> isPasswordProtectionEnabled() async {
    final settings = await getAppSettings();
    final rawValue = settings['passwordEnabled'];
    if (rawValue is int) {
      return rawValue == 1;
    }
    if (rawValue is bool) {
      return rawValue;
    }
    return false;
  }

  Future<String?> getAppPassword() async {
    final settings = await getAppSettings();
    final stored = settings['password'];
    if (stored is String) {
      return stored;
    }
    return null;
  }

  Future<void> updatePasswordProtection({required bool enabled, String? password}) async {
    final db = await database;
    await _ensureDefaultSettings(db);
    await db.update(
      'app_settings',
      {
        'passwordEnabled': enabled ? 1 : 0,
        'password': enabled ? password : null,
      },
      where: 'id = ?',
      whereArgs: const [1],
    );
  }

  Future<void> updateStoredPassword(String? password) async {
    final db = await database;
    await _ensureDefaultSettings(db);
    await db.update(
      'app_settings',
      {
        'password': password,
      },
      where: 'id = ?',
      whereArgs: const [1],
    );
  }

  Future<void> _ensureDefaultSettings(Database db) async {
    final current = await db.query('app_settings', limit: 1);
    if (current.isEmpty) {
      await db.insert(
        'app_settings',
        {
          'id': 1,
          'passwordEnabled': 0,
          'password': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
