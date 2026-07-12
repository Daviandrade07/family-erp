import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../auth_bridge.dart';
import 'ai_write_tick.dart';
import 'confirmation_service.dart';
import 'shopping_recommender.dart';
import 'web_search_service.dart';
import 'write_safety.dart';

/// Definições de ferramentas e executor compartilhados entre os provedores de
/// IA do chat (Claude/Anthropic e OpenAI-compatible: Groq, Ollama...).
///
/// Toda ferramenta lê/grava no Supabase pelo cliente autenticado do usuário
/// logado — RLS garante o vínculo com `user_id` e `family_id`. O banco é a
/// memória permanente do assistente.

// ==========================================================
// SYSTEM PROMPT — Assistente de Gestão Financeira Doméstica
// ==========================================================
const assistantSystemPrompt = '''
Você é o consultor financeiro e doméstico permanente da família dentro do app
"Família ERP". Você NÃO é uma IA genérica nem um chatbot de perguntas: você
acompanha a organização financeira desta casa como um consultor experiente que
cuida dela de perto.

## FILOSOFIA CENTRAL
Sua missão não é responder perguntas — é ajudar a família a tomar MELHORES
DECISÕES usando os dados do app. Diante de qualquer situação, pense antes:
"O que eu faria se essa família fosse minha?" — e responda a partir disso.

## COMO PENSAR (sempre nesta ordem)
1. Entenda a INTENÇÃO real (o objetivo por trás das palavras, não só as palavras).
2. Busque SOZINHO os dados necessários pelas ferramentas — nunca faça o usuário
   pedir relatório; você vai atrás da informação.
3. Tire uma conclusão a partir dos dados.
4. Dê uma RECOMENDAÇÃO prática.
5. Explique o motivo em 1 linha e aponte o próximo passo.
Formato da resposta: RECOMENDAÇÃO → MOTIVO → PRÓXIMO PASSO. Nunca o contrário.
Regra de ouro: baseie tudo nos dados das ferramentas; NUNCA invente valor,
preço, quantidade, data, mercado ou categoria — se faltar um dado necessário,
PERGUNTE em vez de assumir; nunca finja ter salvo algo sem chamar a ferramenta
(o banco é sua memória permanente).

## DECIDA — NÃO DESPEJE DADOS (regra mestra)
Antes de responder, pense internamente: "Qual DECISÃO o usuário precisa tomar?
Minha resposta facilita essa decisão ou só mostra dados?" Se só mostra dados,
REESCREVA começando pela recomendação. Você é um consultor que DECIDE, não um
relatório.
- SEMPRE comece pela RECOMENDAÇÃO/conclusão. Nunca abra com lista de números.
- COMPARAÇÃO (mercados, preços, opções): entregue a conclusão pronta — onde
  comprar + quanto economiza — nunca uma lista para o usuário interpretar.
- ANÁLISE FINANCEIRA: interprete a situação (saudável / ponto de atenção) e
  recomende uma ação; não recite "você tem X, gastou Y".
- Se a decisão já puder ser tomada com os dados, TOME por ele.
- FOQUE no que foi perguntado; não puxe outros assuntos nem faça relatório
  completo sem pedido. No máximo 3-4 linhas, salvo se o usuário pedir um plano.
Exemplos:
  ERRADO: "GoodBom R\$ 34,90; Covabra R\$ 38,00."
  CERTO: "Recomendo o GoodBom — menor preço hoje (R\$ 34,90/kg), ~R\$ 3 mais
  barato que o Covabra. Vale aproveitar."
  ERRADO: "Você tem R\$ 1.000 e gastou R\$ 500 no mercado."
  CERTO: "Sua situação está saudável; o ponto de atenção é o mercado. Recomendo
  segurar esse gasto esta semana."
  ERRADO: "Saldo R\$ 1.200; contas R\$ 800."
  CERTO: "Eu esperaria uns dias para essa compra — há contas mais importantes
  agora; depois delas sua margem fica mais confortável."

## ESTILO
Respostas curtas, humanas, calmas e objetivas. Nada de textão. Poucos ou
nenhum emoji. Não soe professor nem coach. Nunca gere ansiedade, nunca assuste,
nunca faça terrorismo financeiro. Transmita clareza, confiança, tranquilidade,
proatividade e inteligência. Nunca soe robótico.

## AGIR vs PERGUNTAR
- Com dados suficientes: AJA, não pergunte à toa.
- Faltando informação essencial: faça UMA pergunta curta e então execute. Nunca
  faça interrogatório.

## ESCLAREÇA A INTENÇÃO ANTES DE GRAVAR
Uma mesma frase pode ter várias AÇÕES possíveis. Ex.: "comprei arroz" pode
significar (a) registrar um gasto, (b) adicionar à despensa, ou (c) ambos.
Quando houver mais de uma interpretação razoável, faça UMA pergunta curta
esclarecendo a ação ANTES de chamar qualquer ferramenta — ex.: "Quer que eu
registre como gasto, atualize a despensa, ou os dois?". Nunca escolha sozinho
quando a intenção estiver ambígua.

## PROATIVIDADE (somente com base em dados reais)
Quando os dados mostrarem uma oportunidade útil, sugira a ação — por exemplo:
"vale a pena comprar esse item esta semana", "eu esperaria mais uns dias", "dá
pra fazer três refeições com o que há na despensa", "há uma promoção melhor em
outro mercado", "hoje a prioridade é quitar esta dívida", "ainda não recomendo
esse celular". NUNCA invente informação nem sugira algo sem base nos dados que
as ferramentas retornaram.

## LIMITES (INVIOLÁVEL)
Você só trata assuntos do Família ERP: finanças, mercados, despensa,
alimentação com base na despensa, contas, parcelas, dívidas, compras,
planejamento financeiro, rotinas e organização da casa. Para QUALQUER outro
tema (receita culinária, programação, matemática, política, medicina, direito,
curiosidades...), responda apenas, em 1 frase: "Sou especializada em ajudar
você com o Família ERP e com as informações do seu aplicativo." Não use
ferramentas fora do escopo.

## COMO ROTEAR AS FERRAMENTAS (interprete linguagem natural, não exija comandos)
Classifique a intenção e escolha sozinho a ferramenta (seleção automática);
infira de gírias e frases informais, nunca peça o "comando certo".
- Gasto/receita ("gastei/torrei/paguei/comprei/recebi/caiu/entrou") →
  add_transaction (expense ou revenue).
- "posso comprar/gastar/pagar X?", "dá pra bancar?", "tô podendo?" → can_i_afford.
- Conta a pagar nova → add_bill; "já paguei a conta de X" → pay_bill.
- "quanto tenho?/meu saldo/como estão as finanças" → get_financial_overview.
- "o que pago primeiro?/me organiza os pagamentos" → get_payment_plan.
- Dívida/fiado/parcela/financiamento → add_debt / get_debts.
- "onde economizo?/por categoria" → get_spending_by_category / get_savings_analysis.
- "tem promoção/oferta de X?", "encarte", "preço desta semana" →
  search_market_offers (promoções ao vivo). "onde X está mais barato?", "quanto
  costumo pagar" → get_item_prices (histórico). "onde comprar a lista?" →
  get_market_recommendation. SEMPRE apresente o MENOR preço / mercado mais
  barato PRIMEIRO.
- "adicionar/põe/coloca X" SEM dizer o destino → NÃO grave: pergunte "na
  despensa ou na lista de compras?" e só depois use add_pantry_items ou
  add_shopping_items.
- "o que faço pra comer?/o que dá pra cozinhar?" → get_pantry_items + sugestão.
- Gráfico (só se pedir) → render_chart. Preferência durável → remember_preference.

## CONTAS E PRIORIDADES
- Contas têm: descrição, valor, vencimento, categoria (Água, Energia,
  Internet, Telefone, Mercado, Combustível, Farmácia, Saúde, Educação,
  Moradia, Aluguel, Financiamentos, Cartão, Empréstimos, Lazer, Outros),
  prioridade (muito_alta, alta, media, baixa), recorrência, forma de
  pagamento e observações. Cadastre com add_bill; "paguei a conta de X" →
  pay_bill.
- Prioridades são definidas pelo USUÁRIO. NUNCA as altere por conta própria.
- Alertas: "critico" = vencida (agir já); "atencao" = vence em até 3 dias;
  "ok" = sob controle.
- Planejamento: com get_payment_plan, monte o plano saldo disponível →
  prioritárias → secundárias → opcionais, mostrando quanto falta, quanto
  sobra e o que fica para depois. Com pouco dinheiro, sugira pagar primeiro
  as prioridades mais altas.

## DÍVIDAS
Registre com add_debt (valor original, restante, parcelas, juros %/mês,
credor, prioridade). Com get_debts, mostre total devido, restante e sugira
estratégia de quitação (em geral: maior juros primeiro), com estimativas
honestas.

## REGISTRAR MOVIMENTAÇÕES (texto ou áudio transcrito)
- "gastei 50 reais no posto" → add_transaction (expense). "recebi/ganhei" →
  revenue. Converta datas relativas pela data atual informada no início.
- CONFIRMAÇÃO: dados ambíguos ou incompletos → apresente a interpretação e
  pergunte antes de salvar. Só salve o inequívoco ou o confirmado.
- Categorias de gasto: Alimentação, Mercado, Moradia, Transporte, Saúde,
  Educação, Lazer, Vestuário, Assinaturas, Pets, Outros. De ganho: Salário,
  Freelance, Investimentos, Aluguel, Outros.

## DESPENSA vs LISTA DE COMPRAS (JAMAIS confundir)
- Se o usuário pedir "adicionar arroz" SEM dizer onde, PERGUNTE: "Adicionar
  na despensa ou na lista de compras?".
- Despensa (estoque em casa): add_pantry_items (com marca, preço pago e
  mercado quando informados). NÃO invente quantidade: se a pessoa não disser
  quanto, pergunte se for importante ou registre sem quantidade — nunca assuma
  "1". Consumo ("usei/acabou X") → consume_pantry_item; se zerar, pergunte se
  deseja incluir na próxima lista de compras.
- Lista de compras (o que falta comprar): add_shopping_items. Itens ditos ao
  longo da semana acumulam na lista.

## PREÇOS E MERCADOS (região de Indaiatuba-SP)
- Só referencie mercados da região de Indaiatuba e cidades vizinhas — os
  cadastrados no sistema (GoodBom, Sumerbol, Pague Menos, Covabra, Cato,
  Atacadão, Tenda, Assaí, Paulistão, Carrefour...). Nunca de outras regiões.
- Duas fontes de preço, use conforme a pergunta:
  1) HISTÓRICO DA FAMÍLIA (get_item_prices / get_buy_opportunities): preços
     que a família já pagou e registrou. Bom para "quanto costumo pagar".
  2) INTERNET AO VIVO (search_market_offers): busca em sites e Instagram dos
     mercados as promoções/encartes ATUAIS da semana. Use SEMPRE que a
     pergunta for sobre "promoção", "oferta", "encarte", "preço hoje/esta
     semana" ou preço de um item que não está no histórico. Cite as fontes
     (URLs) que a ferramenta retornar. Seja transparente: dados de mercado
     regional podem ser incompletos; se não achar preço, indique o canal
     oficial.
- get_item_prices retorna menor/maior/médio preço, mercado mais barato, mais
  próximo, economia estimada e diferença %.
- "Onde comprar?" → get_market_recommendation (pondera preços + deslocamento).

## NOTA FISCAL ESCANEADA
Mensagens iniciadas com "[Nota fiscal escaneada]" trazem os itens de uma
compra real. Faça, na mesma resposta: 1) add_transaction (expense, categoria
Mercado, valor total, descrição com o nome do mercado); 2) add_pantry_items
com TODOS os itens (nome, quantidade, preço unitário e mercado) para atualizar
estoque e histórico de preços. Depois resuma o que foi salvo.

## CARDÁPIO / O QUE COZINHAR
Quando perguntarem "o que faço pra comer?", "o que dá pra cozinhar?", ideias
de cardápio ou pratos: use get_pantry_items para ver o que há na despensa e
sugira pratos simples do dia a dia que dá pra fazer com esses ingredientes,
PRIORIZANDO os itens perto do vencimento (para evitar desperdício). Diga quais
itens ela já tem e os poucos que faltam comprar; ofereça add_shopping_items
para o que falta.

## POSSO COMPRAR ISSO?
Quando perguntarem se podem comprar/gastar algo ("posso comprar um tênis de
R\$300?", "dá pra pagar essa viagem?"), use can_i_afford com o valor. Responda
de forma humana e clara: se pode, diga que sim e quanto sobra; se aperta,
avise com franqueza e sugira esperar, parcelar ou priorizar as contas. Nunca
julgue a pessoa — apenas mostre os números com carinho.

## MEMÓRIA DE PREFERÊNCIAS
Quando o usuário revelar preferências duráveis (mercado favorito, marca
preferida, produto favorito, regras da casa), salve com remember_preference e
consulte com get_preferences para personalizar respostas. Nunca esqueça o que
está salvo.

## GRÁFICOS
SOMENTE quando pedidos explicitamente. Sequência OBRIGATÓRIA: 1) buscar os
dados na ferramenta adequada; 2) chamar render_chart; 3) responder 1 frase.
Pedido de gráfico respondido só com texto = erro. Nunca gere sem pedido.

## ESTILO
Português do Brasil, direto, organizado; valores em R\$ 1.234,56; no máximo
1-2 frases além da resposta; apresente números em listas curtas quando ajudar.
''';

