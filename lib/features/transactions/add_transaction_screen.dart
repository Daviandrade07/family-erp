import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_feedback.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../categories/categories_screen.dart';
import '../../services/ai/ocr_service.dart';
import '../../services/ai/write_safety.dart';
import '../auth/auth_controller.dart';

final _accountsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(accountRepositoryProvider).all());

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _beneficiary = TextEditingController();
  final _tags = TextEditingController();

  TransactionType _type = TransactionType.expense;
  String _category = Categories.expense.first;
  DateTime _date = DateTime.now();
  String? _paymentMethod;
  String? _accountId;
  int _installments = 1;
  bool _busy = false;
  bool _scanning = false;
  ReceiptData? _receipt;

  static const _paymentMethods = [
    'Pix', 'Débito', 'Crédito', 'Dinheiro', 'Boleto', 'Transferência',
  ];

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _beneficiary.dispose();
    _tags.dispose();
    super.dispose();
  }

  /// OCR flow: photo → structured receipt → form auto-fill.
  Future<void> _scanReceipt() async {
    setState(() => _scanning = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
          source: ImageSource.camera, maxWidth: 1600);
      final fallback = photo ??
          await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
      if (fallback == null) return;

      final bytes = await fallback.readAsBytes();
      final receipt =
          await ref.read(ocrServiceProvider).scanReceipt(bytes);

      setState(() {
        _receipt = receipt;
        _type = TransactionType.expense;
        _category = 'Mercado';
        _amount.text = receipt.total.toStringAsFixed(2);
        _description.text =
            'Compra ${receipt.merchantName} (${receipt.items.length} itens)';
        _beneficiary.text =
            '${receipt.merchantName} · CNPJ ${receipt.cnpj}';
        _date = receipt.date;
      });
    } catch (e, st) {
      developer.log('receipt scan failed', name: 'tx', error: e, stackTrace: st);
      if (mounted) AppFeedback.error(context, humanizeError(e));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(authControllerProvider).profile;
    if (profile?.familyId == null) return;

    setState(() => _busy = true);
    try {
      final isCredit = _paymentMethod == 'Crédito';
      final tx = Transaction(
        familyId: profile!.familyId!,
        userId: profile.id,
        type: _type,
        amount: double.parse(_amount.text.replaceAll(',', '.')),
        category: _category,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        date: _date,
        paymentMethod: _paymentMethod,
        cardId: isCredit ? _accountId : null,
        accountId: isCredit ? null : _accountId,
        totalInstallments: _installments > 1 ? _installments : null,
        installmentNumber: _installments > 1 ? 1 : null,
        beneficiary: _beneficiary.text.trim().isEmpty
            ? null
            : _beneficiary.text.trim(),
        tags: _tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
      );
      await ref.read(transactionRepositoryProvider).insert(tx);

      // Receipt items feed the pantry price history via shopping automation.
      if (_receipt != null) {
        final shopping = ref.read(shoppingRepositoryProvider);
        for (final item in _receipt!.items) {
          await shopping.insertRow(ShoppingItem(
            familyId: profile.familyId!,
            itemName: item.name,
            quantity: item.quantity,
            status: 'bought',
            executionData: {
              'unit_price': item.unitPrice,
              'market': _receipt!.merchantName,
              'source': 'ocr',
              'bought_at': DateTime.now().toIso8601String(),
            },
          ).toInsert());
        }
      }

      if (mounted) {
        AppFeedback.success(context, 'Transação registrada.');
        context.pop();
      }
    } catch (e, st) {
      developer.log('transaction save failed', name: 'tx', error: e, stackTrace: st);
      if (mounted) {
        AppFeedback.error(context, humanizeError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(_accountsProvider);
    final allCats =
        ref.watch(familyCategoriesProvider).valueOrNull ?? const <Category>[];
    final famList = categoriesForType(allCats, _type).map((c) => c.name).toList();
    final categories = famList.isEmpty
        ? (_type == TransactionType.expense
            ? Categories.expense
            : Categories.revenue)
        : famList;
    if (!categories.contains(_category)) _category = categories.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Nova transação')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // OCR honesto: o botão só existe quando há leitura real de nota
            // (OCR_ENABLED). Sem isso, nada de scanner falso na interface.
            if (Env.ocrEnabled)
              OutlinedButton.icon(
                onPressed: _scanning ? null : _scanReceipt,
                icon: _scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.document_scanner_outlined,
                        color: AppColors.techBlue),
                label: Text(_scanning
                    ? 'Lendo nota fiscal...'
                    : 'Escanear nota fiscal (OCR)'),
              ),
            if (_receipt != null) ...[
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            size: 16, color: AppColors.neonGreen),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_receipt!.merchantName} · ${_receipt!.date.br}',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final item in _receipt!.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(
                                    '${item.quantity}x ${item.name}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall)),
                            Text(item.total.brl,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                    value: TransactionType.expense,
                    label: Text('Despesa'),
                    icon: Icon(Icons.arrow_outward_rounded)),
                ButtonSegment(
                    value: TransactionType.revenue,
                    label: Text('Receita'),
                    icon: Icon(Icons.arrow_downward_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  hintText: 'Valor', prefixText: 'R\$ '),
              validator: (v) {
                final parsed =
                    double.tryParse((v ?? '').replaceAll(',', '.'));
                return (parsed == null || parsed <= 0)
                    ? 'Informe um valor válido'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(hintText: 'Categoria'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(hintText: 'Descrição'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _beneficiary,
              decoration:
                  const InputDecoration(hintText: 'Beneficiário / Loja'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tags,
              decoration: const InputDecoration(
                  hintText: 'Tags separadas por vírgula'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(_date.br),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration:
                        const InputDecoration(hintText: 'Pagamento'),
                    items: [
                      for (final m in _paymentMethods)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            accounts.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : DropdownButtonFormField<String>(
                      value: _accountId,
                      decoration: const InputDecoration(
                          hintText: 'Conta / Cartão'),
                      items: [
                        for (final a in list)
                          DropdownMenuItem(
                              value: a.id, child: Text(a.name)),
                      ],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
            ),
            if (_paymentMethod == 'Crédito') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Parcelas'),
                  Expanded(
                    child: Slider(
                      value: _installments.toDouble(),
                      min: 1,
                      max: 24,
                      divisions: 23,
                      label: '${_installments}x',
                      onChanged: (v) =>
                          setState(() => _installments = v.round()),
                    ),
                  ),
                  Text('${_installments}x'),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
