# CLAUDE.md — KinFin

## Sobre o projeto
KinFin é um app de finanças familiares construído em Flutter, com backend em Supabase, voltado para famílias e usuários solo no Brasil. Identidade visual: dark-premium. Diferencial central: um "mordomo" de IA (via API da Groq) que ajuda o usuário a administrar as finanças.

## Estratégia de produto
- A v1 segue a estratégia "gestor first": o fluxo do perfil gestor da família é implementado e validado antes de expandir para os demais perfis.

## Metodologia de desenvolvimento
- Audit-first: antes de qualquer alteração, faça uma auditoria completa do aplicativo — código, fluxos de uso, autenticação, banco de dados, integrações, testes, acessibilidade e impacto nas famílias usuárias. Apresente os achados e o escopo da melhoria antes de editar. O objetivo é melhorar e refinar o produto existente, nunca refazê-lo sem necessidade. Preserve a arquitetura, os fluxos que já funcionam e o histórico do projeto. Não apague funcionalidades, arquivos, linhas de regra de negócio ou faça reescritas amplas sem autorização explícita do responsável pelo projeto. Prefira mudanças pequenas, aditivas e reversíveis. Para cada alteração, documente: problema observado, mudança proposta, arquivos afetados, riscos e como foi verificada.
- Ciclo de aprovação de mockup: toda tela nova precisa ser apresentada como rascunho/mockup e aprovada pelo responsável do projeto antes de virar implementação final em Flutter. Nenhuma tela nova é codificada em definitivo sem essa aprovação prévia.
- Quality gates: nenhuma tarefa é considerada concluída sem `flutter analyze` e `flutter test` passando sem erros.

## Agentes do projeto
Este projeto usa subagentes especializados, definidos em `.claude/agents/`:
- `kinfin-visionario`: visão de produto, pesquisa de mercado e validação de direção antes de qualquer trabalho técnico.
- `kinfin-planejador`: quebra features validadas em tarefas técnicas e define arquitetura.
- `kinfin-mockup`: converte imagens/prints de referência em HTML e CSS fiéis ao layout, sem lógica.
- `kinfin-frontend`: implementa as telas e widgets reais em Flutter.
- `kinfin-backend`: schema, RLS, autenticação e Edge Functions no Supabase.
- `kinfin-qa`: roda `flutter analyze` e `flutter test`, reporta e corrige problemas triviais.
- `kinfin-revisor`: revisão final somente leitura antes do merge.