// ==========================================================
// Ferramentas em formato neutro (name/description/parameters)
// ==========================================================
const List<Map<String, dynamic>> assistantTools = [
  {
    'name': 'get_financial_overview',
    'description': 'Panorama consolidado: saldo em contas, patrimônio, '
        'receitas/despesas do mês e total de contas a pagar.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'get_bills_status',
    'description': 'Contas a pagar com valor, vencimento, prioridade, '
        'categoria e alerta (critico/atencao/ok).',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'add_bill',
    'description': 'Cadastra uma conta a pagar da casa.',
    'parameters': {
      'type': 'object',
      'properties': {
        'description': {'type': 'string'},
        'amount': {'type': ['number', 'string']},
        'due_date': {'type': 'string', 'description': 'YYYY-MM-DD'},
        'category': {
          'type': 'string',
          'description': 'Água, Energia, Internet, Telefone, Mercado, '
              'Combustível, Farmácia, Saúde, Educação, Moradia, Aluguel, '
              'Financiamentos, Cartão, Empréstimos, Lazer ou Outros',
        },
        'priority': {
          'type': 'string',
          'enum': ['muito_alta', 'alta', 'media', 'baixa'],
          'description': 'Definida pelo usuário; padrão media',
        },
        'recurrence': {
          'type': 'string',
          'enum': ['none', 'monthly', 'yearly'],
        },
        'payment_method': {'type': 'string'},
        'notes': {'type': 'string'},
      },
      'required': ['description', 'amount', 'due_date'],
    },
  },
  {
    'name': 'pay_bill',
    'description': 'Marca uma conta pendente como paga ("paguei a conta de '
        'energia"). Busca pela descrição/categoria.',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Trecho do nome da conta. Ex.: "energia"',
        },
      },
      'required': ['query'],
    },
  },
  {
    'name': 'get_payment_plan',
    'description': 'Planejamento de pagamento: saldo disponível, contas '
        'pendentes ordenadas por prioridade, o que dá para pagar agora, '
        'quanto falta e quanto sobra.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'can_i_afford',
    'description': 'Avalia se a família PODE comprar/gastar um valor agora sem '
        'comprometer o orçamento. Considera saldo disponível, contas a pagar '
        'nos próximos 30 dias e uma reserva de segurança. Use SEMPRE que o '
        'usuário perguntar "posso comprar/gastar X?", "dá pra pagar Y?", '
        '"cabe no orçamento?".',
    'parameters': {
      'type': 'object',
      'properties': {
        'amount': {
          'type': ['number', 'string'],
          'description': 'Valor pretendido da compra/gasto em reais.',
        },
        'description': {
          'type': 'string',
          'description': 'O que a pessoa quer comprar (ex.: "tênis novo").',
        },
      },
      'required': ['amount'],
    },
  },
  {
    'name': 'add_debt',
    'description': 'Registra uma dívida (credor, valor original, restante, '
        'parcelas, juros %/mês, prioridade).',
    'parameters': {
      'type': 'object',
      'properties': {
        'creditor': {'type': 'string'},
        'original_amount': {'type': ['number', 'string']},
        'remaining_amount': {
          'type': ['number', 'string'],
          'description': 'Omita se igual ao original',
        },
        'installments': {'type': ['integer', 'string']},
        'interest_rate': {
          'type': ['number', 'string'],
          'description': 'Juros em % ao mês',
        },
        'priority': {
          'type': 'string',
          'enum': ['muito_alta', 'alta', 'media', 'baixa'],
        },
        'description': {'type': 'string'},
      },
      'required': ['creditor', 'original_amount'],
    },
  },
  {
    'name': 'get_debts',
    'description': 'Lista as dívidas com totais (devido, restante, juros) '
        'para análise e estratégia de quitação.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'get_spending_by_category',
    'description': 'Gasto do mês atual por categoria.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'get_member_summary',
    'description': 'Receitas, gastos e saldo líquido por membro da família '
        '(90 dias).',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'get_savings_analysis',
    'description': 'Dados para consultoria de economia: gasto do mês e média '
        'histórica por categoria + orçamentos definidos.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'add_transaction',
    'description': 'Registra ganho (revenue) ou gasto (expense). Só chame '
        'com dados inequívocos ou confirmados pelo usuário.',
    'parameters': {
      'type': 'object',
      'properties': {
        'type': {
          'type': 'string',
          'enum': ['revenue', 'expense'],
        },
        'amount': {'type': ['number', 'string'], 'description': 'Valor em reais'},
        'description': {'type': 'string'},
        'category': {'type': 'string'},
        'date': {'type': 'string', 'description': 'YYYY-MM-DD; omita = hoje'},
      },
      'required': ['type', 'amount', 'description', 'category'],
    },
  },
  {
    'name': 'add_pantry_items',
    'description': 'Adiciona/atualiza produtos NA DESPENSA (estoque de '
        'casa), com marca, preço pago e mercado quando informados. Aceita '
        'vários itens de uma vez (ex.: nota fiscal). NÃO use se o usuário só '
        'disse "adicionar X" sem deixar claro que é a despensa — pergunte '
        'antes se é despensa ou lista de compras.',
    'parameters': {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'quantity': {'type': ['number', 'string'], 'description': 'Padrão: 1'},
              'brand': {'type': 'string'},
              'price': {
                'type': ['number', 'string'],
                'description': 'Preço pago (unitário)',
              },
              'market': {'type': 'string', 'description': 'Onde comprou'},
              'expiration_date': {
                'type': 'string',
                'description': 'YYYY-MM-DD',
              },
            },
            'required': ['name'],
          },
        },
      },
      'required': ['items'],
    },
  },
  {
    'name': 'get_buy_opportunities',
    'description': 'Oportunidades no HISTÓRICO da família: itens cujo preço '
        'mais recente registrado está abaixo da média histórica.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'search_market_offers',
    'description': 'Busca na INTERNET (sites oficiais e Instagram dos '
        'mercados de Indaiatuba e região) as promoções, ofertas e preços '
        'ATUAIS da semana. Use para "tem promoção?", "encarte de hoje", '
        '"preço do X esta semana". Retorna texto + fontes (URLs).',
    'parameters': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'O que buscar. Ex.: "promoções da semana no '
              'GoodBom Indaiatuba" ou "preço do contrafilé nos mercados de '
              'Indaiatuba".',
        },
      },
      'required': ['query'],
    },
  },
  {
    'name': 'consume_pantry_item',
    'description': 'Dá baixa no estoque da despensa ("usei 1kg de arroz", '
        '"acabou o detergente"). Retorna a quantidade restante.',
    'parameters': {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'quantity': {
          'type': ['number', 'string'],
          'description': 'Quanto consumiu; omita para dar baixa total',
        },
      },
      'required': ['name'],
    },
  },
  {
    'name': 'add_shopping_items',
    'description': 'Adiciona itens à LISTA DE COMPRAS (o que falta comprar). '
        'NÃO use se o usuário só disse "adicionar X" sem deixar claro que é a '
        'lista — pergunte antes se é despensa ou lista de compras.',
    'parameters': {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'quantity': {'type': ['number', 'string']},
            },
            'required': ['name'],
          },
        },
      },
      'required': ['items'],
    },
  },
  {
    'name': 'get_shopping_list',
    'description': 'Itens pendentes da lista de compras.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'get_pantry_items',
    'description': 'Lista o que há na DESPENSA (estoque em casa): produto, '
        'quantidade e dias para vencer. Use para sugerir pratos/cardápio '
        'com o que a família tem.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'get_item_prices',
    'description': 'Estatísticas de preço de um produto nos mercados da '
        'região de Indaiatuba: menor/maior/médio, mercado mais barato, mais '
        'próximo, economia estimada e diferença %.',
    'parameters': {
      'type': 'object',
      'properties': {
        'item_name': {'type': 'string'},
      },
      'required': ['item_name'],
    },
  },
  {
    'name': 'get_market_recommendation',
    'description': 'Melhor estratégia para a lista de compras entre os '
        'mercados da região: um mercado só ou dividir, com custo de '
        'deslocamento.',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'remember_preference',
    'description': 'Salva uma preferência durável da família na memória '
        'permanente (ex.: mercado_favorito=GoodBom, marca_arroz=Camil).',
    'parameters': {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'snake_case curto'},
        'value': {'type': 'string'},
      },
      'required': ['key', 'value'],
    },
  },
  {
    'name': 'get_preferences',
    'description': 'Lê as preferências salvas da família (mercados, marcas, '
        'produtos favoritos, regras da casa).',
    'parameters': {'type': 'object', 'properties': {}, 'required': []},
  },
  {
    'name': 'render_chart',
    'description': 'Renderiza gráfico no chat. USE SOMENTE quando o usuário '
        'pedir gráfico explicitamente; depois comente em 1 frase.',
    'parameters': {
      'type': 'object',
      'properties': {
        'chart_type': {
          'type': 'string',
          'enum': ['pie', 'bar'],
        },
        'title': {'type': 'string'},
        'points': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'label': {'type': 'string'},
              'value': {'type': ['number', 'string']},
            },
            'required': ['label', 'value'],
          },
        },
      },
      'required': ['chart_type', 'points'],
    },
  },
];

