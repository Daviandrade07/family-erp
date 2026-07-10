import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

class TransactionsState {
  const TransactionsState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.loading = false,
    this.error,
    this.filter = const TransactionFilter(),
  });

  final List<Transaction> items;
  final int page;
  final bool hasMore;
  final bool loading;
  final String? error;
  final TransactionFilter filter;

  TransactionsState copyWith({
    List<Transaction>? items,
    int? page,
    bool? hasMore,
    bool? loading,
    String? Function()? error,
    TransactionFilter? filter,
  }) =>
      TransactionsState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: error != null ? error() : this.error,
        filter: filter ?? this.filter,
      );
}

/// Infinite-scroll paginated feed with server-side filters.
class TransactionsController extends StateNotifier<TransactionsState> {
  TransactionsController(this._repo) : super(const TransactionsState()) {
    loadMore();
  }

  final TransactionRepository _repo;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, error: () => null);
    try {
      final newItems =
          await _repo.fetchPage(page: state.page, filter: state.filter);
      state = state.copyWith(
        items: [...state.items, ...newItems],
        page: state.page + 1,
        hasMore: newItems.length == TransactionRepository.pageSize,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: () => '$e');
    }
  }

  Future<void> applyFilter(TransactionFilter filter) async {
    state = TransactionsState(filter: filter);
    await loadMore();
  }

  Future<void> refresh() => applyFilter(state.filter);

  Future<void> delete(Transaction tx) async {
    await _repo.delete(tx.id!);
    state = state.copyWith(
        items: state.items.where((t) => t.id != tx.id).toList());
  }
}

final transactionsControllerProvider =
    StateNotifierProvider.autoDispose<TransactionsController, TransactionsState>(
        (ref) => TransactionsController(ref.watch(transactionRepositoryProvider)));
