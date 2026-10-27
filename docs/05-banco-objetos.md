# Objetos do banco de dados (gerado)

Gerado a partir do catalogo do PostgreSQL, esquema `controle`. Fonte da verdade: `banco/schema.sql` e `banco/migracoes/`.
Para atualizar: `docker compose exec api node src/cli/docs-banco.js` (veja docs/08-operacao-backup.md).

## Resumo

| Tipo de objeto | Quantidade |
|---|---|
| Tabelas | 31 |
| Tipos enumerados | 19 |
| Funcoes | 14 |
| Gatilhos (triggers) | 28 |
| Politicas de seguranca por linha (RLS) | 50 |
| Views | 0 |

Extensoes instaladas: plpgsql 1.0.

## Tabelas

| Tabela | Colunas | RLS | Descricao |
|---|---|---|---|
| [`categoria`](#categoria) | 9 | sim |  |
| [`configuracao`](#configuracao) | 2 | sim |  |
| [`consulta`](#consulta) | 13 | sim |  |
| [`conta`](#conta) | 17 | sim |  |
| [`documento`](#documento) | 11 | sim |  |
| [`evento`](#evento) | 16 | sim |  |
| [`grupo`](#grupo) | 5 | sim |  |
| [`grupo_perfil`](#grupo_perfil) | 2 | sim |  |
| [`idioma`](#idioma) | 3 | sim |  |
| [`indicador`](#indicador) | 11 | sim |  |
| [`lancamento`](#lancamento) | 18 | sim |  |
| [`lembrete`](#lembrete) | 9 | sim |  |
| [`liberacao_modulo`](#liberacao_modulo) | 11 | sim |  |
| [`licenca`](#licenca) | 9 | sim |  |
| [`medicamento`](#medicamento) | 12 | sim |  |
| [`meta`](#meta) | 10 | sim |  |
| [`modulo`](#modulo) | 9 | sim |  |
| [`orcamento`](#orcamento) | 8 | sim |  |
| [`pagamento`](#pagamento) | 16 | sim |  |
| [`pais`](#pais) | 6 | sim |  |
| [`perfil`](#perfil) | 7 | sim |  |
| [`perfil_permissao`](#perfil_permissao) | 2 | sim |  |
| [`permissao`](#permissao) | 3 | sim |  |
| [`plano`](#plano) | 5 | sim |  |
| [`plano_preco`](#plano_preco) | 3 | sim |  |
| [`registro_tomada`](#registro_tomada) | 9 | sim |  |
| [`tarefa`](#tarefa) | 10 | sim |  |
| [`usuario`](#usuario) | 29 | sim |  |
| [`usuario_grupo`](#usuario_grupo) | 2 | sim |  |
| [`usuario_perfil`](#usuario_perfil) | 2 | sim |  |
| [`usuario_permissao`](#usuario_permissao) | 3 | sim |  |

### categoria

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `nome` | text | sim |  |  |
| `tipo` | controle.tipo_categoria | sim |  |  |
| `cor` | character(7) | nao |  |  |
| `categoria_mae_id` | uuid | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Chave estrangeira** `categoria_categoria_mae_id_fkey`: `FOREIGN KEY (categoria_mae_id) REFERENCES controle.categoria(id)`
- **Chave estrangeira** `categoria_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `categoria_pkey`: `PRIMARY KEY (id)`

Indices:

- `categoria_pkey`: `CREATE UNIQUE INDEX categoria_pkey ON controle.categoria USING btree (id)`
- `ix_categoria_sync`: `CREATE INDEX ix_categoria_sync ON controle.categoria USING btree (usuario_id, atualizado_em)`

Gatilhos:

- `trg_categoria_atualizado`: `CREATE TRIGGER trg_categoria_atualizado BEFORE INSERT OR UPDATE ON controle.categoria FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_categoria_dono`: `CREATE TRIGGER trg_categoria_dono BEFORE INSERT OR UPDATE ON controle.categoria FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('categoria_mae_id', 'categoria')`

Seguranca por linha (RLS):

- `p_categoria_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### configuracao

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `chave` | text | sim |  |  |
| `valor` | text | sim |  |  |

Restricoes:

- **Chave primaria** `configuracao_pkey`: `PRIMARY KEY (chave)`

Indices:

- `configuracao_pkey`: `CREATE UNIQUE INDEX configuracao_pkey ON controle.configuracao USING btree (chave)`

Seguranca por linha (RLS):

- `p_configuracao_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_configuracao_leitura` (SELECT): USING `true`

### consulta

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `evento_id` | uuid | nao |  |  |
| `lancamento_id` | uuid | nao |  |  |
| `medico` | text | sim |  |  |
| `especialidade` | text | nao |  |  |
| `local` | text | nao |  |  |
| `data_hora` | timestamp with time zone | sim |  |  |
| `preparo` | text | nao |  |  |
| `resultado` | text | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Chave estrangeira** `consulta_evento_id_fkey`: `FOREIGN KEY (evento_id) REFERENCES controle.evento(id)`
- **Chave estrangeira** `consulta_lancamento_id_fkey`: `FOREIGN KEY (lancamento_id) REFERENCES controle.lancamento(id)`
- **Chave estrangeira** `consulta_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `consulta_pkey`: `PRIMARY KEY (id)`

Indices:

- `consulta_pkey`: `CREATE UNIQUE INDEX consulta_pkey ON controle.consulta USING btree (id)`
- `ix_consulta_data`: `CREATE INDEX ix_consulta_data ON controle.consulta USING btree (usuario_id, data_hora) WHERE (excluido_em IS NULL)`
- `ix_consulta_sync`: `CREATE INDEX ix_consulta_sync ON controle.consulta USING btree (usuario_id, atualizado_em)`

Gatilhos:

- `trg_consulta_atualizado`: `CREATE TRIGGER trg_consulta_atualizado BEFORE INSERT OR UPDATE ON controle.consulta FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_consulta_dono`: `CREATE TRIGGER trg_consulta_dono BEFORE INSERT OR UPDATE ON controle.consulta FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('evento_id', 'evento', 'lancamento_id', 'lancamento')`

Seguranca por linha (RLS):

- `p_consulta_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### conta

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `nome` | text | sim |  |  |
| `tipo` | controle.tipo_conta | sim |  |  |
| `saldo_inicial` | numeric(14,2) | sim | 0 |  |
| `dia_fechamento` | smallint | nao |  |  |
| `dia_vencimento` | smallint | nao |  |  |
| `titularidade` | text | sim | 'propria'::text |  |
| `banco` | text | nao |  |  |
| `agencia` | text | nao |  |  |
| `numero_conta` | text | nao |  |  |
| `documento` | text | nao |  |  |
| `chave_pix` | text | nao |  |  |
| `apelido` | text | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `ck_conta_documento`: `CHECK (((documento IS NULL) OR (documento ~ '^[0-9]{11}$\|^[0-9]{14}$'::text)))`
- **Regra (CHECK)** `ck_conta_titularidade`: `CHECK ((titularidade = ANY (ARRAY['propria'::text, 'externa'::text])))`
- **Regra (CHECK)** `conta_dia_fechamento_check`: `CHECK (((dia_fechamento >= 1) AND (dia_fechamento <= 31)))`
- **Regra (CHECK)** `conta_dia_vencimento_check`: `CHECK (((dia_vencimento >= 1) AND (dia_vencimento <= 31)))`
- **Chave estrangeira** `conta_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `conta_pkey`: `PRIMARY KEY (id)`

Indices:

- `conta_pkey`: `CREATE UNIQUE INDEX conta_pkey ON controle.conta USING btree (id)`
- `ix_conta_sync`: `CREATE INDEX ix_conta_sync ON controle.conta USING btree (usuario_id, atualizado_em)`

Gatilhos:

- `trg_conta_atualizado`: `CREATE TRIGGER trg_conta_atualizado BEFORE INSERT OR UPDATE ON controle.conta FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_conta_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### documento

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `consulta_id` | uuid | nao |  |  |
| `lancamento_id` | uuid | nao |  |  |
| `arquivo_url` | text | sim |  |  |
| `nome_arquivo` | text | sim |  |  |
| `tipo` | controle.tipo_documento | sim |  |  |
| `data` | date | sim | CURRENT_DATE |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Chave estrangeira** `documento_consulta_id_fkey`: `FOREIGN KEY (consulta_id) REFERENCES controle.consulta(id)`
- **Chave estrangeira** `documento_lancamento_id_fkey`: `FOREIGN KEY (lancamento_id) REFERENCES controle.lancamento(id)`
- **Chave estrangeira** `documento_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `documento_pkey`: `PRIMARY KEY (id)`

Indices:

- `documento_pkey`: `CREATE UNIQUE INDEX documento_pkey ON controle.documento USING btree (id)`
- `ix_documento_sync`: `CREATE INDEX ix_documento_sync ON controle.documento USING btree (usuario_id, atualizado_em)`

Gatilhos:

- `trg_documento_atualizado`: `CREATE TRIGGER trg_documento_atualizado BEFORE INSERT OR UPDATE ON controle.documento FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_documento_dono`: `CREATE TRIGGER trg_documento_dono BEFORE INSERT OR UPDATE ON controle.documento FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('consulta_id', 'consulta', 'lancamento_id', 'lancamento')`

Seguranca por linha (RLS):

- `p_documento_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### evento

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `titulo` | text | sim |  |  |
| `inicio` | timestamp with time zone | sim |  |  |
| `fim` | timestamp with time zone | nao |  |  |
| `dia_inteiro` | boolean | sim | false |  |
| `local` | text | nao |  |  |
| `tipo` | controle.tipo_evento | sim | 'pessoal'::controle.tipo_evento |  |
| `recorrencia` | text | nao |  |  |
| `link` | text | nao |  |  |
| `notas` | text | nao |  |  |
| `origem` | controle.origem_evento | sim | 'local'::controle.origem_evento |  |
| `id_externo` | text | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `evento_check`: `CHECK (((fim IS NULL) OR (fim >= inicio)))`
- **Chave estrangeira** `evento_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `evento_pkey`: `PRIMARY KEY (id)`

Indices:

- `evento_pkey`: `CREATE UNIQUE INDEX evento_pkey ON controle.evento USING btree (id)`
- `ix_evento_inicio`: `CREATE INDEX ix_evento_inicio ON controle.evento USING btree (usuario_id, inicio) WHERE (excluido_em IS NULL)`
- `ix_evento_sync`: `CREATE INDEX ix_evento_sync ON controle.evento USING btree (usuario_id, atualizado_em)`

Gatilhos:

- `trg_evento_atualizado`: `CREATE TRIGGER trg_evento_atualizado BEFORE INSERT OR UPDATE ON controle.evento FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_evento_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### grupo

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `nome` | text | sim |  |  |
| `descricao` | text | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |

Restricoes:

- **Chave primaria** `grupo_pkey`: `PRIMARY KEY (id)`
- **Unica** `grupo_nome_key`: `UNIQUE (nome)`

Indices:

- `grupo_nome_key`: `CREATE UNIQUE INDEX grupo_nome_key ON controle.grupo USING btree (nome)`
- `grupo_pkey`: `CREATE UNIQUE INDEX grupo_pkey ON controle.grupo USING btree (id)`

Gatilhos:

- `trg_grupo_atualizado`: `CREATE TRIGGER trg_grupo_atualizado BEFORE UPDATE ON controle.grupo FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_grupo_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_grupo_membro` (SELECT): USING `(id IN ( SELECT usuario_grupo.grupo_id    FROM controle.usuario_grupo   WHERE (usuario_grupo.usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)))`

### grupo_perfil

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `grupo_id` | uuid | sim |  |  |
| `perfil_id` | uuid | sim |  |  |

Restricoes:

- **Chave estrangeira** `grupo_perfil_grupo_id_fkey`: `FOREIGN KEY (grupo_id) REFERENCES controle.grupo(id) ON DELETE CASCADE`
- **Chave estrangeira** `grupo_perfil_perfil_id_fkey`: `FOREIGN KEY (perfil_id) REFERENCES controle.perfil(id) ON DELETE CASCADE`
- **Chave primaria** `grupo_perfil_pkey`: `PRIMARY KEY (grupo_id, perfil_id)`

Indices:

- `grupo_perfil_pkey`: `CREATE UNIQUE INDEX grupo_perfil_pkey ON controle.grupo_perfil USING btree (grupo_id, perfil_id)`

Seguranca por linha (RLS):

- `p_grupo_perfil_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_grupo_perfil_leitura` (SELECT): USING `true`

### idioma

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `codigo` | text | sim |  |  |
| `nome` | text | sim |  |  |
| `ativo` | boolean | sim | true |  |

Restricoes:

- **Chave primaria** `idioma_pkey`: `PRIMARY KEY (codigo)`

Indices:

- `idioma_pkey`: `CREATE UNIQUE INDEX idioma_pkey ON controle.idioma USING btree (codigo)`

Seguranca por linha (RLS):

- `p_idioma_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_idioma_leitura` (SELECT): USING `true`

### indicador

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `tipo` | controle.tipo_indicador | sim |  |  |
| `valor` | numeric(10,2) | sim |  |  |
| `valor_secundario` | numeric(10,2) | nao |  |  |
| `unidade` | text | sim |  |  |
| `data_hora` | timestamp with time zone | sim |  |  |
| `origem` | controle.origem_indicador | sim | 'manual'::controle.origem_indicador |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Chave estrangeira** `indicador_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `indicador_pkey`: `PRIMARY KEY (id)`

Indices:

- `indicador_pkey`: `CREATE UNIQUE INDEX indicador_pkey ON controle.indicador USING btree (id)`
- `ix_indicador_sync`: `CREATE INDEX ix_indicador_sync ON controle.indicador USING btree (usuario_id, atualizado_em)`
- `ix_indicador_tipo_data`: `CREATE INDEX ix_indicador_tipo_data ON controle.indicador USING btree (usuario_id, tipo, data_hora DESC) WHERE (excluido_em IS NULL)`

Gatilhos:

- `trg_indicador_atualizado`: `CREATE TRIGGER trg_indicador_atualizado BEFORE INSERT OR UPDATE ON controle.indicador FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_indicador_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### lancamento

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `conta_id` | uuid | sim |  |  |
| `categoria_id` | uuid | nao |  |  |
| `valor` | numeric(14,2) | sim |  |  |
| `data` | date | sim |  |  |
| `descricao` | text | sim |  |  |
| `tipo` | controle.tipo_lancamento | sim |  |  |
| `status` | controle.status_lancamento | sim | 'pendente'::controle.status_lancamento |  |
| `recorrencia` | text | nao |  |  |
| `parcela_numero` | smallint | nao |  |  |
| `parcela_total` | smallint | nao |  |  |
| `grupo_parcelas` | uuid | nao |  |  |
| `tags` | text[] | sim | '{}'::text[] |  |
| `observacao` | text | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `lancamento_check`: `CHECK (((parcela_numero IS NULL) OR (parcela_numero <= parcela_total)))`
- **Regra (CHECK)** `lancamento_valor_check`: `CHECK ((valor >= (0)::numeric))`
- **Chave estrangeira** `lancamento_categoria_id_fkey`: `FOREIGN KEY (categoria_id) REFERENCES controle.categoria(id)`
- **Chave estrangeira** `lancamento_conta_id_fkey`: `FOREIGN KEY (conta_id) REFERENCES controle.conta(id)`
- **Chave estrangeira** `lancamento_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `lancamento_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_lancamento_data`: `CREATE INDEX ix_lancamento_data ON controle.lancamento USING btree (usuario_id, data) WHERE (excluido_em IS NULL)`
- `ix_lancamento_pendente`: `CREATE INDEX ix_lancamento_pendente ON controle.lancamento USING btree (usuario_id, data) WHERE ((status = 'pendente'::controle.status_lancamento) AND (excluido_em IS NULL))`
- `ix_lancamento_sync`: `CREATE INDEX ix_lancamento_sync ON controle.lancamento USING btree (usuario_id, atualizado_em)`
- `lancamento_pkey`: `CREATE UNIQUE INDEX lancamento_pkey ON controle.lancamento USING btree (id)`

Gatilhos:

- `trg_lancamento_atualizado`: `CREATE TRIGGER trg_lancamento_atualizado BEFORE INSERT OR UPDATE ON controle.lancamento FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_lancamento_dono`: `CREATE TRIGGER trg_lancamento_dono BEFORE INSERT OR UPDATE ON controle.lancamento FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('conta_id', 'conta', 'categoria_id', 'categoria')`

Seguranca por linha (RLS):

- `p_lancamento_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### lembrete

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `alvo_tipo` | controle.alvo_lembrete | sim |  |  |
| `alvo_id` | uuid | sim |  |  |
| `antecedencia_min` | integer | sim | 0 |  |
| `canal` | controle.canal_lembrete | sim | 'local'::controle.canal_lembrete |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `lembrete_antecedencia_min_check`: `CHECK ((antecedencia_min >= 0))`
- **Chave estrangeira** `lembrete_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `lembrete_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_lembrete_alvo`: `CREATE INDEX ix_lembrete_alvo ON controle.lembrete USING btree (alvo_tipo, alvo_id)`
- `ix_lembrete_sync`: `CREATE INDEX ix_lembrete_sync ON controle.lembrete USING btree (usuario_id, atualizado_em)`
- `lembrete_pkey`: `CREATE UNIQUE INDEX lembrete_pkey ON controle.lembrete USING btree (id)`

Gatilhos:

- `trg_lembrete_alvo`: `CREATE TRIGGER trg_lembrete_alvo BEFORE INSERT OR UPDATE ON controle.lembrete FOR EACH ROW EXECUTE FUNCTION controle.verifica_alvo_lembrete()`
- `trg_lembrete_atualizado`: `CREATE TRIGGER trg_lembrete_atualizado BEFORE INSERT OR UPDATE ON controle.lembrete FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_lembrete_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### liberacao_modulo

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `modulo_codigo` | text | sim |  |  |
| `usuario_id` | uuid | nao |  |  |
| `grupo_id` | uuid | nao |  |  |
| `plano_codigo` | text | nao |  |  |
| `concedida` | boolean | sim | true |  |
| `ativa` | boolean | sim | true |  |
| `vitalicio` | boolean | sim | true |  |
| `inicio` | timestamp with time zone | nao |  |  |
| `fim` | timestamp with time zone | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |

Restricoes:

- **Regra (CHECK)** `ck_liberacao_alvo`: `CHECK ((num_nonnulls(usuario_id, grupo_id, plano_codigo) = 1))`
- **Regra (CHECK)** `ck_liberacao_validade`: `CHECK ((vitalicio OR ((inicio IS NOT NULL) AND (fim IS NOT NULL))))`
- **Regra (CHECK)** `ck_liberacao_vigencia`: `CHECK (((fim IS NULL) OR (inicio IS NULL) OR (fim > inicio)))`
- **Chave estrangeira** `liberacao_modulo_grupo_id_fkey`: `FOREIGN KEY (grupo_id) REFERENCES controle.grupo(id) ON DELETE CASCADE`
- **Chave estrangeira** `liberacao_modulo_modulo_codigo_fkey`: `FOREIGN KEY (modulo_codigo) REFERENCES controle.modulo(codigo) ON DELETE CASCADE`
- **Chave estrangeira** `liberacao_modulo_plano_codigo_fkey`: `FOREIGN KEY (plano_codigo) REFERENCES controle.plano(codigo) ON DELETE CASCADE`
- **Chave estrangeira** `liberacao_modulo_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id) ON DELETE CASCADE`
- **Chave primaria** `liberacao_modulo_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_liberacao_modulo`: `CREATE INDEX ix_liberacao_modulo ON controle.liberacao_modulo USING btree (modulo_codigo)`
- `liberacao_modulo_pkey`: `CREATE UNIQUE INDEX liberacao_modulo_pkey ON controle.liberacao_modulo USING btree (id)`
- `ux_liberacao_usuario`: `CREATE UNIQUE INDEX ux_liberacao_usuario ON controle.liberacao_modulo USING btree (modulo_codigo, usuario_id) WHERE (usuario_id IS NOT NULL)`

Seguranca por linha (RLS):

- `p_liberacao_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_liberacao_leitura` (SELECT): USING `((usuario_id IS NULL) OR (usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid))`

### licenca

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `plano_codigo` | text | sim |  |  |
| `status` | controle.status_licenca | sim | 'ativa'::controle.status_licenca |  |
| `origem` | controle.origem_licenca | sim |  |  |
| `inicio` | timestamp with time zone | sim | now() |  |
| `fim` | timestamp with time zone | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |

Restricoes:

- **Regra (CHECK)** `ck_licenca_fim`: `CHECK (((fim IS NULL) OR (fim > inicio)))`
- **Chave estrangeira** `licenca_plano_codigo_fkey`: `FOREIGN KEY (plano_codigo) REFERENCES controle.plano(codigo)`
- **Chave estrangeira** `licenca_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id) ON DELETE CASCADE`
- **Chave primaria** `licenca_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_licenca_usuario`: `CREATE INDEX ix_licenca_usuario ON controle.licenca USING btree (usuario_id, status)`
- `licenca_pkey`: `CREATE UNIQUE INDEX licenca_pkey ON controle.licenca USING btree (id)`

Gatilhos:

- `trg_licenca_atualizado`: `CREATE TRIGGER trg_licenca_atualizado BEFORE UPDATE ON controle.licenca FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_licenca_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_licenca_leitura` (SELECT): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### medicamento

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `nome` | text | sim |  |  |
| `dose` | text | sim |  |  |
| `horarios` | time without time zone[] | sim |  |  |
| `inicio` | date | sim |  |  |
| `fim` | date | nao |  |  |
| `estoque` | integer | nao |  |  |
| `estoque_minimo` | integer | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `medicamento_check`: `CHECK (((fim IS NULL) OR (fim >= inicio)))`
- **Regra (CHECK)** `medicamento_estoque_check`: `CHECK ((estoque >= 0))`
- **Chave estrangeira** `medicamento_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `medicamento_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_medicamento_sync`: `CREATE INDEX ix_medicamento_sync ON controle.medicamento USING btree (usuario_id, atualizado_em)`
- `medicamento_pkey`: `CREATE UNIQUE INDEX medicamento_pkey ON controle.medicamento USING btree (id)`

Gatilhos:

- `trg_medicamento_atualizado`: `CREATE TRIGGER trg_medicamento_atualizado BEFORE INSERT OR UPDATE ON controle.medicamento FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_medicamento_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### meta

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `conta_id` | uuid | nao |  |  |
| `nome` | text | sim |  |  |
| `valor_alvo` | numeric(14,2) | sim |  |  |
| `prazo` | date | nao |  |  |
| `valor_acumulado` | numeric(14,2) | sim | 0 |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `meta_valor_alvo_check`: `CHECK ((valor_alvo > (0)::numeric))`
- **Chave estrangeira** `meta_conta_id_fkey`: `FOREIGN KEY (conta_id) REFERENCES controle.conta(id)`
- **Chave estrangeira** `meta_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `meta_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_meta_sync`: `CREATE INDEX ix_meta_sync ON controle.meta USING btree (usuario_id, atualizado_em)`
- `meta_pkey`: `CREATE UNIQUE INDEX meta_pkey ON controle.meta USING btree (id)`

Gatilhos:

- `trg_meta_atualizado`: `CREATE TRIGGER trg_meta_atualizado BEFORE INSERT OR UPDATE ON controle.meta FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_meta_dono`: `CREATE TRIGGER trg_meta_dono BEFORE INSERT OR UPDATE ON controle.meta FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('conta_id', 'conta')`

Seguranca por linha (RLS):

- `p_meta_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### modulo

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `codigo` | text | sim |  |  |
| `nome` | text | sim |  |  |
| `descricao` | text | nao |  |  |
| `ordem` | integer | sim |  |  |
| `ativo` | boolean | sim | true |  |
| `liberado_para_todos` | boolean | sim | false |  |
| `icone` | text | sim | 'extension'::text |  |
| `exibir_no_menu` | boolean | sim | false |  |
| `no_pacote` | boolean | sim | false |  |

Restricoes:

- **Chave primaria** `modulo_pkey`: `PRIMARY KEY (codigo)`

Indices:

- `modulo_pkey`: `CREATE UNIQUE INDEX modulo_pkey ON controle.modulo USING btree (codigo)`

Seguranca por linha (RLS):

- `p_modulo_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_modulo_leitura` (SELECT): USING `true`

### orcamento

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `categoria_id` | uuid | sim |  |  |
| `mes` | date | sim |  |  |
| `valor_limite` | numeric(14,2) | sim |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Regra (CHECK)** `orcamento_mes_check`: `CHECK ((date_trunc('month'::text, (mes)::timestamp with time zone) = mes))`
- **Regra (CHECK)** `orcamento_valor_limite_check`: `CHECK ((valor_limite >= (0)::numeric))`
- **Chave estrangeira** `orcamento_categoria_id_fkey`: `FOREIGN KEY (categoria_id) REFERENCES controle.categoria(id)`
- **Chave estrangeira** `orcamento_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `orcamento_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_orcamento_sync`: `CREATE INDEX ix_orcamento_sync ON controle.orcamento USING btree (usuario_id, atualizado_em)`
- `orcamento_pkey`: `CREATE UNIQUE INDEX orcamento_pkey ON controle.orcamento USING btree (id)`
- `ux_orcamento_categoria_mes`: `CREATE UNIQUE INDEX ux_orcamento_categoria_mes ON controle.orcamento USING btree (usuario_id, categoria_id, mes) WHERE (excluido_em IS NULL)`

Gatilhos:

- `trg_orcamento_atualizado`: `CREATE TRIGGER trg_orcamento_atualizado BEFORE INSERT OR UPDATE ON controle.orcamento FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_orcamento_dono`: `CREATE TRIGGER trg_orcamento_dono BEFORE INSERT OR UPDATE ON controle.orcamento FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('categoria_id', 'categoria')`

Seguranca por linha (RLS):

- `p_orcamento_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### pagamento

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `licenca_id` | uuid | nao |  |  |
| `plano_codigo` | text | sim |  |  |
| `metodo` | controle.metodo_pagamento | sim |  |  |
| `status` | controle.status_pagamento | sim | 'pendente'::controle.status_pagamento |  |
| `valor_centavos` | integer | sim |  |  |
| `moeda` | character(3) | sim |  |  |
| `gateway` | text | nao |  |  |
| `id_externo` | text | nao |  |  |
| `pix_codigo` | text | nao |  |  |
| `pix_expira_em` | timestamp with time zone | nao |  |  |
| `cartao_final` | character(4) | nao |  |  |
| `cartao_bandeira` | text | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |

Restricoes:

- **Regra (CHECK)** `ck_pagamento_final`: `CHECK (((cartao_final IS NULL) OR (cartao_final ~ '^[0-9]{4}$'::text)))`
- **Regra (CHECK)** `pagamento_valor_centavos_check`: `CHECK ((valor_centavos > 0))`
- **Chave estrangeira** `pagamento_licenca_id_fkey`: `FOREIGN KEY (licenca_id) REFERENCES controle.licenca(id)`
- **Chave estrangeira** `pagamento_plano_codigo_fkey`: `FOREIGN KEY (plano_codigo) REFERENCES controle.plano(codigo)`
- **Chave estrangeira** `pagamento_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id) ON DELETE CASCADE`
- **Chave primaria** `pagamento_pkey`: `PRIMARY KEY (id)`
- **Unica** `pagamento_gateway_id_externo_key`: `UNIQUE (gateway, id_externo)`

Indices:

- `ix_pagamento_usuario`: `CREATE INDEX ix_pagamento_usuario ON controle.pagamento USING btree (usuario_id, criado_em DESC)`
- `pagamento_gateway_id_externo_key`: `CREATE UNIQUE INDEX pagamento_gateway_id_externo_key ON controle.pagamento USING btree (gateway, id_externo)`
- `pagamento_pkey`: `CREATE UNIQUE INDEX pagamento_pkey ON controle.pagamento USING btree (id)`

Gatilhos:

- `trg_pagamento_atualizado`: `CREATE TRIGGER trg_pagamento_atualizado BEFORE UPDATE ON controle.pagamento FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_pagamento_abrir` (INSERT): USING `` WITH CHECK `((usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid) AND (status = 'pendente'::controle.status_pagamento))`
- `p_pagamento_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_pagamento_leitura` (SELECT): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### pais

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `codigo` | character(2) | sim |  |  |
| `nome` | text | sim |  |  |
| `idioma_padrao` | text | sim |  |  |
| `moeda_padrao` | character(3) | sim |  |  |
| `fuso_padrao` | text | sim |  |  |
| `ativo` | boolean | sim | true |  |

Restricoes:

- **Chave estrangeira** `pais_idioma_padrao_fkey`: `FOREIGN KEY (idioma_padrao) REFERENCES controle.idioma(codigo)`
- **Chave primaria** `pais_pkey`: `PRIMARY KEY (codigo)`

Indices:

- `pais_pkey`: `CREATE UNIQUE INDEX pais_pkey ON controle.pais USING btree (codigo)`

Seguranca por linha (RLS):

- `p_pais_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_pais_leitura` (SELECT): USING `true`

### perfil

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `codigo` | text | sim |  |  |
| `nome` | text | sim |  |  |
| `descricao` | text | nao |  |  |
| `sistema` | boolean | sim | false |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |

Restricoes:

- **Chave primaria** `perfil_pkey`: `PRIMARY KEY (id)`
- **Unica** `perfil_codigo_key`: `UNIQUE (codigo)`

Indices:

- `perfil_codigo_key`: `CREATE UNIQUE INDEX perfil_codigo_key ON controle.perfil USING btree (codigo)`
- `perfil_pkey`: `CREATE UNIQUE INDEX perfil_pkey ON controle.perfil USING btree (id)`

Gatilhos:

- `trg_perfil_atualizado`: `CREATE TRIGGER trg_perfil_atualizado BEFORE UPDATE ON controle.perfil FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`

Seguranca por linha (RLS):

- `p_perfil_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_perfil_leitura` (SELECT): USING `true`

### perfil_permissao

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `perfil_id` | uuid | sim |  |  |
| `permissao_codigo` | text | sim |  |  |

Restricoes:

- **Chave estrangeira** `perfil_permissao_perfil_id_fkey`: `FOREIGN KEY (perfil_id) REFERENCES controle.perfil(id) ON DELETE CASCADE`
- **Chave estrangeira** `perfil_permissao_permissao_codigo_fkey`: `FOREIGN KEY (permissao_codigo) REFERENCES controle.permissao(codigo) ON DELETE CASCADE`
- **Chave primaria** `perfil_permissao_pkey`: `PRIMARY KEY (perfil_id, permissao_codigo)`

Indices:

- `perfil_permissao_pkey`: `CREATE UNIQUE INDEX perfil_permissao_pkey ON controle.perfil_permissao USING btree (perfil_id, permissao_codigo)`

Seguranca por linha (RLS):

- `p_perfil_permissao_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_perfil_permissao_leitura` (SELECT): USING `true`

### permissao

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `codigo` | text | sim |  |  |
| `modulo_codigo` | text | sim |  |  |
| `nome` | text | sim |  |  |

Restricoes:

- **Chave estrangeira** `permissao_modulo_codigo_fkey`: `FOREIGN KEY (modulo_codigo) REFERENCES controle.modulo(codigo)`
- **Chave primaria** `permissao_pkey`: `PRIMARY KEY (codigo)`

Indices:

- `permissao_pkey`: `CREATE UNIQUE INDEX permissao_pkey ON controle.permissao USING btree (codigo)`

Seguranca por linha (RLS):

- `p_permissao_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_permissao_leitura` (SELECT): USING `true`

### plano

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `codigo` | text | sim |  |  |
| `nome` | text | sim |  |  |
| `periodo` | controle.tipo_periodo | sim |  |  |
| `duracao_meses` | integer | nao |  |  |
| `ativo` | boolean | sim | true |  |

Restricoes:

- **Regra (CHECK)** `ck_plano_duracao`: `CHECK ((((periodo = ANY (ARRAY['gratuito'::controle.tipo_periodo, 'vitalicio'::controle.tipo_periodo])) AND (duracao_meses IS NULL)) OR ((periodo = ANY (ARRAY['mensal'::controle.tipo_periodo, 'anual'::controle.tipo_periodo])) AND COALESCE((duracao_meses > 0), false))))`
- **Chave primaria** `plano_pkey`: `PRIMARY KEY (codigo)`

Indices:

- `plano_pkey`: `CREATE UNIQUE INDEX plano_pkey ON controle.plano USING btree (codigo)`

Seguranca por linha (RLS):

- `p_plano_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_plano_leitura` (SELECT): USING `true`

### plano_preco

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `plano_codigo` | text | sim |  |  |
| `moeda` | character(3) | sim |  |  |
| `valor_centavos` | integer | sim |  |  |

Restricoes:

- **Regra (CHECK)** `plano_preco_valor_centavos_check`: `CHECK ((valor_centavos > 0))`
- **Chave estrangeira** `plano_preco_plano_codigo_fkey`: `FOREIGN KEY (plano_codigo) REFERENCES controle.plano(codigo) ON DELETE CASCADE`
- **Chave primaria** `plano_preco_pkey`: `PRIMARY KEY (plano_codigo, moeda)`

Indices:

- `plano_preco_pkey`: `CREATE UNIQUE INDEX plano_preco_pkey ON controle.plano_preco USING btree (plano_codigo, moeda)`

Seguranca por linha (RLS):

- `p_plano_preco_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_plano_preco_leitura` (SELECT): USING `true`

### registro_tomada

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `medicamento_id` | uuid | sim |  |  |
| `horario_previsto` | timestamp with time zone | sim |  |  |
| `status` | controle.status_tomada | sim | 'pendente'::controle.status_tomada |  |
| `horario_real` | timestamp with time zone | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Chave estrangeira** `registro_tomada_medicamento_id_fkey`: `FOREIGN KEY (medicamento_id) REFERENCES controle.medicamento(id)`
- **Chave estrangeira** `registro_tomada_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `registro_tomada_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_tomada_sync`: `CREATE INDEX ix_tomada_sync ON controle.registro_tomada USING btree (usuario_id, atualizado_em)`
- `registro_tomada_pkey`: `CREATE UNIQUE INDEX registro_tomada_pkey ON controle.registro_tomada USING btree (id)`
- `ux_tomada_medicamento_horario`: `CREATE UNIQUE INDEX ux_tomada_medicamento_horario ON controle.registro_tomada USING btree (medicamento_id, horario_previsto) WHERE (excluido_em IS NULL)`

Gatilhos:

- `trg_registro_tomada_atualizado`: `CREATE TRIGGER trg_registro_tomada_atualizado BEFORE INSERT OR UPDATE ON controle.registro_tomada FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_tomada_dono`: `CREATE TRIGGER trg_tomada_dono BEFORE INSERT OR UPDATE ON controle.registro_tomada FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('medicamento_id', 'medicamento')`

Seguranca por linha (RLS):

- `p_registro_tomada_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### tarefa

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `usuario_id` | uuid | sim |  |  |
| `evento_id` | uuid | nao |  |  |
| `titulo` | text | sim |  |  |
| `prazo` | timestamp with time zone | nao |  |  |
| `prioridade` | controle.prioridade_tarefa | sim | 'media'::controle.prioridade_tarefa |  |
| `status` | controle.status_tarefa | sim | 'aberta'::controle.status_tarefa |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |

Restricoes:

- **Chave estrangeira** `tarefa_evento_id_fkey`: `FOREIGN KEY (evento_id) REFERENCES controle.evento(id)`
- **Chave estrangeira** `tarefa_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id)`
- **Chave primaria** `tarefa_pkey`: `PRIMARY KEY (id)`

Indices:

- `ix_tarefa_sync`: `CREATE INDEX ix_tarefa_sync ON controle.tarefa USING btree (usuario_id, atualizado_em)`
- `tarefa_pkey`: `CREATE UNIQUE INDEX tarefa_pkey ON controle.tarefa USING btree (id)`

Gatilhos:

- `trg_tarefa_atualizado`: `CREATE TRIGGER trg_tarefa_atualizado BEFORE INSERT OR UPDATE ON controle.tarefa FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_tarefa_dono`: `CREATE TRIGGER trg_tarefa_dono BEFORE INSERT OR UPDATE ON controle.tarefa FOR EACH ROW EXECUTE FUNCTION controle.verifica_dono('evento_id', 'evento')`

Seguranca por linha (RLS):

- `p_tarefa_dono` (ALL): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### usuario

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `id` | uuid | sim | gen_random_uuid() |  |
| `nome` | text | sim |  |  |
| `email` | text | sim |  |  |
| `senha_hash` | text | nao |  |  |
| `pais` | character(2) | sim | 'BR'::bpchar |  |
| `idioma` | text | sim | 'pt-BR'::text |  |
| `fuso_horario` | text | sim | 'America/Sao_Paulo'::text |  |
| `moeda_padrao` | character(3) | sim | 'BRL'::bpchar |  |
| `preferencias` | jsonb | sim | '{}'::jsonb |  |
| `cpf` | text | nao |  |  |
| `telefone` | text | nao |  |  |
| `data_nascimento` | date | nao |  |  |
| `cep` | text | nao |  |  |
| `logradouro` | text | nao |  |  |
| `numero` | text | nao |  |  |
| `complemento` | text | nao |  |  |
| `bairro` | text | nao |  |  |
| `cidade` | text | nao |  |  |
| `uf` | character(2) | nao |  |  |
| `ativo` | boolean | sim | true |  |
| `email_verificado_em` | timestamp with time zone | nao |  |  |
| `tentativas_login` | integer | sim | 0 |  |
| `bloqueado_ate` | timestamp with time zone | nao |  |  |
| `ultimo_login_em` | timestamp with time zone | nao |  |  |
| `criado_em` | timestamp with time zone | sim | now() |  |
| `atualizado_em` | timestamp with time zone | sim | now() |  |
| `excluido_em` | timestamp with time zone | nao |  |  |
| `superusuario` | boolean | sim | false |  |
| `criado_por` | uuid | nao |  |  |

Restricoes:

- **Regra (CHECK)** `ck_usuario_cep`: `CHECK (((cep IS NULL) OR (cep ~ '^[0-9]{8}$'::text)))`
- **Regra (CHECK)** `ck_usuario_cpf`: `CHECK (((cpf IS NULL) OR controle.cpf_valido(cpf)))`
- **Regra (CHECK)** `ck_usuario_email`: `CHECK (((email = lower(email)) AND (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'::text)))`
- **Regra (CHECK)** `ck_usuario_nascimento`: `CHECK (((data_nascimento IS NULL) OR ((data_nascimento >= '1900-01-01'::date) AND (data_nascimento <= CURRENT_DATE))))`
- **Regra (CHECK)** `ck_usuario_telefone`: `CHECK (((telefone IS NULL) OR (telefone ~ '^[0-9]{10,13}$'::text)))`
- **Regra (CHECK)** `ck_usuario_uf`: `CHECK (((uf IS NULL) OR (uf ~ '^[A-Z]{2}$'::text)))`
- **Chave estrangeira** `usuario_criado_por_fkey`: `FOREIGN KEY (criado_por) REFERENCES controle.usuario(id) ON DELETE SET NULL`
- **Chave estrangeira** `usuario_idioma_fkey`: `FOREIGN KEY (idioma) REFERENCES controle.idioma(codigo)`
- **Chave estrangeira** `usuario_pais_fkey`: `FOREIGN KEY (pais) REFERENCES controle.pais(codigo)`
- **Chave primaria** `usuario_pkey`: `PRIMARY KEY (id)`

Indices:

- `usuario_pkey`: `CREATE UNIQUE INDEX usuario_pkey ON controle.usuario USING btree (id)`
- `ux_usuario_cpf`: `CREATE UNIQUE INDEX ux_usuario_cpf ON controle.usuario USING btree (cpf) WHERE ((cpf IS NOT NULL) AND (excluido_em IS NULL))`
- `ux_usuario_email`: `CREATE UNIQUE INDEX ux_usuario_email ON controle.usuario USING btree (email) WHERE (excluido_em IS NULL)`

Gatilhos:

- `trg_usuario_atualizado`: `CREATE TRIGGER trg_usuario_atualizado BEFORE INSERT OR UPDATE ON controle.usuario FOR EACH ROW EXECUTE FUNCTION controle.set_atualizado_em()`
- `trg_usuario_preferencias`: `CREATE TRIGGER trg_usuario_preferencias BEFORE INSERT OR UPDATE ON controle.usuario FOR EACH ROW EXECUTE FUNCTION controle.verifica_preferencias_usuario()`

Seguranca por linha (RLS):

- `p_usuario_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_usuario_dono` (ALL): USING `(id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)` WITH CHECK `(id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### usuario_grupo

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `usuario_id` | uuid | sim |  |  |
| `grupo_id` | uuid | sim |  |  |

Restricoes:

- **Chave estrangeira** `usuario_grupo_grupo_id_fkey`: `FOREIGN KEY (grupo_id) REFERENCES controle.grupo(id) ON DELETE CASCADE`
- **Chave estrangeira** `usuario_grupo_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id) ON DELETE CASCADE`
- **Chave primaria** `usuario_grupo_pkey`: `PRIMARY KEY (usuario_id, grupo_id)`

Indices:

- `usuario_grupo_pkey`: `CREATE UNIQUE INDEX usuario_grupo_pkey ON controle.usuario_grupo USING btree (usuario_id, grupo_id)`

Seguranca por linha (RLS):

- `p_usuario_grupo_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_usuario_grupo_leitura` (SELECT): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### usuario_perfil

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `usuario_id` | uuid | sim |  |  |
| `perfil_id` | uuid | sim |  |  |

Restricoes:

- **Chave estrangeira** `usuario_perfil_perfil_id_fkey`: `FOREIGN KEY (perfil_id) REFERENCES controle.perfil(id) ON DELETE CASCADE`
- **Chave estrangeira** `usuario_perfil_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id) ON DELETE CASCADE`
- **Chave primaria** `usuario_perfil_pkey`: `PRIMARY KEY (usuario_id, perfil_id)`

Indices:

- `usuario_perfil_pkey`: `CREATE UNIQUE INDEX usuario_perfil_pkey ON controle.usuario_perfil USING btree (usuario_id, perfil_id)`

Seguranca por linha (RLS):

- `p_usuario_perfil_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_usuario_perfil_leitura` (SELECT): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

### usuario_permissao

| Coluna | Tipo | Obrigatoria | Padrao | Descricao |
|---|---|---|---|---|
| `usuario_id` | uuid | sim |  |  |
| `permissao_codigo` | text | sim |  |  |
| `concedida` | boolean | sim |  |  |

Restricoes:

- **Chave estrangeira** `usuario_permissao_permissao_codigo_fkey`: `FOREIGN KEY (permissao_codigo) REFERENCES controle.permissao(codigo) ON DELETE CASCADE`
- **Chave estrangeira** `usuario_permissao_usuario_id_fkey`: `FOREIGN KEY (usuario_id) REFERENCES controle.usuario(id) ON DELETE CASCADE`
- **Chave primaria** `usuario_permissao_pkey`: `PRIMARY KEY (usuario_id, permissao_codigo)`

Indices:

- `usuario_permissao_pkey`: `CREATE UNIQUE INDEX usuario_permissao_pkey ON controle.usuario_permissao USING btree (usuario_id, permissao_codigo)`

Seguranca por linha (RLS):

- `p_usuario_permissao_admin` (ALL): USING `controle.e_admin()` WITH CHECK `controle.e_admin()`
- `p_usuario_permissao_leitura` (SELECT): USING `(usuario_id = (NULLIF(current_setting('app.usuario_id'::text, true), ''::text))::uuid)`

## Tipos enumerados

- `alvo_lembrete`: `evento`, `consulta`, `medicamento`, `lancamento`, `tarefa`
- `canal_lembrete`: `local`, `push`
- `metodo_pagamento`: `pix`, `cartao_credito`, `cartao_debito`
- `origem_evento`: `local`, `google`, `ios`, `outlook`
- `origem_indicador`: `manual`, `aparelho`
- `origem_licenca`: `gratuita`, `compra`, `cortesia`
- `prioridade_tarefa`: `baixa`, `media`, `alta`
- `status_lancamento`: `pendente`, `pago`
- `status_licenca`: `pendente`, `ativa`, `expirada`, `cancelada`
- `status_pagamento`: `pendente`, `aprovado`, `recusado`, `estornado`, `expirado`
- `status_tarefa`: `aberta`, `em_andamento`, `concluida`
- `status_tomada`: `tomou`, `pulou`, `atrasou`, `pendente`
- `tipo_categoria`: `receita`, `despesa`
- `tipo_conta`: `corrente`, `poupanca`, `dinheiro`, `cartao`
- `tipo_documento`: `exame`, `receita`, `laudo`, `nota`
- `tipo_evento`: `reuniao`, `pessoal`, `saude`, `financeiro`
- `tipo_indicador`: `peso`, `pressao`, `glicemia`, `sono`, `agua`, `passos`, `frequencia_cardiaca`
- `tipo_lancamento`: `receita`, `despesa`, `transferencia`
- `tipo_periodo`: `gratuito`, `mensal`, `anual`, `vitalicio`

## Funcoes

| Funcao | Argumentos | Retorno | Linguagem | Roda como dono (SECURITY DEFINER) | Descricao |
|---|---|---|---|---|---|
| `buscar_login` | p_email text | TABLE(id uuid, nome text, senha_hash text, ativo boolean, bloqueado_ate timestamp with time zone, tentativas_login integer, idioma text, pais character) | sql | sim |  |
| `cadastrar_usuario` | p_nome text, p_email text, p_senha_hash text, p_pais text, p_idioma text, p_cpf text, p_telefone text, p_nascimento date, p_endereco jsonb | uuid | plpgsql | sim |  |
| `cpf_valido` | c text | boolean | plpgsql | nao |  |
| `e_admin` |  | boolean | sql | nao |  |
| `e_superusuario` | u uuid | boolean | sql | sim |  |
| `modulo_liberado` | u uuid, m text | boolean | sql | sim |  |
| `modulos_do_usuario` | u uuid | SETOF text | sql | sim |  |
| `permissoes_do_usuario` | u uuid | SETOF text | sql | sim |  |
| `registrar_login` | p_id uuid, p_ok boolean | void | sql | sim |  |
| `set_atualizado_em` |  | trigger | plpgsql | nao |  |
| `tem_acesso` | u uuid | boolean | sql | sim |  |
| `verifica_alvo_lembrete` |  | trigger | plpgsql | sim |  |
| `verifica_dono` |  | trigger | plpgsql | sim |  |
| `verifica_preferencias_usuario` |  | trigger | plpgsql | sim |  |

