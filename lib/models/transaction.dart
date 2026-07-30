import 'dart:convert';

class FinancialTransaction {
  final int? id;
  final int categoryId;
  final int? subcategoryId; // Nullable para compatibilidad con transacciones antiguas
  final double amount;
  final String description;
  final DateTime date;
  final String type; // 'income' o 'expense'
  final bool excludeFromTotal;
  final bool isInterestBearing;
  final double interestRate;
  final DateTime? interestLastApplied;
  final List<String> imagePaths;

  FinancialTransaction({
    this.id,
    required this.categoryId,
    this.subcategoryId,
    required this.amount,
    required this.description,
    required this.date,
    required this.type,
    this.excludeFromTotal = false,
    this.isInterestBearing = false,
    this.interestRate = 0.0,
    this.interestLastApplied,
    this.imagePaths = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'categoryId': categoryId,
      'subcategoryId': subcategoryId,
      'amount': amount,
      'description': description,
      'date': date.toIso8601String(),
      'type': type,
      'excludeFromTotal': excludeFromTotal ? 1 : 0,
      'isInterestBearing': isInterestBearing ? 1 : 0,
      'interestRate': interestRate,
      'interestLastApplied': interestLastApplied?.toIso8601String(),
      'imagePaths': jsonEncode(imagePaths),
    };
  }

  factory FinancialTransaction.fromMap(Map<String, dynamic> map) {
    return FinancialTransaction(
      id: map['id'],
      categoryId: map['categoryId'],
      subcategoryId: map['subcategoryId'],
      amount: map['amount'],
      description: map['description'],
      date: DateTime.parse(map['date']),
      type: map['type'],
      excludeFromTotal: _parseExcludeFlag(map['excludeFromTotal']),
      isInterestBearing: _parseExcludeFlag(map['isInterestBearing']),
      interestRate: _parseRate(map['interestRate']),
      interestLastApplied: _parseDate(map['interestLastApplied']),
      imagePaths: _parseImagePaths(map['imagePaths']),
    );
  }

  FinancialTransaction copyWith({
    int? id,
    int? categoryId,
    int? subcategoryId,
    double? amount,
    String? description,
    DateTime? date,
    String? type,
    bool? excludeFromTotal,
    bool? isInterestBearing,
    double? interestRate,
    DateTime? interestLastApplied,
    List<String>? imagePaths,
  }) {
    return FinancialTransaction(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      date: date ?? this.date,
      type: type ?? this.type,
      excludeFromTotal: excludeFromTotal ?? this.excludeFromTotal,
      isInterestBearing: isInterestBearing ?? this.isInterestBearing,
      interestRate: interestRate ?? this.interestRate,
      interestLastApplied: interestLastApplied ?? this.interestLastApplied,
      imagePaths: imagePaths ?? this.imagePaths,
    );
  }

  static bool _parseExcludeFlag(dynamic value) {
    if (value is int) {
      return value == 1;
    }
    if (value is bool) {
      return value;
    }
    return false;
  }

  static double _parseRate(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static List<String> _parseImagePaths(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }
    return const [];
  }
}
