# Contrato de sincronização

Versão 1 · 26/10/2026 · Etapa 0 do cronograma. Vale para o app (Drift/SQLite) e para a API (Node.js + PostgreSQL).

**Decisão de arquitetura (26/10/2026):** API própria em Node.js, conectada ao PostgreSQL com o papel `app_api`. Login e cadastro usam as funções `buscar_login` e `cadastrar_usuario`; o hash da senha (argon2id) é feito na API. Não usamos Supabase.

Este contrato fixa o que fica igual nos dois lados. Quem implementar a fase 1 (API) e a fase 7 (sincronização) deve segui-lo, e qualquer mudança entra aqui primeiro.

## 1. Regras gerais

1. **Id:** UUID v4 gerado no aparelho, em texto minúsculo com hífens (36 caracteres). Nunca reaproveitar um id.
2. **Dono:** cada registro tem `usuario_id`. A API define `app.usuario_id` (e só ele) com `set_config('app.usuario_id', '<uuid>', true)` dentro de cada transação; a RLS faz o resto. O cliente não escolhe o dono: a API ignora o `usuario_id` enviado e usa o do login.
3. **Exclusão:** sempre lógica (`excluido_em`). Nada é apagado do servidor na versão 1. Um registro excluído não volta por sincronização; para desfazer, o usuário cria um novo.
4. **Horas:** o app envia e recebe datas e horas em ISO 8601 UTC (`2026-10-26T13:45:00Z`). O servidor usa `timestamptz`.
5. **Dinheiro:** inteiro em centavos no app e no JSON. A API converte para `numeric(14,2)` (`centavos / 100`) ao gravar e de volta ao ler.
6. **Idempotência:** reenviar o mesmo lote não duplica nada, porque a gravação é um upsert por `id`.

## 2. Ajustes necessários no app (antes da fase 7)

O esqueleto atual tem valores que o servidor recusaria. Vão para a migração do Drift (`schemaVersion` 2):

| Hoje | Problema | Correção |
|---|---|---|
| Conta inicial com id `conta-padrao` | Não é UUID; a coluna do servidor é `uuid` | Gerar um UUID v4 na primeira abertura e guardá-lo em preferências no lugar da constante `contaPadraoId` |
| `usuarioId` com valor `'local'` | Não é UUID | Enquanto não há login, usar `'local'` só no aparelho. Ao entrar pela primeira vez, trocar `'local'` pelo id do usuário em todas as tabelas, antes da primeira sincronização |
| Tabela local `usuarios` | O usuário pertence ao servidor | Não sincroniza. O app guarda só o que vem de `GET /me` |

## 3. Tabelas sincronizadas e ordem de envio

O lote é gravado em uma transação, nesta ordem, para respeitar as chaves estrangeiras e as verificações de dono:

| Ordem | Tabela | Depende de |
|---|---|---|
| 1 | `categoria` | ela mesma (`categoria_mae_id`): enviar a mãe antes da filha |
| 2 | `conta` | |
| 3 | `evento` | |
| 4 | `medicamento` | |
| 5 | `lancamento` | `conta`, `categoria` |
| 6 | `tarefa` | `evento` |
| 7 | `orcamento` | `categoria` |
| 8 | `meta` | `conta` |
| 9 | `consulta` | `evento`, `lancamento` |
| 10 | `registro_tomada` | `medicamento` |
| 11 | `indicador` | |
| 12 | `documento` | `consulta`, `lancamento` |
| 13 | `lembrete` | o alvo (evento, consulta, medicamento, lancamento ou tarefa) |

O banco recusa um lembrete cujo alvo não exista ou seja de outro usuário, e recusa referências a registros de outro usuário.

## 4. Mapeamento de campos (app para servidor)

