import '../../data/models/models.dart';

/// Regras de validação de categorias — PURAS e testáveis (sem Supabase).

/// O nome está disponível para [type] entre as categorias NÃO arquivadas?
/// Case-insensitive; [excludingId] ignora a própria (ao editar). Nome vazio
/// nunca é válido.
bool categoryNameAvailable(
  String name,
  TransactionType type,
  List<Category> existing, {
  String? excludingId,
}) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  return !existing.any((c) =>
      c.id != excludingId &&
      c.type == type &&
      !c.archived &&
      c.name.trim().toLowerCase() == n);
}

/// Pode APAGAR de vez? Só categoria da família (não-padrão) e SEM uso.
/// Caso contrário, arquive (preserva o histórico).
bool canDeleteCategory(Category c, {required bool inUse}) =>
    !c.isDefault && !inUse;

/// Pode ARQUIVAR? Só as próprias (padrões nunca são arquivados/apagados).
bool canArchiveCategory(Category c) => !c.isDefault;
