import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../models/subcategory.dart';
import '../providers/finance_provider.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import 'movements_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  final FinancialCategory? preselectedCategory;
  final FinancialTransaction? transactionToEdit;
  final String initialType;

  const AddTransactionScreen({
    super.key,
    this.preselectedCategory,
    this.transactionToEdit,
    this.initialType = 'income',
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _interestRateController = TextEditingController();

  FinancialCategory? _selectedCategory;
  Subcategory? _selectedSubcategory;
  String _transactionType = 'income';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _excludeFromTotal = false;
  bool _didHydrateFromExisting = false;
  bool _isInterestBearingTransaction = false;
  bool _isApplyingInterest = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<String> _selectedImagePaths = [];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.preselectedCategory;
    _transactionType = widget.transactionToEdit?.type ?? widget.initialType;

    if (widget.transactionToEdit != null) {
      final transaction = widget.transactionToEdit!;
      _amountController.text = transaction.amount.toString();
      _descriptionController.text = transaction.description;
      _selectedDate = transaction.date;
      _excludeFromTotal = transaction.excludeFromTotal;
      _isInterestBearingTransaction =
          transaction.type == 'income' && transaction.isInterestBearing;
      if (transaction.interestRate > 0) {
        _interestRateController.text = transaction.interestRate.toStringAsFixed(2);
      }
      _selectedImagePaths.addAll(transaction.imagePaths);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didHydrateFromExisting || widget.transactionToEdit == null) {
      return;
    }

    final provider = context.read<FinanceProvider>();
    final transaction = widget.transactionToEdit!;

    if (_selectedCategory == null) {
      final matchingCategory = provider.categories
          .where((category) => category.id == transaction.categoryId)
          .toList();
      if (matchingCategory.isNotEmpty) {
        _selectedCategory = matchingCategory.first;
      }
    }

    if (transaction.subcategoryId != null && _selectedSubcategory == null) {
      final matchingSubcategory = provider.subcategories
          .where((subcategory) => subcategory.id == transaction.subcategoryId)
          .toList();
      if (matchingSubcategory.isNotEmpty) {
        _selectedSubcategory = matchingSubcategory.first;
      }
    }

    _didHydrateFromExisting = true;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _interestRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<FinanceProvider>();

    if (_selectedCategory == null && widget.preselectedCategory == null) {
      _selectedCategory = provider.categories.isNotEmpty ? provider.categories.first : null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.transactionToEdit == null ? Icons.add_circle_outline : Icons.edit_outlined,
              size: 20,
              color: AppTheme.accentBlue,
            ),
            const SizedBox(width: 10),
            Text(widget.transactionToEdit == null ? 'Nueva Transacción' : 'Editar Transacción'),
          ],
        ),
        actions: [
          if (_showSumarButton)
            TextButton(
              onPressed: _isApplyingInterest ? null : _handleApplyInterest,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.chromeLight,
              ),
              child: _isApplyingInterest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.chromeLight),
                      ),
                    )
                  : const Text('Sumar'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Selector de tipo de transacción
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.chromeMedium.withValues(alpha: 0.08),
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTypeButton('Ingreso', 'income', AppTheme.accentGreen),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTypeButton('Gasto', 'expense', AppTheme.accentRed),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Selector de categoría
              Text(
                'Categoría',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: AppTheme.backgroundCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.08))),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<FinancialCategory>(

                    value: _selectedCategory,
                    isExpanded: true,
                    dropdownColor: AppTheme.backgroundCard,
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.chromeMedium),
                    style: const TextStyle(color: AppTheme.chromeLight, fontSize: 16),
                    items: provider.categories.map((category) {
                      final color = Color(int.parse(category.color, radix: 16));
                      return DropdownMenuItem<FinancialCategory>(
                        value: category,
                        child: Row(
                          children: [
                            Icon(
                              _getIconData(category.icon),
                              color: color,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(category.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: widget.preselectedCategory == null
                        ? (value) {
                            setState(() {
                              _selectedCategory = value;
                              _selectedSubcategory = null; // Reset subcategory cuando cambia categoría
                            });
                          }
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Selector de movimiento vinculable
              if (_selectedCategory != null) ...[
                Row(
                  children: [
                    Text(
                      _transactionType == 'income'
                          ? 'Movimiento destino'
                          : 'Movimiento origen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Gestionar movimientos',
                      icon: const Icon(Icons.tune, size: 20, color: AppTheme.chromeMedium),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MovementsScreen(),
                          ),
                        );
                      },
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddSubcategoryDialog(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nuevo'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accentBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: AppTheme.backgroundCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.08))),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: DropdownButtonHideUnderline(
                    child: Consumer<FinanceProvider>(
                      builder: (context, provider, child) {
                        final subcategories = provider.getSubcategoriesByCategory(_selectedCategory!.id!);

                        if (_selectedSubcategory != null) {
                          final refreshed = subcategories
                              .where((subcategory) => subcategory.id == _selectedSubcategory!.id)
                              .toList();
                          if (refreshed.isEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _selectedSubcategory = null;
                              });
                            });
                          } else if (!identical(refreshed.first, _selectedSubcategory)) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _selectedSubcategory = refreshed.first;
                              });
                            });
                          }
                        }

                        if (subcategories.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'No hay movimientos en esta categoría.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppTheme.chromeMedium),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _showAddSubcategoryDialog(context),
                                  child: const Text('Crear'),
                                ),
                              ],
                            ),
                          );
                        }

                        return DropdownButton<Subcategory>(
                          value: _selectedSubcategory,
                          isExpanded: true,
                          dropdownColor: AppTheme.backgroundCard,
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.chromeMedium),
                          style: const TextStyle(color: AppTheme.chromeLight, fontSize: 16),
                          hint: Text(
                            _transactionType == 'income'
                                ? 'Selecciona dónde depositar'
                                : 'Selecciona de dónde debitar',
                          ),
                          items: subcategories.map((subcategory) {
                            Color accentColor;
                            if (subcategory.color != null) {
                              try {
                                accentColor = Color(int.parse(subcategory.color!, radix: 16));
                              } catch (_) {
                                accentColor = AppTheme.chromeMedium;
                              }
                            } else {
                              accentColor = AppTheme.chromeMedium;
                            }

                            return DropdownMenuItem<Subcategory>(
                              value: subcategory,
                              child: Row(
                                children: [
                                  Icon(
                                    subcategory.icon != null
                                        ? _getIconData(subcategory.icon!)
                                        : Icons.account_balance_wallet,
                                    color: accentColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      subcategory.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    FormatUtils.formatCurrency(subcategory.balance),
                                    style: TextStyle(
                                      color: subcategory.balance >= 0
                                          ? AppTheme.accentGreen
                                          : AppTheme.accentRed,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedSubcategory = value;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Campo de monto
              Text(
                'Monto',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.attach_money),
                  hintText: '0.00',
                ),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa un monto';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Ingresa un monto válido';
                  }
                  if (double.parse(value) < 0) {
                    return 'El monto no puede ser negativo';
                  }
                  return null;
                },
              ),

              if (widget.transactionToEdit != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _showAdjustAmountDialog(isAddition: true),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Sumar monto'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _showAdjustAmountDialog(isAddition: false),
                        icon: const Icon(Icons.remove, size: 18),
                        label: const Text('Restar monto'),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Opción para excluir del capital total
              Container(
                decoration: BoxDecoration(color: AppTheme.backgroundCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.08))),
                child: CheckboxListTile(
                  value: _excludeFromTotal,
                  onChanged: (value) {
                    setState(() {
                      _excludeFromTotal = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('No sumar al capital total'),
                  subtitle: const Text(
                    'Útil para registros informativos o montos que no afectan tu capital principal.',
                  ),
                  activeColor: AppTheme.accentBlue,
                  checkColor: Colors.white,
                ),
              ),

              const SizedBox(height: 24),

              if (_transactionType == 'income') ...[
                Container(
                  decoration: BoxDecoration(color: AppTheme.backgroundCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.08))),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        value: _isInterestBearingTransaction,
                        onChanged: (value) {
                          setState(() {
                            _isInterestBearingTransaction = value;
                            if (!value) {
                              _interestRateController.clear();
                            } else {
                              final currentRate = _selectedSubcategory?.interestRate ?? 0;
                              if (_interestRateController.text.isEmpty && currentRate > 0) {
                                _interestRateController.text = currentRate.toStringAsFixed(2);
                              }
                            }
                          });
                        },
                        title: const Text('Interés compuesto diario'),
                        subtitle: const Text(
                          'Aplica el GAT anual de la cuenta automáticamente cada día a las 12:00.',
                        ),
                        activeColor: AppTheme.accentBlue,
                      ),
                      if (_isInterestBearingTransaction)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextFormField(
                            controller: _interestRateController,
                            decoration: const InputDecoration(
                              labelText: 'GAT anual (%)',
                              prefixIcon: Icon(Icons.percent),
                              helperText: 'Ejemplo: 13',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,4}')),
                            ],
                            validator: (value) {
                              if (!_isInterestBearingTransaction) {
                                return null;
                              }
                              final sanitized = value?.replaceAll('%', '').replaceAll(',', '.').trim();
                              final parsed = sanitized != null && sanitized.isNotEmpty
                                  ? double.tryParse(sanitized)
                                  : null;
                              if (parsed == null || parsed <= 0) {
                                return 'Ingresa una tasa anual válida';
                              }
                              return null;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Campo de descripción
              Text(
                'Descripción',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.description),
                  hintText: 'Ej: Salario, compra, inversión...',
                ),
                maxLength: 100,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa una descripción';
                  }
                  if (value.length < 3) {
                    return 'La descripción debe tener al menos 3 caracteres';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              Text(
                'Referencias visuales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sube fotos o capturas para tenerlas como referencia local en esta transacción.',
                      style: TextStyle(
                        color: AppTheme.chromeMedium.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final path in _selectedImagePaths)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(path),
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                            ),
                          ),
                        InkWell(
                          onTap: _pickImages,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundCardLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.2)),
                            ),
                            child: const Icon(Icons.add_photo_alternate_outlined, size: 32),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Selector de fecha
              Text(
                'Fecha',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.backgroundCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.chromeMedium.withValues(alpha: 0.08))),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppTheme.chromeMedium),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm', 'es').format(_selectedDate),
                        style: const TextStyle(
                          color: AppTheme.chromeLight,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.chromeMedium),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Botón de guardar
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (_transactionType == 'income' 
                          ? AppTheme.accentGreen 
                          : AppTheme.accentRed).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveTransaction,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _transactionType == 'income' 
                        ? AppTheme.accentGreen 
                        : AppTheme.accentRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          widget.transactionToEdit == null ? 'Guardar Transacción' : 'Actualizar',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeButton(String label, String type, Color color) {
    final isSelected = _transactionType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _transactionType = type;
          _selectedSubcategory = null; // Reset al cambiar tipo
          if (type != 'income') {
            _isInterestBearingTransaction = false;
            _interestRateController.clear();
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'income' ? Icons.add_circle : Icons.remove_circle,
              color: isSelected ? Colors.white : color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    if (!mounted) return;
    
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.accentBlue,
              onPrimary: Colors.white,
              surface: AppTheme.backgroundCard,
              onSurface: AppTheme.chromeLight,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppTheme.accentBlue,
                onPrimary: Colors.white,
                surface: AppTheme.backgroundCard,
                onSurface: AppTheme.chromeLight,
              ),
            ),
            child: child!,
          );
        },
      );

      if (time != null && mounted) {
        setState(() {
          _selectedDate = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final amountValue = double.parse(_amountController.text);
      final bool interestEnabled = _transactionType == 'income' && _isInterestBearingTransaction;
      double interestRate = 0.0;

      if (interestEnabled) {
        if (_selectedSubcategory == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selecciona un movimiento para aplicar interés.')),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        final sanitized = _interestRateController.text
            .replaceAll('%', '')
            .replaceAll(',', '.')
            .trim();
        interestRate = double.tryParse(sanitized) ?? 0.0;

        if (interestRate <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ingresa un GAT anual válido mayor a 0.')),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      final transaction = FinancialTransaction(
        id: widget.transactionToEdit?.id,
        categoryId: _selectedCategory!.id!,
        subcategoryId: _selectedSubcategory?.id,
        amount: amountValue,
        description: _descriptionController.text.trim(),
        date: _selectedDate,
        type: _transactionType,
        excludeFromTotal: _excludeFromTotal,
        isInterestBearing: interestEnabled,
        interestRate: interestRate,
        interestLastApplied: interestEnabled
            ? (widget.transactionToEdit?.interestLastApplied ?? DateTime.now())
            : null,
        imagePaths: List<String>.from(_selectedImagePaths),
      );

      final provider = context.read<FinanceProvider>();
      
      if (widget.transactionToEdit == null) {
        await provider.addTransaction(transaction);
      } else {
        await provider.updateTransaction(transaction);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.transactionToEdit == null 
                  ? 'Transacción guardada' 
                  : 'Transacción actualizada',
            ),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      final pickedFiles = await _imagePicker.pickMultiImage();
      if (pickedFiles.isEmpty) {
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDir.path, 'local_images'));
      await imagesDir.create(recursive: true);

      final copiedPaths = <String>[];
      for (final file in pickedFiles) {
        if (file.path.isEmpty) {
          continue;
        }

        final destinationPath = path.join(
          imagesDir.path,
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}',
        );
        final sourceFile = File(file.path);
        if (await sourceFile.exists()) {
          await sourceFile.copy(destinationPath);
          copiedPaths.add(destinationPath);
        }
      }

      if (copiedPaths.isNotEmpty) {
        setState(() {
          for (final copiedPath in copiedPaths) {
            if (!_selectedImagePaths.contains(copiedPath)) {
              _selectedImagePaths.add(copiedPath);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las imágenes: $e')),
        );
      }
    }
  }

  Future<void> _showAdjustAmountDialog({required bool isAddition}) async {
    final controller = TextEditingController();
    final actionLabel = isAddition ? 'Sumar monto' : 'Restar monto';

    final delta = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(actionLabel),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.attach_money),
              hintText: '0.00',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isAddition ? AppTheme.accentGreen : AppTheme.accentRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final raw = controller.text.trim();
                final value = double.tryParse(raw);
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingresa un monto válido mayor a 0.')),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: Text(isAddition ? 'Sumar' : 'Restar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (delta == null || delta <= 0) {
      return;
    }

    final current = double.tryParse(_amountController.text) ?? 0.0;
    final updated = isAddition ? current + delta : current - delta;

    if (updated < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El resultado no puede ser negativo.')),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _amountController.text = updated.toStringAsFixed(2);
    });
  }

  bool get _showSumarButton {
    final transaction = widget.transactionToEdit;
    if (transaction == null) {
      return false;
    }

    final bool hasSubcategory = (transaction.subcategoryId ?? _selectedSubcategory?.id) != null;
    if (!hasSubcategory) {
      return false;
    }

    if (_transactionType != 'income') {
      return false;
    }

    return _isInterestBearingTransaction || transaction.isInterestBearing;
  }

  Future<void> _handleApplyInterest() async {
    final transaction = widget.transactionToEdit;
    final activeSubcategoryId = _selectedSubcategory?.id ?? transaction?.subcategoryId;

    if (transaction == null || activeSubcategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un movimiento válido para sumar interés.')),
      );
      return;
    }

    setState(() {
      _isApplyingInterest = true;
    });

    try {
      final provider = context.read<FinanceProvider>();
      final applied = await provider.applyInterestForTransaction(
        transaction.copyWith(subcategoryId: activeSubcategoryId),
        manual: true,
      );

      if (!mounted) {
        return;
      }

      if (applied > 0) {
        FinancialTransaction? updated;
        try {
          updated = provider.transactions.firstWhere((t) => t.id == transaction.id);
        } catch (_) {
          updated = null;
        }

        Subcategory? refreshedSubcategory;
        try {
          refreshedSubcategory = provider.subcategories.firstWhere(
            (subcategory) => subcategory.id == activeSubcategoryId,
          );
        } catch (_) {
          refreshedSubcategory = _selectedSubcategory;
        }

        setState(() {
          if (updated != null) {
            _amountController.text = updated.amount.toStringAsFixed(2);
            _isInterestBearingTransaction = updated.isInterestBearing;
          }
          if (refreshedSubcategory != null) {
            _selectedSubcategory = refreshedSubcategory;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Interés sumado: +${FormatUtils.formatCurrency(applied)}'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay interés pendiente por sumar.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al sumar interés: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingInterest = false;
        });
      }
    }
  }

  void _showAddSubcategoryDialog(BuildContext context) {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0.00');
    final provider = context.read<FinanceProvider>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nuevo Movimiento', style: TextStyle(color: AppTheme.chromeLight, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Nombre (ej: Nu Débito, BBVA Ahorro)',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: AppTheme.chromeMedium.withValues(alpha: 0.6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: const TextStyle(color: AppTheme.chromeLight, fontWeight: FontWeight.w600),
              maxLength: 50,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Saldo Inicial (MXN)',
                prefixIcon: Icon(Icons.attach_money, color: AppTheme.chromeMedium.withValues(alpha: 0.6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              style: const TextStyle(color: AppTheme.chromeLight, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ingresa un nombre')),
                );
                return;
              }

              final balance = double.tryParse(balanceController.text) ?? 0.0;

              final subcategory = Subcategory(
                categoryId: _selectedCategory!.id!,
                name: name,
                balance: balance,
                order: provider.getSubcategoriesByCategory(_selectedCategory!.id!).length,
              );

              try {
                await provider.addSubcategory(subcategory);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Movimiento agregado'),
                      backgroundColor: AppTheme.accentGreen,
                    ),
                  );
                  setState(() {
                    // Actualizar UI para que aparezca en el dropdown
                  });
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Agregar'),
          ),
        ],
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