| Campo no app (Drift) | Campo no servidor | Conversão |
|---|---|---|
| `valorCentavos`, `saldoInicialCentavos`, `valorLimiteCentavos`, `valorAlvoCentavos`, `valorAcumuladoCentavos` | `valor`, `saldo_inicial`, `valor_limite`, `valor_alvo`, `valor_acumulado` | centavos para `numeric(14,2)` |
| `dia` (Lancamento, Documento) | `data` | data local `AAAA-MM-DD`, sem fuso |
| `mes` (Orcamento) | `mes` | `AAAA-MM-01` |
| `prazo` (Meta) | `prazo` (date) | `AAAA-MM-DD` |
| `prazo` (Tarefa) | `prazo` (timestamptz) | ISO 8601 UTC |
| `horarios` ("08:00,20:00") | `horarios` (`time[]`) | separar por vírgula; cada item `HH:MM` |
| `tags` ("a,b") | `tags` (`text[]`) | separar por vírgula; uma tag não pode conter vírgula |
| `inicio`, `fim` (Medicamento) | `inicio`, `fim` (date) | `AAAA-MM-DD` |
| `inicio`, `fim` (Evento), `dataHora`, `horarioPrevisto`, `horarioReal`, `criadoEm`, `atualizadoEm`, `excluidoEm` | timestamptz | ISO 8601 UTC |
| `valor`, `valorSecundario` (Indicador) | `valor`, `valor_secundario` (`numeric(10,2)`) | número com até 2 casas |
| `arquivoCaminho` (Documento) | `arquivo_url` | só envia o documento depois do arquivo subir para o armazenamento; antes disso o registro fica local |
| Enumerações (texto) | enumerações do PostgreSQL | mesmos valores do `schema.sql` |

Os nomes de campo no JSON usam o nome da coluna do servidor (`snake_case`).

## 5. Protocolo

Um único ponto de entrada, autenticado por token:

```
POST /sincronizar
{
  "cursor": "2026-10-26T13:45:00.123456Z" | null,
  "alteracoes": { "categoria": [ {registro}, ... ], "conta": [ ... ], ... }
}
```

Resposta:

```
{
  "cursor": "2026-10-26T13:50:02.654321Z",
  "alteracoes": { "categoria": [ ... ], ... },
  "conflitos":  [ { "tabela": "lancamento", "id": "...", "motivo": "servidor mais novo" } ]
}
```

- **Cursor:** é sempre um `atualizado_em` do servidor, nunca da hora do aparelho. O app guarda o cursor devolvido e o envia na próxima vez; `null` baixa tudo.
- **Margem:** o servidor devolve registros com `atualizado_em > cursor - 2 minutos`. O app descarta o que já tem igual (mesmo `id` e mesmo `atualizado_em`). Isso cobre transações que confirmam depois do cursor.
- **Tamanho:** no máximo 500 registros por tabela por chamada. Se houver mais, a resposta traz `"tem_mais": true` e o app repete a chamada.
- **Permissão:** a API exige a permissão `sincronizacao.sincronizar` e o módulo `sincronizacao` liberado para o usuário.
- **Erros:** o lote inteiro é gravado em uma transação. Se qualquer registro falhar, nada é gravado e a API responde com o erro e o `id` do registro. O app não avança o cursor.

## 6. Conflitos (regra da versão 1)

O banco guarda um único `atualizado_em` por registro, definido pelo servidor a cada gravação. Por isso a regra é **por registro**, não campo a campo:

1. Cada registro enviado traz `base_atualizado_em`: o `atualizado_em` do servidor que o aparelho tinha quando começou a editar (`null` para registro novo).
2. Se o `atualizado_em` atual no servidor for igual à base, a edição é aceita.
3. Se o servidor já tem uma versão mais nova, **a do servidor vence**. A API devolve essa versão em `alteracoes` e lista o registro em `conflitos`. O app aplica a versão do servidor e guarda a edição perdida num histórico local de conflitos, para o usuário ver.
4. **Exclusão vence edição:** se o registro está excluído no servidor, uma edição vinda do aparelho é descartada. Se foi excluído no aparelho e editado no servidor, a exclusão é aceita.

Campo a campo (a regra descrita no escopo original) exigiria uma data por campo e fica para uma versão futura, se o uso mostrar necessidade.

## 7. Decisões fora do contrato

- **Arquivos (documentos e fotos):** o armazenamento ainda não foi escolhido. Até lá, `documento` não sincroniza (seção 4).
- **Notificações push:** não fazem parte da versão 1; os lembretes são locais.
- **Perfis, grupos e liberações:** o app não os edita. Chegam por `GET /me` (módulos e permissões do usuário, via `modulos_do_usuario` e `permissoes_do_usuario`).

## 8. Quando mudar este contrato

Mudou um tipo, uma tabela ou a regra de conflito: atualize este arquivo, o `schema.sql`, as tabelas do Drift (com migração) e os testes, na mesma entrega.