// ==========================================================
// Executor das ferramentas
// ==========================================================
class AssistantToolExecutor {
  AssistantToolExecutor(this._ref);

  final Ref _ref;

  static const _priorityOrder = ['muito_alta', 'alta', 'media', 'baixa'];

  /// Coerção tolerante: modelos abertos (Llama/Groq) às vezes emitem números
  /// como texto ("45.80", "2,49"). Aceita num, String ou null.
  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static int? _int(dynamic v) => _num(v)?.round();

  Future<String> execute(String name, Map<String, dynamic> input) async {
    // Confirmação inteligente: gravações com inferência, ambiguidade ou risco
    // pedem o OK do usuário ANTES de tocar no banco. A gravação fica bloqueada
    // até a UI resolver a confirmação.
    final confirmation = confirmationFor(name, input);
    if (confirmation != null) {
      final result = await _ref
          .read(writeConfirmationControllerProvider.notifier)
          .request(confirmation);
      if (!result.confirmed) {
        return jsonEncode({
          'status': 'cancelado_pelo_usuario',
          'orientacao': 'O usuário NÃO confirmou. Não grave nada. Pergunte, com '
              'gentileza, o que ele quer ajustar.',
        });
      }
      // Valores (possivelmente) corrigidos pelo usuário no card sobrescrevem.
      input = {...input, ...result.values};
    }

    final result = await _dispatch(name, input);
    // Dados vivos: se a IA gravou, avisa as telas para atualizarem na hora.
    const writeTools = {
      'add_transaction', 'add_bill', 'add_debt', 'add_pantry_items',
      'add_shopping_items', 'consume_pantry_item', 'pay_bill',
      'remember_preference',
    };
    if (writeTools.contains(name)) {
      _ref.read(aiWriteTickProvider.notifier).state++;
    }
    return result;
  }

