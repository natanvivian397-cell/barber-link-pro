# Relatório de segurança — Barber Link Pro

**Data:** 29/10/2026  
**Escopo:** revisão estática de código e SQL no repositório. Isto não é um pentest nem confirma o estado do banco publicado.

## Achados prioritários

1. **Dados pessoais dos agendamentos:** a consulta de políticas registrada durante a revisão mostrou uma política SELECT pública para `bookings` com condição verdadeira e privilégios de leitura para `anon`. Isso pode expor nome, telefone e observações de clientes. A migração proposta remove a leitura pública da tabela e oferece uma view com apenas campos de disponibilidade.
2. **Painel administrativo:** a rota do painel e o formulário de login agora verificam uma lista explícita de duas contas e removem a criação pública de conta. A autorização também é aplicada por políticas RLS propostas no banco; a verificação no navegador, isoladamente, não é suficiente.
3. **Escrita em dados administrativos e fotos:** a proposta limita gravações em serviços, barbeiros, horários, bloqueios e fotos às contas permitidas. A migração também adiciona proteções restritivas ao bucket de fotos.
4. **Cabeçalhos e upload:** mudanças já versionadas adicionam cabeçalhos HTTP de segurança e validações básicas de imagem no cliente. Validação no cliente é defesa adicional, não substitui limites no Storage.

## Preservação do funcionamento

A migração foi ajustada para **não substituir a lógica existente de criação de agendamentos nem reescrever a função de clientes fixos**. A proposta mantém a página pública usando uma view de disponibilidade e um sinal de realtime sem dados pessoais. Ainda são necessários testes reais antes de ativar a mudança.

## Estado do trabalho

- As alterações estão na branch `security/database-rls-hardening`, na [PR #7](https://github.com/natanvivian397-cell/barber-link-pro/pull/7).
- A PR continua aberta; não foi mesclada.
- A migração SQL **não foi executada no banco publicado** por este ambiente.
- O build de produção e o CodeQL estão em execução para o commit mais recente; ainda não há resultados finais confirmados.
- O lint completo já apresentou centenas de problemas de formatação preexistentes; não foi aplicada formatação em massa.
- Não houve confirmação visual do deploy do Lovable nem teste de regressão no site publicado.

## Riscos e verificações pendentes

- Confirmar que a migração SQL corresponde às tabelas, colunas, funções e políticas reais do banco conectado.
- Aplicar primeiro em ambiente de teste e verificar: agendamento público, cancelamento, agenda do painel, mudança de status, bloqueios individuais, clientes fixos, fotos e atualização em tempo real.
- Testar as duas contas permitidas e uma conta autenticada comum; a conta comum não pode ver nem alterar dados administrativos.
- Verificar limites e tipos MIME no próprio Storage.
- Avaliar limitação de tentativas para as funções públicas de busca/cancelamento por nome e telefone.
- Confirmar os resultados finais de build e CodeQL.

## Conclusão

Há correções concretas preparadas no repositório, mas **não é correto declarar o site publicado protegido ainda**. A proteção dos dados de agendamento depende da revisão e execução da migração, seguida de testes de regressão. Não compartilhe senhas, tokens ou chaves privadas no repositório nem no relatório.
