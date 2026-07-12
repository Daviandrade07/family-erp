/// Contrato de domínio para uma futura integração regulada de Open Finance.
///
/// Este app não recebe senha bancária, não persiste token de banco no cliente e
/// não simula uma conexão. Um adaptador de parceiro, executado no servidor,
/// deve implementar [OpenFinanceGateway] quando houver contrato e credenciais.
enum OpenFinanceConnectionStatus {
  unavailable,
  awaitingConsent,
  active,
  expired,
  revoked,
  failed,
}

enum OpenFinanceScope { accounts, balances, transactions, creditCards }

class OpenFinanceConnection {
  const OpenFinanceConnection({
    required this.id,
    required this.status,
    required this.scopes,
    this.institutionName,
    this.expiresAt,
    this.lastSyncedAt,
  });

  final String id;
  final OpenFinanceConnectionStatus status;
  final Set<OpenFinanceScope> scopes;
  final String? institutionName;
  final DateTime? expiresAt;
  final DateTime? lastSyncedAt;

  bool get canRead => status == OpenFinanceConnectionStatus.active;
  bool get isRevocable =>
      status == OpenFinanceConnectionStatus.active ||
      status == OpenFinanceConnectionStatus.awaitingConsent;
}

/// A implementação real fica no backend e devolve uma URL de consentimento do
/// parceiro. O aplicativo abre essa URL; a autenticação acontece no banco.
abstract class OpenFinanceGateway {
  Future<Uri> beginConsent({required Set<OpenFinanceScope> scopes});
  Future<List<OpenFinanceConnection>> connections();
  Future<void> sync(String connectionId);
  Future<void> revoke(String connectionId);
}

/// Estado explícito antes da contratação de parceiro. Evita um botão que pareça
/// funcional quando não há integração regulada ativa.
class OpenFinanceUnavailableGateway implements OpenFinanceGateway {
  const OpenFinanceUnavailableGateway();

  Never _unavailable() => throw UnsupportedError(
      'Open Finance ainda não está disponível neste ambiente.');

  @override
  Future<Uri> beginConsent({required Set<OpenFinanceScope> scopes}) async =>
      _unavailable();

  @override
  Future<List<OpenFinanceConnection>> connections() async => const [];

  @override
  Future<void> revoke(String connectionId) async => _unavailable();

  @override
  Future<void> sync(String connectionId) async => _unavailable();
}
