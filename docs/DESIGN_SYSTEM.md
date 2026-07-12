# Design System — Casa Viva

> Fonte de verdade da identidade visual do app. Reflete o **código real**
> (`lib/core/theme/app_theme.dart`). Se o código e este doc divergirem, um dos
> dois está errado — conserte.

## Princípio
Organização com **calma, não excesso**. Um foco por vez: a tela mostra o
**próximo passo** antes dos detalhes. Cor orienta, não enfeita. Sem pânico,
sem culpa.

## Fundo — Aurora
Base **ink** `#10131A` com dois brilhos radiais sutis (teal no topo-esquerda,
ameixa embaixo-direita), pintados por `AuroraBackground` atrás de TODAS as
telas (os `Scaffold` são transparentes). No tema claro, fundo calmo sólido
(`#F6F3EE`).

## Tokens semânticos de cor — UM papel por cor
Definidos em `AppColors`. Cada papel tem **uma** cor. Nomes legados são
apelidos documentados que apontam para o papel certo (evita renomear ~80 usos).

| Token | Cor | Papel | Apelidos legados |
|---|---|---|---|
| `mint` | `#5CC8B3` | **Ação + positivo** — CTA, progresso, receita, sucesso | `successSage`, `neonGreen` |
| `coral` | `#F19A78` | **Secundário** — FAB de apoio, acento secundário | `brandCoral` |
| `indigo` | `#8174E8` | **Sonho / metas** — estrela do sonho, acento de metas | `violet` |
| `amber` | `#E7B967` | **Alerta / atenção** — risco de orçamento, vencimento próximo | — |
| `lagoon` | `#46AFC3` | **Info / assistente** — bússola/assistente, ícones informativos | `techBlue`, `brandLagoon` |
| `red` | `#E8796F` | **Urgência / erro** — vencido, estouro, erro | — |
| `mintDeep` | `#3E9C88` | fim de gradiente de progresso | `successSageDark`, `neonGreenDark` |

**Regras:**
- `mint` é a cor primária do tema (`accent` default). Texto sobre o primário é
  calculado por contraste (escuro em acentos claros, branco em escuros).
- `indigo` é **exclusivo do sonho/metas**. `red` é **exclusivo de urgência/erro**
  — nenhum dos dois entra na paleta de categorias.
- `lagoon` (info/assistente) é distinto de `mint` (ação) de propósito: o
  assistente **não compete** com os CTAs.

## Superfícies (dark)
| Uso | Cor |
|---|---|
| Fundo/ink | `#10131A` |
| Nav e bottom sheets | `#171C25` |
| Cards | `#1A1F29` |
| Borda hairline | branco 9% (`0x17FFFFFF`) |
| Texto primário | `#F5F7FB` |
| Texto muted | `#AEB7C5` |

Cards: raio **18**, borda hairline, sem sombra dura. Botões: raio **16**,
altura 52. Campos: raio 18. Pílulas/chips: 999.

## Tipografia
**Inter** (uma família — sem serifada). Números **tabulares** em valores.
Títulos com **tracking apertado** (letter-spacing negativo) e peso 800 — a cara
contemporânea do protótipo. Corpo/rótulos em peso normal.

## Paleta de categorias
Cor fixa por categoria (`AppColors.catX`), reharmonizada para o dark+aurora
(mais clara e levemente saturada que a versão antiga). Índigo e vermelho ficam
fora (reservados a sonho e urgência).

## Personalização
Seletor de **cor de acento** em Perfil → Aparência (6 tons: Menta padrão,
Coral, Índigo, Âmbar, Lagoa, Rosa). Recolore só o elemento primário; superfícies
e legibilidade não mudam. **Modo privacidade** (olhinho) oculta valores em R$.

## Voz
Frases curtas, no presente, sem jargão. A IA **oferece e explica**, nunca impõe
(aceitar / editar / agora não). Metas oferecem **ritmos** (confortável, acelerar,
pausar) — nunca ranking familiar.