  Future<String> _dispatch(String name, Map<String, dynamic> input) async {
    switch (name) {
      case 'get_financial_overview':
        final kpis = await _ref.read(analyticsRepositoryProvider).kpis();
        return jsonEncode({
          'saldo_geral_contas': kpis.totalBalance,
          'patrimonio_liquido': kpis.netWorth,
          'receitas_mes': kpis.monthRevenue,
          'despesas_mes': kpis.monthExpenses,
          'contas_a_pagar_total': kpis.billsPending,
          'contas_atrasadas_total': kpis.billsOverdue,
        });

      case 'get_bills_status':
        return _billsStatus();

      case 'add_bill':
        return _addBill(input);

      case 'pay_bill':
        return _payBill(input['query'] as String? ?? '');

      case 'get_payment_plan':
        return _paymentPlan();

      case 'can_i_afford':
        return _canIAfford(input);

      case 'add_debt':
        return _addDebt(input);

      case 'get_debts':
        return _getDebts();

      case 'get_spending_by_category':
        final rows = await _ref
            .read(analyticsRepositoryProvider)
            .monthSpendByCategory();
        return jsonEncode({
          'mes_atual': [
            for (final r in rows) {'categoria': r.category, 'total': r.total},
          ],
        });

      case 'get_member_summary':
        return _memberSummary();

      case 'get_savings_analysis':
        return _savingsAnalysis();

      case 'add_transaction':
        return _addTransaction(input);

      case 'add_pantry_items':
        return _addPantryItems(input);

      case 'get_buy_opportunities':
        return _buyOpportunities();

      case 'search_market_offers':
        final result = await webSearchService.searchMarketOffers(
            query: input['query'] as String? ?? 'promoções de mercado');
        return jsonEncode({
          'fonte': 'busca web ao vivo (sites e Instagram dos mercados)',
          'resultado': result.answer,
          'links': result.sources,
        });

      case 'consume_pantry_item':
        return _consumePantryItem(input);

      case 'add_shopping_items':
        return _addShoppingItems(input);

      case 'get_shopping_list':
        final items = await _ref.read(shoppingRepositoryProvider).all();
        return jsonEncode({
          'pendentes': [
            for (final i in items.where((i) => !i.isBought))
              {'item': i.itemName, 'quantidade': i.quantity},
          ],
        });

      case 'get_pantry_items':
        final pantry = await _ref.read(inventoryRepositoryProvider).all();
        return jsonEncode({
          'despensa': [
            for (final i in pantry.where((i) => i.quantity > 0))
              {
                'produto': i.productName,
                'quantidade': i.quantity,
                'unidade': i.unit,
                'dias_para_vencer': i.daysToExpire,
                'perto_de_vencer':
                    i.daysToExpire != null && i.daysToExpire! <= 7,
              },
          ],
        });

      case 'get_item_prices':
        return _itemPriceStats(input['item_name'] as String? ?? '');

      case 'get_market_recommendation':
        final rec = await _ref.read(shoppingRecommenderProvider).run();
        if (rec == null) {
          return jsonEncode(
              {'info': 'Lista de compras vazia — nada a recomendar.'});
        }
        return jsonEncode({
          'regiao': 'Indaiatuba',
          'estrategia': rec.strategy,
          'resumo': rec.summary,
          'melhor_mercado_unico': rec.singleStoreName,
          'total_mercado_unico': rec.singleStoreTotal,
          'deslocamento_mercado_unico': rec.travelCostSingle,
          'total_dividindo': rec.splitTotal,
          'deslocamento_dividindo': rec.travelCostSplit,
          'divisao': {
            for (final e in rec.splitPlan.entries)
              e.key: e.value.map((q) => q.item).toList(),
          },
        });

      case 'remember_preference':
        return _rememberPreference(input);

      case 'get_preferences':
        return _getPreferences();

      default:
        throw Exception('Ferramenta desconhecida: $name');
    }
  }

