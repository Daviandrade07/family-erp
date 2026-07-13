# Resumo do mockup — telas do KinFin

## O que foi implementado
5 telas em HTML/CSS estático, fiéis ao layout da imagem enviada, cada uma em seu próprio arquivo:
- `inicio-solo.html` — Início, Modo Solo
- `inicio-compartilhado.html` — Início, Modo Compartilhado
- `financas.html` — tela Finanças
- `alocacao-despesa.html` — chat de alocação de despesa com o mordomo
- `perfil.html` — tela Perfil
- `preview-todas-as-telas.html` — as 5 lado a lado, só para visualização rápida

Nenhuma lógica, cálculo, estado ou chamada de API foi implementada — é só a camada visual, como definido no `kinfin-mockup`.

## O que foi estimado (não estava 100% determinável pela imagem)
- **Cores exatas em hexadecimal**: aproximei visualmente (roxo, verde, tons de fundo). Quando o `kinfin-frontend` for implementar em Flutter, vale confirmar os valores exatos com você antes de fixar no design system do app.
- **Fonte**: usei a fonte padrão do sistema (mesma família do iOS/Android), já que não dá pra confirmar com certeza a fonte exata só pela imagem.
- **Fotos de perfil**: substituí por círculos com a inicial do nome (Davi, Luiza, Lucas, Marcela), já que não tenho as fotos reais.
- **Estados não implementados**: hover, loading, erro e vazio não aparecem na imagem original, então não foram cobertos aqui.

## Um ponto pra você confirmar
Reparei numa possível inconsistência entre duas telas da própria imagem original — reproduzi exatamente como está, sem "corrigir" por conta própria:
- Na tela de Início (Modo Compartilhado), a distribuição das despesas mostra **Luiza 41%, Lucas 30%, Marcela 20%, Você 9%**.
- Na tela de Alocação da despesa, a sugestão de divisão mostra **Você (Davi) 41%, Luiza 30%, Lucas 20%, Marcela 9%**.

Os percentuais são os mesmos, mas atribuídos a pessoas diferentes nas duas telas. Pode ser intencional (contextos diferentes) ou uma inconsistência do mockup original — vale confirmar antes de implementar em Flutter.
