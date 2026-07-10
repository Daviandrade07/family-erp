import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_theme.dart';

/// Dica de economia doméstica exibida em pop-up a cada abertura do app.
/// O ciclo é embaralhado e persistido: nenhuma dica se repete até que todas
/// as 100 tenham sido exibidas.
class EconomyTips {
  static const tips = <String>[
    // Água
    'Banhos de até 5 minutos podem cortar 30% da conta de água.',
    'Conserte torneiras pingando: uma gota por segundo vira ~1.400 L/mês.',
    'Reaproveite a água da máquina de lavar para lavar o quintal.',
    'Feche a torneira ao escovar os dentes e ensaboar a louça.',
    'Use a máquina de lavar roupa sempre com carga cheia.',
    'Instale arejadores nas torneiras: reduzem o fluxo em até 50%.',
    'Regue plantas de manhã cedo ou à noite para evitar evaporação.',
    'Descarga com caixa acoplada de duplo acionamento economiza até 60%.',
    'Capte água da chuva em baldes para limpeza de áreas externas.',
    'Verifique vazamentos: feche tudo e veja se o hidrômetro continua girando.',
    // Energia
    'Troque lâmpadas por LED: até 85% menos consumo que incandescentes.',
    'Tire aparelhos da tomada: o modo standby pode ser 10% da conta de luz.',
    'Acumule roupas e passe tudo de uma vez — o ferro é um dos vilões.',
    'Limpe o filtro do ar-condicionado mensalmente: sujo, gasta até 25% mais.',
    'Ajuste o ar-condicionado para 23°C: cada grau a menos custa ~8% mais.',
    'Aproveite luz natural: abra cortinas antes de acender lâmpadas.',
    'Não guarde alimentos quentes na geladeira — force menos o motor.',
    'Verifique a borracha da geladeira: prenda uma folha; se soltar, troque.',
    'Chuveiro no modo "verão" gasta ~30% menos que no "inverno".',
    'Ventilador de teto no verão custa 90% menos que ar-condicionado.',
    // Mercado / compras
    'Nunca vá ao mercado com fome: aumenta compras por impulso em até 20%.',
    'Leve lista pronta e cumpra-a — o app monta a sua!',
    'Compare o preço por quilo/litro, não o preço da embalagem.',
    'Produtos na altura dos olhos são os mais caros: olhe prateleiras de baixo.',
    'Compre frutas e verduras da estação: chegam a custar metade do preço.',
    'Atacarejos compensam para itens não perecíveis em quantidade.',
    'Registre preços no app e compare mercados antes de sair de casa.',
    'Desconfie de "leve 3 pague 2" — faça a conta por unidade antes.',
    'Marcas próprias do mercado costumam ser 20-30% mais baratas.',
    'Feiras no fim do expediente têm descontos de até 50%.',
    // Gás
    'Panela de pressão reduz o tempo de cozimento e o gás em até 70%.',
    'Tampe as panelas: cozinha mais rápido e gasta menos gás.',
    'Desligue o forno alguns minutos antes: o calor residual termina o preparo.',
    'Chama azul e centralizada = queima eficiente; amarela desperdiça gás.',
    'Cozinhe porções grandes e congele: menos vezes acendendo o fogão.',
    'Use a panela do tamanho da boca do fogão para não perder calor.',
    'Descongele alimentos naturalmente antes de levar ao fogo.',
    'Aproveite o forno aceso para assar mais de um prato por vez.',
    'Água para café/chá: aqueça só o necessário, não a chaleira cheia.',
    'Revise a validade do regulador de gás: vazamentos custam caro e são perigosos.',
    // Alimentação
    'Planeje o cardápio da semana: reduz desperdício e delivery por impulso.',
    'Cozinhar em casa custa em média 3× menos que pedir delivery.',
    'Congele sobras em porções individuais para "marmitas de emergência".',
    'Talos e folhas viram refogados e caldos nutritivos: desperdício zero.',
    'Leve marmita para o trabalho: economia de centenas de reais por mês.',
    'Frutas muito maduras viram vitaminas, bolos e geleias.',
    'Prefira cortes de carne mais baratos em preparos de panela.',
    'Ovos são a proteína mais barata: inclua no cardápio semanal.',
    'Reduza o refrigerante: água com limão custa centavos.',
    'Café passado em casa custa até 10× menos que na padaria.',
    // Limpeza
    'Vinagre + bicarbonato substituem vários produtos caros de limpeza.',
    'Dilua o detergente conforme o rótulo: concentrado não limpa mais.',
    'Panos de microfibra reutilizáveis saem mais baratos que papel-toalha.',
    'Sabão em barra rende mais que líquido para a maioria das tarefas.',
    'Faça seu multiuso: água, álcool e algumas gotas de detergente.',
    'Doses corretas de sabão na máquina: excesso não lava melhor, só gasta.',
    'Amaciante caseiro: vinagre branco deixa roupas macias por centavos.',
    'Reaproveite escovas de dente velhas para limpar rejuntes e cantos.',
    'Limpe o filtro do aspirador: sujo, consome mais energia e quebra antes.',
    'Compre produtos de limpeza concentrados e dilua você mesmo.',
    // Organização financeira
    'Anote TODO gasto no app — o que não é medido não é controlado.',
    'Regra 50/30/20: 50% necessidades, 30% desejos, 20% poupança.',
    'Pague primeiro as dívidas de maior juros (método avalanche).',
    'Monte uma reserva de emergência de 3 a 6 meses de despesas.',
    'Revise assinaturas mensalmente: cancele o que não usou nos últimos 30 dias.',
    'Espere 24h antes de qualquer compra por impulso acima de R\$ 100.',
    'Negocie anuidade do cartão: muitas vezes basta ligar e pedir isenção.',
    'Defina orçamento por categoria no app e acompanhe os alertas da IA.',
    'Compras parceladas comprometem o orçamento futuro: some antes de assumir.',
    'Guarde qualquer dinheiro extra (13º, restituição) direto na reserva.',
    // Manutenção da casa
    'Manutenção preventiva é sempre mais barata que conserto de emergência.',
    'Limpe calhas antes da temporada de chuvas: evita infiltrações caras.',
    'Pinte e impermeabilize áreas externas a cada 3-5 anos.',
    'Aperte parafusos e dobradiças soltos antes que estraguem o móvel.',
    'Aprenda pequenos reparos no YouTube: mão de obra é 60% do custo.',
    'Vede frestas de portas e janelas: conforto térmico sem gastar energia.',
    'Revise a fiação antiga: além do risco, desperdiça energia.',
    'Lubrifique fechaduras e trilhos com grafite: duram muito mais.',
    'Troque o vedante da caixa de descarga ao primeiro sinal de vazamento.',
    'Cuide do jardim você mesmo: jardinagem básica é simples e terapêutica.',
    // Eletrodomésticos
    'Descongele o freezer: 5 mm de gelo aumentam o consumo em até 30%.',
    'Máquina de lavar no modo econômico/frio resolve para roupas do dia a dia.',
    'Deixe a geladeira longe do fogão e da parede: ventilação economiza energia.',
    'Micro-ondas gasta menos que o forno elétrico para porções pequenas.',
    'Selo Procel A no próximo eletrodoméstico: economia todos os meses.',
    'Não sobrecarregue tomadas com benjamins: risco e desperdício.',
    'Airfryer pequena gasta menos que forno grande para porções do dia a dia.',
    'Desligue a TV de verdade: horas de standby por dia somam no ano.',
    'Use o timer do ar-condicionado para desligar de madrugada.',
    'Cafeteira elétrica ligada mantendo café quente: prefira garrafa térmica.',
    // Extra: hábitos de consumo
    'Compare o custo por uso: um item durável barato por uso vence o descartável.',
    'Venda o que não usa há mais de um ano: desapego vira renda.',
    'Conserte roupas e sapatos antes de substituir: costureira custa pouco.',
    'Biblioteca e sebos: leitura quase de graça.',
    'Reuniões em casa custam uma fração de restaurantes e bares.',
    'Cupons e cashback: ative sempre, mas só para o que já ia comprar.',
    'Revise o plano de celular: a maioria paga por franquia que não usa.',
    'Ande ou pedale trajetos curtos: saúde e combustível no bolso.',
    'Carona solidária no trabalho divide o custo do combustível.',
    'Presentes feitos em casa (doces, fotos) marcam mais e custam menos.',
  ];

  static const _indexKey = 'economy_tip_index';
  static const _orderKey = 'economy_tip_order';

  /// Próxima dica do ciclo embaralhado persistente.
  static Future<String> next() async {
    final prefs = await SharedPreferences.getInstance();
    var order = prefs.getStringList(_orderKey);
    var index = prefs.getInt(_indexKey) ?? 0;

    if (order == null || order.length != tips.length || index >= tips.length) {
      final shuffled = List.generate(tips.length, (i) => i)..shuffle(Random());
      order = shuffled.map((i) => '$i').toList();
      index = 0;
      await prefs.setStringList(_orderKey, order);
    }

    final tip = tips[int.parse(order[index])];
    await prefs.setInt(_indexKey, index + 1);
    return tip;
  }
}

/// Exibe o pop-up de dica uma vez por sessão do app.
class EconomyTipPopup {
  static bool _shownThisSession = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (_shownThisSession) return;
    _shownThisSession = true;

    final tip = await EconomyTips.next();
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.lightbulb_rounded, color: AppColors.amber),
            SizedBox(width: 10),
            Text('Dica de economia'),
          ],
        ),
        content: Text(tip),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Boa! Vou aplicar'),
          ),
        ],
      ),
    );
  }
}
