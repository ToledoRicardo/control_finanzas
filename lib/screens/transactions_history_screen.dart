import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../providers/finance_provider.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';

class TransactionsHistoryScreen extends StatelessWidget {
  const TransactionsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 20, color: AppTheme.accentPurple),
            SizedBox(width: 10),
            Text('Historial de Transacciones'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<FinanceProvider>().loadData(),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Consumer<FinanceProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final transactions = provider.transactions;
          final categories = provider.categories;

          if (transactions.isEmpty) {
            return _buildEmptyState();
          }

          // Agrupar transacciones por fecha
          final groupedTransactions = _groupTransactionsByDate(transactions);
          final sortedDates = groupedTransactions.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDates.length,
            itemBuilder: (context, index) {
              final date = sortedDates[index];
              final dayTransactions = groupedTransactions[date]!;
              
              return _buildDateGroup(
                context,
                date,
                dayTransactions,
                categories,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 36,
              color: AppTheme.accentBlue.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No hay transacciones',
            style: TextStyle(
              color: AppTheme.chromeMedium.withValues(alpha: 0.7),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Comienza agregando tu primera transacción',
            style: TextStyle(
              color: AppTheme.chromeMedium.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<FinancialTransaction>> _groupTransactionsByDate(
    List<FinancialTransaction> transactions,
  ) {
    final Map<String, List<FinancialTransaction>> grouped = {};
    final dateFormatter = DateFormat('yyyy-MM-dd');

    for (var transaction in transactions) {
      final dateKey = dateFormatter.format(transaction.date);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(transaction);
    }

    return grouped;
  }

  Widget _buildDateGroup(
    BuildContext context,
    String dateKey,
    List<FinancialTransaction> transactions,
    List<FinancialCategory> categories,
  ) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final transactionDate = DateTime(date.year, date.month, date.day);

    String dateLabel;
    if (transactionDate == today) {
      dateLabel = 'Hoy';
    } else if (transactionDate == yesterday) {
      dateLabel = 'Ayer';
    } else {
      dateLabel = DateFormat('EEEE, d MMMM yyyy', 'es').format(date);
      dateLabel = dateLabel[0].toUpperCase() + dateLabel.substring(1);
    }

    // Calcular totales del día
    double totalIncome = 0;
    double totalExpense = 0;
    for (var transaction in transactions) {
      if (transaction.type == 'income') {
        totalIncome += transaction.amount;
      } else {
        totalExpense += transaction.amount;
      }
    }
    final dailyBalance = totalIncome - totalExpense;
    final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.steelCard(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        color: AppTheme.chromeLight,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${transactions.length} transacción${transactions.length != 1 ? 'es' : ''}',
                      style: TextStyle(
                        color: AppTheme.chromeMedium.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatter.format(dailyBalance),
                    style: TextStyle(
                      color: dailyBalance >= 0 ? AppTheme.accentGreen : AppTheme.accentRed,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+${formatter.format(totalIncome)}',
                        style: TextStyle(
                          color: AppTheme.accentGreen.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '-${formatter.format(totalExpense)}',
                        style: TextStyle(
                          color: AppTheme.accentRed.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        ...transactions.map((transaction) {
          final category = categories.firstWhere(
            (c) => c.id == transaction.categoryId,
            orElse: () => FinancialCategory(
              name: 'Desconocida',
              icon: 'account_balance_wallet',
              color: 'FF95A5A6',
              order: 999,
            ),
          );
          return _buildTransactionItem(context, transaction, category);
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTransactionItem(
    BuildContext context,
    FinancialTransaction transaction,
    FinancialCategory category,
  ) {
    final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final timeFormatter = DateFormat('HH:mm', 'es');
    final isIncome = transaction.type == 'income';
    final categoryColor = Color(int.parse(category.color, radix: 16));

    return Dismissible(
      key: Key('transaction_${transaction.id}'),
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accentRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 24),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.backgroundCard,
            title: const Text(
              'Confirmar eliminación',
              style: TextStyle(color: AppTheme.chromeLight),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Deseas eliminar esta transacción?',
                  style: TextStyle(color: AppTheme.chromeMedium),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundCardLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.description,
                        style: const TextStyle(
                          color: AppTheme.chromeLight,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatter.format(transaction.amount),
                        style: TextStyle(
                          color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        await context.read<FinanceProvider>().deleteTransaction(transaction.id!);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Transacción eliminada'),
              backgroundColor: AppTheme.accentRed,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Deshacer',
                textColor: Colors.white,
                onPressed: () {
                  // Aquí podrías implementar funcionalidad de deshacer
                },
              ),
            ),
          );
        }
      },
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddTransactionScreen(
                transactionToEdit: transaction,
                preselectedCategory: category,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.chromeMedium.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              // Icono de categoría
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getIconData(category.icon),
                  color: categoryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              
              // Información de la transacción
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (transaction.imagePaths.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          height: 64,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: transaction.imagePaths.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final path = transaction.imagePaths[index];
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(path),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    Text(
                      transaction.description,
                      style: const TextStyle(
                        color: AppTheme.chromeLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category.name,
                            style: TextStyle(
                              color: categoryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: AppTheme.chromeMedium.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeFormatter.format(transaction.date),
                          style: TextStyle(
                            color: AppTheme.chromeMedium.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Monto e indicador de edición
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? '+' : '-'} ${formatter.format(transaction.amount)}',
                    style: TextStyle(
                      color: isIncome ? AppTheme.accentGreen : AppTheme.accentRed,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.chromeMedium.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: AppTheme.chromeMedium.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconData(String iconName) {
    final iconMap = {
      'account_balance': Icons.account_balance,
      'trending_up': Icons.trending_up,
      'currency_bitcoin': Icons.currency_bitcoin,
      'show_chart': Icons.show_chart,
      'handshake': Icons.handshake,
      'home': Icons.home,
      'payments': Icons.payments,
      'inventory_2': Icons.inventory_2,
      'account_balance_wallet': Icons.account_balance_wallet,
    };
    return iconMap[iconName] ?? Icons.account_balance_wallet;
  }
}
