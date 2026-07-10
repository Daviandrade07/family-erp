# Família ERP — auditoria do código-fonte e alterações aplicadas

## Diagnóstico

O projeto é um Flutter multiplataforma com Riverpod, GoRouter, Supabase, RLS, modo simples, dashboard financeiro, metas, contas, despensa, compras, refeições, IA e biometria local. O `flutter analyze` concluiu sem erros fatais; havia 102 avisos informativos/depreciações.

## Alterações aplicadas nesta atualização

- A identidade visual deixou de usar o verde neon como cor primária. O azul-petróleo/índigo comunica confiança, o coral destaca ações humanas e o verde permanece disponível para semântica positiva/receitas.
- O login não força mais biometria automaticamente. Face ID/digital é opt-in pelo bloqueio do app; recusar a biometria não encerra a sessão nem impede o uso por senha.
- O bloqueio biométrico passou a respeitar o tema ativo e a opção só é habilitada quando o dispositivo informa suporte.
- O estado da preferência de segurança só muda depois que a persistência local confirma sucesso.
- O cadastro agora informa claramente que o e-mail pode precisar de confirmação, evitando que a pessoa interprete o retorno à tela de login como falha silenciosa.
- Em builds de produção, chaves de IA manuais não são carregadas nem persistidas no dispositivo. O assistente Claude exige a Edge Function autenticada.
- A Edge Function de IA agora aceita somente endpoints previstos, limita o corpo, aplica timeout, restringe origens configuráveis e não devolve exceções internas.
- A migration `0005_security_hardening.sql` restringe RPCs sensíveis a usuários autenticados, impede ingresso com papel `admin`, valida nome/família, adiciona `WITH CHECK` às políticas de atualização e limita consultas analíticas.

## Decisões de produto e segurança

Face ID/digital é uma camada local do sistema operacional; o app nunca recebe ou armazena a biometria. Em aparelhos antigos, a conta continua acessível por senha.

Open Finance ainda não é uma conexão real neste backup. O contrato existente deve ser ligado a um provedor regulado por OAuth/consentimento, com escopo somente leitura, tokens no backend, revogação e trilha LGPD. Não deve ser ativado usando credenciais no Flutter.

Promoções de mercado precisam de fonte verificável, data de coleta, cidade e indicação de confiança. O seed atual contém mercados de referência; ele não deve ser apresentado como promoção real sem integração de dados.

## Pendências para uma versão de produção

- Implementar convites familiares com token de uso único, expiração e revogação; o RPC atual ainda usa UUID da família como identificador de entrada.
- Adicionar centro de privacidade: consentimento versionado, exportação, exclusão e retenção de dados.
- Criar testes de RLS com duas famílias, testes de RPC/Edge Function, testes de biometria e widgets em modo simples, tema claro/escuro, texto ampliado e redução de movimento.
- Substituir chamadas depreciadas (`withOpacity`, `anonKey`, `dart:html`) em uma atualização de compatibilidade Flutter, sem misturar essa migração com mudanças de produto.
- Paginar listas e limitar consultas analíticas para famílias grandes.

## Verificação

Executado `flutter pub get` e `flutter analyze`: projeto compila sem erros; os avisos restantes são informativos/depreciações e estão listados acima.