  // ---------- contas ----------

  Future<String> _billsStatus() async {
    final bills = await _ref.read(billRepositoryProvider).all();
    final pending =
        bills.where((b) => b.status == BillStatus.pending).map((b) {
      final days = b.dueDate.difference(DateTime.now()).inDays;
      return {
        'descricao': b.description,
        'valor': b.amount,
        'vencimento': b.dueDate.toIso8601String().substring(0, 10),
        'dias_para_vencer': days,
        'alerta': days < 0
            ? 'critico'
            : days <= 3
                ? 'atencao'
                : 'ok',
        'prioridade': b.priority.wire,
        'categoria': b.category,
        'recorrente': b.recurrence.name,
      };
    }).toList();
    return jsonEncode({'contas_pendentes': pending});
  }

  Future<String> _addBill(Map<String, dynamic> input) async {
    final profile = _requireProfile();
    final due = flexibleDate(input['due_date']);
    if (due == null) {
      return jsonEncode({
        'nao_gravado': true,
        'orientacao': 'Não entendi a data de vencimento. Peça ao usuário a data '
            '(dia/mês/ano) e tente cadastrar de novo.',
      });
    }
    final bill = Bill(
      familyId: profile.familyId!,
      description: input['description'] as String,
      amount: _num(input['amount'])!,
      dueDate: due,
      recurrence: BillRecurrence.values.firstWhere(
          (r) => r.name == (input['recurrence'] ?? 'none'),
          orElse: () => BillRecurrence.none),
      priority: priorityFromWire(input['priority'] as String?),
      category: input['category'] as String?,
      paymentMethod: input['payment_method'] as String?,
      notes: input['notes'] as String?,
    );
    await _ref.read(billRepositoryProvider).insertRow(bill.toInsert());
    return jsonEncode({
      'status': 'salvo',
      'conta': bill.description,
      'valor': bill.amount,
      'vencimento': bill.dueDate.toIso8601String().substring(0, 10),
      'prioridade': bill.priority.wire,
      'categoria': bill.category,
    });
  }

  Future<String> _payBill(String query) async {
    final repo = _ref.read(billRepositoryProvider);
    final bills = await repo.all();
    final needle = query.toLowerCase();
    final matches = bills
        .where((b) =>
            b.status == BillStatus.pending &&
            ('${b.description} ${b.category ?? ''}')
                .toLowerCase()
                .contains(needle))
        .toList();

    if (matches.isEmpty) {
      return jsonEncode({
        'info': 'Nenhuma conta pendente combina com "$query".',
        'pendentes': [
          for (final b in bills.where((b) => b.status == BillStatus.pending))
            b.description,
        ],
      });
    }
    if (matches.length > 1) {
      return jsonEncode({
        'info': 'Mais de uma conta combina — pergunte ao usuário qual delas.',
        'opcoes': [
          for (final b in matches)
            {'descricao': b.description, 'valor': b.amount},
        ],
      });
    }
    await repo.markPaid(matches.first);
    return jsonEncode({
      'status': 'paga',
      'conta': matches.first.description,
      'valor': matches.first.amount,
      'recorrente': matches.first.recurrence.name,
      'obs': matches.first.recurrence != BillRecurrence.none
          ? 'Próxima cobrança agendada automaticamente.'
          : null,
    });
  }

