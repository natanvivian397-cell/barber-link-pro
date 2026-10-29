# Relatório de segurança — Barber Link Pro

**Data da revisão:** 29/10/2026  
**Escopo:** revisão estática do código e das migrações disponíveis no repositório. Não é um pentest e não equivale a uma auditoria do banco de produção.

## Resumo executivo

Foram incorporadas ao branch principal correções de defesa em profundidade para uploads de fotos e cabeçalhos HTTP, além de uma migração para limitar alterações em bloqueios de agenda e fotos do catálogo às duas contas administrativas indicadas pelo responsável.

**Status geral: parcialmente endurecido; segurança de produção ainda não confirmada.** A migração SQL foi publicada no GitHub, mas não foi possível confirmar sua execução no banco Supabase conectado. Também não foi possível consultar as políticas RLS ativas no banco de produção. Portanto, não é correto afirmar que todas as tabelas administrativas já estão protegidas.

## Alterações no repositório

1. **Uploads de fotos do catálogo** — o componente valida formatos de imagem permitidos, rejeita arquivos vazios ou maiores que 5 MB, deriva a extensão do MIME aprovado e não substitui arquivos existentes por upsert. Essas verificações no navegador são defesa adicional; não substituem limites e validações no servidor/Storage.
2. **Cabeçalhos HTTP** — o servidor adiciona X-Content-Type-Options: nosniff, Referrer-Policy: strict-origin-when-cross-origin e uma Permissions-Policy que desabilita câmera, microfone e geolocalização.
3. **Políticas de escrita de agenda e catálogo** — a nova migração supabase/migrations/20261029150000_admin_allowlist_hardening.sql troca a política ampla de escrita de schedule_blocks por uma lista de permissões para as duas contas autorizadas e restringe upload, substituição e exclusão de fotos do bucket catalog-photos. Mantém as leituras públicas que o site utiliza.
4. **Preservação de funcionalidades** — essas alterações não modificam a lógica de criação/cancelamento de agendamentos, preços, durações ou regras de conflito de horários.

## Pontos ainda pendentes / riscos residuais

- **Crítico para confirmar antes de declarar concluído:** executar a migração no Supabase conectado e testar com ambas as contas autorizadas e com uma conta comum. O merge no GitHub/Lovable não comprova, por si só, que a migração SQL foi aplicada ao banco.
- **RLS das demais tabelas administrativas:** o código do painel renderiza o painel após autenticação, sem verificar explicitamente um papel administrativo na interface. A proteção real precisa estar nas políticas do banco. As migrações versionadas encontradas não permitem confirmar as políticas de produção para bookings, services, barbers, configurações e demais tabelas. Não foram alteradas às cegas para evitar bloquear o painel ou os agendamentos.
- **Políticas duplicadas no banco:** políticas RLS permissivas do mesmo comando são combinadas por OR. Se existirem políticas de escrita adicionais no banco de produção, a nova política pode não ser suficiente até que as políticas efetivas sejam auditadas.
- **Cancelamento por nome e telefone:** as funções públicas find_my_bookings e cancel_my_booking usam nome e telefone como prova de correspondência. Não foi possível confirmar controles de taxa/anti-enumeração na produção. Esse fluxo foi preservado para não interromper o cancelamento de clientes; recomenda-se avaliar limitação de tentativas e proteção contra abuso.
- **Bucket de fotos:** a migração limita quem pode escrever, mas a configuração efetiva do bucket (privado/público, limite de tamanho e tipos MIME) não foi inspecionada no Supabase.
- **Testes automatizados:** não havia resultados de CI disponíveis para os commits de segurança revisados. A revisão estática não substitui testes de integração e verificação em produção.
- **Deploy Lovable:** o repositório indica que commits na branch conectada sincronizam com o Lovable, mas não foi possível verificar visualmente o deploy/preview nem confirmar a execução da migração no banco.

## Checklist recomendado para encerrar a auditoria

- [ ] Confirmar que a migração 20261029150000_admin_allowlist_hardening.sql foi aplicada no Supabase.
- [ ] Confirmar que as duas contas autorizadas conseguem administrar e que uma conta autenticada comum não consegue escrever em schedule_blocks nem alterar fotos.
- [ ] Inspecionar as políticas RLS efetivas de todas as tabelas usadas pelo painel e remover políticas amplas redundantes, sem alterar permissões públicas necessárias para criar e consultar agendamentos.
- [ ] Confirmar a configuração do bucket catalog-photos e impor limites de tamanho/MIME no próprio Storage.
- [ ] Testar agendamento, cancelamento, bloqueios por barbeiro, horários recorrentes e atualização em tempo real após aplicar as políticas.
- [ ] Confirmar o deploy do Lovable e executar testes de regressão.

## Conclusão

O código versionado recebeu melhorias concretas, mas **não deve ser classificado como totalmente seguro nem como auditado em produção** até que a migração seja aplicada e as políticas RLS e configurações reais do Supabase sejam verificadas. Nenhuma senha, chave privada ou chave de serviço deve ser incluída no repositório ou compartilhada no relatório.