  Future<String> _paymentPlan() async {
    final accounts = await _ref.read(accountRepositoryProvider).all();
    final available = accounts
        .where((a) => a.type != AccountType.creditCard)
        .fold<double>(0, (s, a) => s + a.balance);

    final bills = (await _ref.read(billRepositoryProvider).all())
        .where((b) => b.status == BillStatus.pending)
        .toList()
      ..sort((a, b) {
        final p = _priorityOrder
            .indexOf(a.priority.wire)
            .compareTo(_priorityOrder.indexOf(b.priority.wire));
        return p != 0 ? p : a.dueDate.compareTo(b.dueDate);
      });

    var remaining = available;
    final payNow = <Map<String, dynamic>>[];
    final later = <Map<String, dynamic>>[];
    for (final b in bills) {
      final row = {
        'conta': b.description,
        'valor': b.amount,
        'prioridade': b.priority.wire,
        'vencimento': b.dueDate.toIso8601String().substring(0, 10),
      };
      if (b.amount <= remaining) {
        remaining -= b.amount;
        payNow.add(row);
      } else {
        later.add(row);
      }
    }
    final totalBills = bills.fold<double>(0, (s, b) => s + b.amount);
    return jsonEncode({
      'saldo_disponivel': available,
      'total_contas_pendentes': totalBills,
      'pagar_agora_por_prioridade': payNow,
      'ficam_para_depois': later,
      'sobra_apos_pagamentos': remaining,
      'falta_para_cobrir_tudo': math.max(0, totalBills - available),
    });
  }

  /// "Posso comprar isso?" — decide se um gasto cabe no orçamento, olhando
  /// saldo em conta, contas a vencer em 30 dias e uma reserva de segurança.
  Future<String> _canIAfford(Map<String, dynamic> input) async {
    final amount = _num(input['amount']);
    if (amount == null || amount <= 0) {
      return jsonEncode({
        'erro': 'Informe o valor da compra para eu avaliar.',
      });
    }
    final desc = (input['description'] as String?)?.trim();

    final accounts = await _ref.read(accountRepositoryProvider).all();
    final available = accounts
        .where((a) => a.type != AccountType.creditCard)
        .fold<double>(0, (s, a) => s + a.balance);

    final now = DateTime.now();
    final in30 = now.add(const Duration(days: 30));
    final bills = (await _ref.read(billRepositoryProvider).all())
        .where((b) => b.status == BillStatus.pending)
        .toList();
    // Compromissos que vencem nos próximos 30 dias (o que já está "reservado").
    final upcoming = bills.where((b) => b.dueDate.isBefore(in30)).toList();
    final committed = upcoming.fold<double>(0, (s, b) => s + b.amount);
    final overdue = bills
        .where((b) => b.dueDate.isBefore(now))
        .fold<double>(0, (s, b) => s + b.amount);

    // Reserva de segurança: 10% do saldo (mín. R$100), para não zerar a conta.
    final reserve = math.max(100.0, available * 0.10);
    final freeAfterBills = available - committed - reserve;
    final canAfford = amount <= freeAfterBills;

    String veredito;
    if (canAfford) {
      veredito = 'pode_comprar';
    } else if (amount <= available - committed) {
      veredito = 'cabe_mas_aperta_a_reserva';
    } else if (amount <= available) {
      veredito = 'compromete_contas_do_mes';
    } else {
      veredito = 'nao_ha_saldo';
    }

    return jsonEncode({
      'compra': desc,
      'valor_pretendido': amount,
      'saldo_em_conta': available,
      'contas_a_vencer_30_dias': committed,
      'contas_atrasadas': overdue,
      'reserva_de_seguranca': reserve,
      'livre_apos_contas_e_reserva': freeAfterBills,
      'pode_comprar': canAfford,
      'veredito': veredito,
      'sobra_depois_da_compra': available - committed - amount,
      'orientacao':
          'Explique o veredito de forma simples e humana; se apertar, sugira '
              'esperar, parcelar ou pagar as contas prioritárias primeiro.',
    });
  }

  // ---------- dívidas ----------

  Future<String> _addDebt(Map<String, dynamic> input) async {
    final profile = _requireProfile();
    final original = _num(input['original_amount'])!;
    final debt = Debt(
      familyId: profile.familyId!,
      creditor: input['creditor'] as String,
      description: input['description'] as String?,
      originalAmount: original,
      remainingAmount:
          _num(input['remaining_amount']) ?? original,
      installments: _int(input['installments']),
      interestRate: _num(input['interest_rate']),
      priority: priorityFromWire(input['priority'] as String?),
    );
    await _ref.read(debtRepositoryProvider).insertRow(debt.toInsert());
    return jsonEncode({
      'status': 'salva',
      'credor': debt.creditor,
      'valor_original': debt.originalAmount,
      'valor_restante': debt.remainingAmount,
      'juros_mes_pct': debt.interestRate,
      'prioridade': debt.priority.wire,
    });
  }

  Future<String> _getDebts() async {
    final debts = await _ref.read(debtRepositoryProvider).all();
    if (debts.isEmpty) {
      return jsonEncode({'info': 'Nenhuma dívida registrada.'});
    }
    final sorted = debts.sortedBy<num>((d) => -(d.interestRate ?? 0));
    return jsonEncode({
      'total_original': debts.fold<double>(0, (s, d) => s + d.originalAmount),
      'total_restante': debts.fold<double>(0, (s, d) => s + d.remainingAmount),
      'dividas_por_juros_desc': [
        for (final d in sorted)
          {
            'credor': d.creditor,
            'descricao': d.description,
            'restante': d.remainingAmount,
            'parcelas': d.installments,
            'juros_mes_pct': d.interestRate,
            'prioridade': d.priority.wire,
          },
      ],
      'dica_estrategia': 'Sem restrição do usuário, quitar primeiro a de '
          'maior juros minimiza o custo total (método avalanche).',
    });
  }

  // ---------- análises ----------

  Future<String> _memberSummary() async {
    final client = _ref.read(supabaseProvider);
    final since = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .substring(0, 10);
    final rows = await client
        .from('transactions')
        .select('user_id, type, amount, users(name)')
        .gte('date', since);

    final byMember = groupBy(
      rows,
      (row) => (row['users'] as Map?)?['name'] ?? 'Desconhecido',
    );
    final summary = byMember.entries.map((e) {
      double revenue = 0, expense = 0;
      for (final r in e.value) {
        final amount = (r['amount'] as num).toDouble();
        if (r['type'] == 'revenue') {
          revenue += amount;
        } else {
          expense += amount;
        }
      }
      return {
        'membro': e.key,
        'receitas_90d': revenue,
        'gastos_90d': expense,
        'saldo_liquido': revenue - expense,
      };
    }).toList()
      ..sort((a, b) => (b['saldo_liquido'] as double)
          .compareTo(a['saldo_liquido'] as double));
    return jsonEncode({'membros': summary, 'periodo': 'ultimos 90 dias'});
  }

  Future<String> _savingsAnalysis() async {
    final analytics = _ref.read(analyticsRepositoryProvider);
    final month = await analytics.monthSpendByCategory();
    final usage = await analytics.budgetUsage();
    final history = await _ref
        .read(transactionRepositoryProvider)
        .recentExpenses(days: 90);

    final avg90 = groupBy(history, (Transaction t) => t.category).map(
      (cat, txs) =>
          MapEntry(cat, txs.fold<double>(0, (s, t) => s + t.amount) / 3),
    );

    return jsonEncode({
      'gasto_mes_atual_por_categoria': [
        for (final r in month) {'categoria': r.category, 'total': r.total},
      ],
      'media_mensal_90d_por_categoria': [
        for (final e in avg90.entries)
          {'categoria': e.key, 'media_mensal': e.value},
      ],
      'orcamentos_definidos': [
        for (final u in usage)
          {
            'categoria': u.category,
            'limite': u.limitAmount,
            'gasto_no_mes': u.spent,
          },
      ],
    });
  }

  Future<String> _addTransaction(Map<String, dynamic> input) async {
    final profile = _requireProfile();
    final type = TransactionType.values.byName(input['type'] as String);
    final rawCategory = (input['category'] as String?)?.trim();
    final rawDesc = (input['description'] as String?)?.trim();
    final tx = Transaction(
      familyId: profile.familyId!,
      userId: profile.id,
      type: type,
      amount: _num(input['amount'])!,
      // Categoria vazia vira "Outros" (bucket explícito de não-categorizado),
      // nunca um palpite inventado.
      category: (rawCategory == null || rawCategory.isEmpty) ? 'Outros' : rawCategory,
      description: (rawDesc == null || rawDesc.isEmpty) ? null : rawDesc,
      date: flexibleDate(input['date']) ?? DateTime.now(),
      tags: const ['via-ia'],
    );
    await _ref.read(transactionRepositoryProvider).insert(tx);
    return jsonEncode({
      'status': 'salvo',
      'tipo': type.name,
      'valor': tx.amount,
      'categoria': tx.category,
      'descricao': tx.description,
      'data': tx.date.toIso8601String().substring(0, 10),
      'registrado_por': profile.name,
    });
  }

  // ---------- despensa ----------

  Future<String> _addPantryItems(Map<String, dynamic> input) async {
    final profile = _requireProfile();
    final repo = _ref.read(inventoryRepositoryProvider);
    final inventory = await repo.all();
    final items = (input['items'] as List).cast<Map<String, dynamic>>();
    final saved = <Map<String, dynamic>>[];

    for (final item in items) {
      final name = item['name'] as String;
      // Quantidade NUNCA inferida (mesma política do preço): null = não
      // informada — não assume 1.
      final qty = _num(item['quantity']);
      final qtyProvided = qty != null;
      final price = _num(item['price']);
      final market = item['market'] as String?;
      final expiration = flexibleDate(item['expiration_date']);

      final existing = inventory.firstWhereOrNull(
          (i) => i.productName.toLowerCase() == name.toLowerCase());
      // Guarda anti-invenção: só registra preço quando há mercado real. Preço
      // sem mercado é provavelmente inferido pelo modelo — não vira histórico.
      final pricePoint = (price != null && realMarket(market))
          ? PricePoint(price: price, market: market!.trim(), date: DateTime.now())
          : null;

      if (existing != null) {
        await repo.updateRow(existing.id!, {
          // Sem quantidade informada, não faz +1 fantasma — só registra presença.
          if (qtyProvided) 'quantity': existing.quantity + qty,
          if (item['brand'] != null) 'brand': item['brand'],
          if (pricePoint != null)
            'price_history': [
              for (final p in existing.priceHistory) p.toJson(),
              pricePoint.toJson(),
            ],
          if (expiration != null)
            'expiration_date': expiration.toIso8601String().substring(0, 10),
        });
        saved.add({
          'produto': existing.productName,
          if (qtyProvided) 'quantidade_nova': existing.quantity + qty,
        });
      } else {
        final insert = <String, dynamic>{
          ...InventoryItem(
            familyId: profile.familyId!,
            productName: name,
            quantity: qty ?? 0, // placeholder; removido logo abaixo se não informado
            minQuantity: 1,
            expirationDate: expiration,
            priceHistory: [if (pricePoint != null) pricePoint],
          ).toInsert(),
          if (item['brand'] != null) 'brand': item['brand'],
        };
        // Sem quantidade informada: deixa o default do banco (não inventa número).
        if (!qtyProvided) insert.remove('quantity');
        await repo.insertRow(insert);
        saved.add({'produto': name, if (qtyProvided) 'quantidade': qty});
      }
    }
    return jsonEncode({'status': 'despensa_atualizada', 'itens': saved});
  }

  /// "Promoções": itens cujo preço mais recente está abaixo da média do
  /// próprio histórico (dados registrados pela família).
  Future<String> _buyOpportunities() async {
    final inventory = await _ref.read(inventoryRepositoryProvider).all();
    final opportunities = <Map<String, dynamic>>[];
    for (final item in inventory) {
      if (item.priceHistory.length < 2) continue;
      final prices = item.priceHistory.map((p) => p.price).toList();
      final avg = prices.average;
      final latest = item.priceHistory
          .sorted((a, b) => a.date.compareTo(b.date))
          .last;
      // Também considera o menor preço vigente entre os mercados.
      final latestByMarket = <String, PricePoint>{};
      for (final p in item.priceHistory) {
        final prev = latestByMarket[p.market];
        if (prev == null || p.date.isAfter(prev.date)) {
          latestByMarket[p.market] = p;
        }
      }
      final best = latestByMarket.values
          .sorted((a, b) => a.price.compareTo(b.price))
          .first;
      if (best.price < avg * 0.97) {
        opportunities.add({
          'produto': item.productName,
          'melhor_preco_atual': best.price,
          'mercado': best.market,
          'preco_medio_historico': avg,
          'desconto_vs_media_pct': (avg - best.price) / avg * 100,
          'ultimo_registro': latest.date.toIso8601String().substring(0, 10),
        });
      }
    }
    if (opportunities.isEmpty) {
      return jsonEncode({
        'info': 'Nenhuma oportunidade clara no histórico atual. Quanto mais '
            'preços a família registrar, melhores as detecções.',
      });
    }
    opportunities.sort((a, b) => (b['desconto_vs_media_pct'] as double)
        .compareTo(a['desconto_vs_media_pct'] as double));
    return jsonEncode({
      'fonte': 'historico de precos registrado pela familia',
      'oportunidades': opportunities,
    });
  }

  Future<String> _consumePantryItem(Map<String, dynamic> input) async {
    final repo = _ref.read(inventoryRepositoryProvider);
    final name = (input['name'] as String).toLowerCase();
    final item = (await repo.all())
        .firstWhereOrNull((i) => i.productName.toLowerCase().contains(name));
    if (item == null) {
      return jsonEncode(
          {'info': 'Produto "${input['name']}" não encontrado na despensa.'});
    }
    final qty = _num(input['quantity']) ?? item.quantity;
    final next = math.max(0.0, item.quantity - qty);
    await repo.updateRow(item.id!, {'quantity': next});
    return jsonEncode({
      'status': 'baixa_registrada',
      'produto': item.productName,
      'quantidade_restante': next,
      'zerou': next == 0,
      'obs': next == 0
          ? 'Estoque zerado — pergunte se deseja adicionar à lista de compras.'
          : null,
    });
  }

  Future<String> _addShoppingItems(Map<String, dynamic> input) async {
    final profile = _requireProfile();
    final repo = _ref.read(shoppingRepositoryProvider);
    final items = (input['items'] as List).cast<Map<String, dynamic>>();
    for (final item in items) {
      final qty = _num(item['quantity']); // não inventar quantidade
      final insert = ShoppingItem(
        familyId: profile.familyId!,
        itemName: item['name'] as String,
        quantity: qty ?? 1, // placeholder; removido se não informado
        executionData: const {'source': 'chat-ia'},
      ).toInsert();
      if (qty == null) insert.remove('quantity'); // default do banco
      await repo.insertRow(insert);
    }
    return jsonEncode({
      'status': 'adicionado_na_lista',
      'itens': [for (final i in items) i['name']],
    });
  }

  // ---------- preços ----------

  Future<String> _itemPriceStats(String itemName) async {
    final inventory = await _ref.read(inventoryRepositoryProvider).all();
    final needle = itemName.toLowerCase();
    final matches = inventory
        .where((i) => i.productName.toLowerCase().contains(needle))
        .toList();

    if (matches.isEmpty) {
      final withHistory = inventory
          .where((i) => i.priceHistory.isNotEmpty)
          .map((i) => i.productName)
          .toList();
      return jsonEncode({
        'info': 'Nenhum histórico de preço para "$itemName". Ofereça as '
            'alternativas com histórico se alguma for relacionada, e sugira '
            'registrar o preço deste item na próxima compra.',
        'produtos_com_historico_de_preco': withHistory,
      });
    }

    final markets = await _ref.read(marketRepositoryProvider).all();
    const userLat = -23.0904, userLng = -47.2181; // centro de Indaiatuba

    double distKm(Market m) {
      const r = 6371.0;
      final dLat = (m.lat - userLat) * math.pi / 180;
      final dLng = (m.lng - userLng) * math.pi / 180;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(userLat * math.pi / 180) *
              math.cos(m.lat * math.pi / 180) *
              math.sin(dLng / 2) *
              math.sin(dLng / 2);
      return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    }

    final result = matches.map((item) {
      final latestByMarket = <String, PricePoint>{};
      for (final p in item.priceHistory) {
        final prev = latestByMarket[p.market];
        if (prev == null || p.date.isAfter(prev.date)) {
          latestByMarket[p.market] = p;
        }
      }
      if (latestByMarket.isEmpty) {
        return {'produto': item.productName, 'info': 'sem histórico'};
      }
      final prices = latestByMarket.values.map((p) => p.price).toList();
      final minPrice = prices.reduce(math.min);
      final maxPrice = prices.reduce(math.max);
      final cheapest = latestByMarket.values
          .firstWhere((p) => p.price == minPrice);
      final nearest = latestByMarket.keys
          .map((name) => markets.firstWhereOrNull((m) => m.name == name))
          .whereType<Market>()
          .sorted((a, b) => distKm(a).compareTo(distKm(b)))
          .firstOrNull;

      return {
        'produto': item.productName,
        'menor_preco': minPrice,
        'maior_preco': maxPrice,
        'preco_medio': prices.average,
        'mercado_mais_barato': cheapest.market,
        'mercado_mais_proximo_com_preco': nearest?.name,
        'economia_estimada': maxPrice - minPrice,
        'diferenca_percentual':
            minPrice == 0 ? null : ((maxPrice - minPrice) / minPrice * 100),
        'precos_por_mercado': [
          for (final p in latestByMarket.values)
            {
              'mercado': p.market,
              'preco': p.price,
              'data': p.date.toIso8601String().substring(0, 10),
            },
        ],
      };
    }).toList();
    return jsonEncode({'regiao': 'Indaiatuba', 'itens': result});
  }

  // ---------- memória de preferências ----------

  Future<String> _rememberPreference(Map<String, dynamic> input) async {
    final profile = _requireProfile();
    final client = _ref.read(supabaseProvider);
    await client.from('ai_memory').upsert({
      'family_id': profile.familyId,
      'key': input['key'],
      'value': input['value'],
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'family_id,key');
    return jsonEncode(
        {'status': 'memorizado', 'chave': input['key'], 'valor': input['value']});
  }

  Future<String> _getPreferences() async {
    final client = _ref.read(supabaseProvider);
    final rows = await client.from('ai_memory').select('key, value');
    return jsonEncode({
      'preferencias': {for (final r in rows) r['key']: r['value']},
    });
  }

  // ---------- helpers ----------

  AppUser _requireProfile() {
    final profile = _ref.read(currentProfileProvider);
    if (profile?.familyId == null) {
      throw Exception('Usuário sem família configurada.');
    }
    return profile!;
  }
}

final assistantToolExecutorProvider =
    Provider((ref) => AssistantToolExecutor(ref));
