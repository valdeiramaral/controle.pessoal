-- =====================================================================
-- App de controle pessoal - esquema PostgreSQL (servidor)
-- 14 entidades de dados do usuario (mais acesso, licencas e catalogos).
-- As 14 levam: id (UUID gerado no aparelho),
-- usuario_id, criado_em, atualizado_em, excluido_em (exclusao logica).
-- Requer PostgreSQL 13+ (gen_random_uuid nativo).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS controle;
SET search_path TO controle, public;

-- ---------- Tipos enumerados ----------
CREATE TYPE tipo_conta        AS ENUM ('corrente', 'poupanca', 'dinheiro', 'cartao');
CREATE TYPE tipo_categoria    AS ENUM ('receita', 'despesa');
CREATE TYPE tipo_lancamento   AS ENUM ('receita', 'despesa', 'transferencia');
CREATE TYPE status_lancamento AS ENUM ('pendente', 'pago');
CREATE TYPE tipo_evento       AS ENUM ('reuniao', 'pessoal', 'saude', 'financeiro');
CREATE TYPE origem_evento     AS ENUM ('local', 'google', 'ios', 'outlook');
CREATE TYPE prioridade_tarefa AS ENUM ('baixa', 'media', 'alta');
CREATE TYPE status_tarefa     AS ENUM ('aberta', 'em_andamento', 'concluida');
CREATE TYPE status_tomada     AS ENUM ('tomou', 'pulou', 'atrasou', 'pendente');
CREATE TYPE tipo_indicador    AS ENUM ('peso', 'pressao', 'glicemia', 'sono', 'agua', 'passos', 'frequencia_cardiaca');
CREATE TYPE origem_indicador  AS ENUM ('manual', 'aparelho');
CREATE TYPE tipo_documento    AS ENUM ('exame', 'receita', 'laudo', 'nota');
CREATE TYPE alvo_lembrete     AS ENUM ('evento', 'consulta', 'medicamento', 'lancamento', 'tarefa');
CREATE TYPE canal_lembrete    AS ENUM ('local', 'push');

-- Atualiza atualizado_em a cada INSERT/UPDATE (base da sincronizacao).
-- Usa clock_timestamp() (hora real da gravacao) e nao now() (hora de INICIO
-- da transacao): com now(), uma transacao longa gravaria uma hora antiga e o
-- aparelho, que ja avancou o cursor "atualizado_em > ultimoSync", nunca a veria.
-- A API ainda deve reler com uma pequena margem (ex.: 2 minutos) por seguranca.
CREATE OR REPLACE FUNCTION set_atualizado_em() RETURNS trigger AS $$
BEGIN
  NEW.atualizado_em := clock_timestamp();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------- 0. Catalogos de idioma e pais ----------
-- O usuario escolhe pais e idioma no cadastro. O pais traz os padroes de
-- idioma, moeda e fuso horario (o usuario pode trocar depois).
CREATE TABLE idioma (
  codigo  text PRIMARY KEY,                 -- BCP 47: pt-BR, en, es...
  nome    text NOT NULL,                    -- nome na propria lingua
  ativo   boolean NOT NULL DEFAULT true
);
INSERT INTO idioma (codigo, nome) VALUES
  ('pt-BR', 'Português (Brasil)'),
  ('pt-PT', 'Português (Portugal)'),
  ('en',    'English'),
  ('es',    'Español');

CREATE TABLE pais (
  codigo        char(2) PRIMARY KEY,        -- ISO 3166-1 alfa-2
  nome          text NOT NULL,
  idioma_padrao text NOT NULL REFERENCES idioma (codigo),
  moeda_padrao  char(3) NOT NULL,           -- ISO 4217
  fuso_padrao   text NOT NULL,
  ativo         boolean NOT NULL DEFAULT true
);
INSERT INTO pais (codigo, nome, idioma_padrao, moeda_padrao, fuso_padrao) VALUES
  ('BR', 'Brasil',         'pt-BR', 'BRL', 'America/Sao_Paulo'),
  ('PT', 'Portugal',       'pt-PT', 'EUR', 'Europe/Lisbon'),
  ('US', 'Estados Unidos', 'en',    'USD', 'America/New_York'),
  ('GB', 'Reino Unido',    'en',    'GBP', 'Europe/London'),
  ('ES', 'Espanha',        'es',    'EUR', 'Europe/Madrid'),
  ('MX', 'México',         'es',    'MXN', 'America/Mexico_City'),
  ('AR', 'Argentina',      'es',    'ARS', 'America/Argentina/Buenos_Aires');

-- ---------- 1. Usuario ----------
-- CPF valido? Recebe so os 11 digitos (a API tira pontos e traco antes).
-- Confere os dois digitos verificadores e recusa sequencias como 111.111.111-11.
CREATE FUNCTION cpf_valido(c text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE s int := 0; d1 int; d2 int; i int;
BEGIN
  IF c IS NULL OR c !~ '^[0-9]{11}$' OR c ~ '^(.)\1{10}$' THEN RETURN false; END IF;
  FOR i IN 1..9 LOOP s := s + substr(c, i, 1)::int * (11 - i); END LOOP;
  d1 := (s * 10) % 11; IF d1 = 10 THEN d1 := 0; END IF;
  s := 0;
  FOR i IN 1..10 LOOP s := s + substr(c, i, 1)::int * (12 - i); END LOOP;
  d2 := (s * 10) % 11; IF d2 = 10 THEN d2 := 0; END IF;
  RETURN d1 = substr(c, 10, 1)::int AND d2 = substr(c, 11, 1)::int;
END $$;

-- Login por e-mail e senha. A senha NUNCA fica aqui em texto: so o hash
-- (argon2id ou bcrypt, gerado pela API). O e-mail e gravado em minusculas.
CREATE TABLE usuario (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                text NOT NULL,
  email               text NOT NULL,
  senha_hash          text,
  pais                char(2) NOT NULL DEFAULT 'BR' REFERENCES pais (codigo),
  idioma              text NOT NULL DEFAULT 'pt-BR' REFERENCES idioma (codigo),
  fuso_horario        text NOT NULL DEFAULT 'America/Sao_Paulo',
  moeda_padrao        char(3) NOT NULL DEFAULT 'BRL',
  preferencias        jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Dados da pessoa (so digitos em cpf, telefone e cep; a API normaliza).
  cpf                 text,
  telefone            text,
  data_nascimento     date,
  cep                 text,
  logradouro          text,
  numero              text,
  complemento         text,
  bairro              text,
  cidade              text,
  uf                  char(2),
  ativo               boolean NOT NULL DEFAULT true,
  email_verificado_em timestamptz,
  tentativas_login    integer NOT NULL DEFAULT 0,
  bloqueado_ate       timestamptz,
  ultimo_login_em     timestamptz,
  criado_em           timestamptz NOT NULL DEFAULT now(),
  atualizado_em       timestamptz NOT NULL DEFAULT now(),
  excluido_em         timestamptz,
  superusuario        boolean NOT NULL DEFAULT false,  -- unico que enxerga os dados de todos
  criado_por          uuid REFERENCES usuario (id) ON DELETE SET NULL,  -- quem cadastrou (NULL = auto-cadastro)
  CONSTRAINT ck_usuario_email CHECK (email = lower(email) AND email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  CONSTRAINT ck_usuario_cpf CHECK (cpf IS NULL OR cpf_valido(cpf)),
  CONSTRAINT ck_usuario_telefone CHECK (telefone IS NULL OR telefone ~ '^[0-9]{10,13}$'),
  CONSTRAINT ck_usuario_nascimento CHECK (data_nascimento IS NULL
    OR (data_nascimento >= DATE '1900-01-01' AND data_nascimento <= current_date)),
  CONSTRAINT ck_usuario_cep CHECK (cep IS NULL OR cep ~ '^[0-9]{8}$'),
  CONSTRAINT ck_usuario_uf CHECK (uf IS NULL OR uf ~ '^[A-Z]{2}$')
);

-- E-mail unico apenas entre usuarios nao excluidos: quem apagou a conta pode
-- se cadastrar de novo com o mesmo e-mail.
CREATE UNIQUE INDEX ux_usuario_email ON usuario (email) WHERE excluido_em IS NULL;
-- CPF tambem unico entre os nao excluidos (uma conta por pessoa).
CREATE UNIQUE INDEX ux_usuario_cpf ON usuario (cpf) WHERE cpf IS NOT NULL AND excluido_em IS NULL;

-- ---------- 2. Conta ----------
CREATE TABLE conta (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  nome            text NOT NULL,
  tipo            tipo_conta NOT NULL,
  saldo_inicial   numeric(14,2) NOT NULL DEFAULT 0,
  -- Campos do cartao de credito (fase 2)
  dia_fechamento  smallint CHECK (dia_fechamento BETWEEN 1 AND 31),
  dia_vencimento  smallint CHECK (dia_vencimento BETWEEN 1 AND 31),
  -- Dados bancarios: propria (do usuario) ou externa (de terceiros, so cadastro)
  titularidade    text NOT NULL DEFAULT 'propria' CONSTRAINT ck_conta_titularidade CHECK (titularidade IN ('propria', 'externa')),
  banco           text,   -- codigo COMPE (ex.: 341) ou 000 = outro banco
  agencia         text,
  numero_conta    text,
  documento       text CONSTRAINT ck_conta_documento CHECK (documento IS NULL OR documento ~ '^[0-9]{11}$|^[0-9]{14}$'), -- CPF/CNPJ so digitos
  chave_pix       text,
  apelido         text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- 3. Categoria ----------
CREATE TABLE categoria (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  nome            text NOT NULL,
  tipo            tipo_categoria NOT NULL,
  cor             char(7),
  categoria_mae_id uuid REFERENCES categoria(id),
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- 4. Evento (criado antes de Consulta, que o referencia) ----------
CREATE TABLE evento (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  titulo          text NOT NULL,
  inicio          timestamptz NOT NULL,
  fim             timestamptz,
  dia_inteiro     boolean NOT NULL DEFAULT false,
  local           text,
  tipo            tipo_evento NOT NULL DEFAULT 'pessoal',
  recorrencia     text,                       -- regra RRULE (RFC 5545)
  link            text,
  notas           text,
  origem          origem_evento NOT NULL DEFAULT 'local',
  id_externo      text,                       -- id no calendario externo
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz,
  CHECK (fim IS NULL OR fim >= inicio)
);

-- ---------- 5. Tarefa ----------
CREATE TABLE tarefa (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  evento_id       uuid REFERENCES evento(id),
  titulo          text NOT NULL,
  prazo           timestamptz,
  prioridade      prioridade_tarefa NOT NULL DEFAULT 'media',
  status          status_tarefa NOT NULL DEFAULT 'aberta',
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- 6. Lancamento ----------
CREATE TABLE lancamento (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  conta_id        uuid NOT NULL REFERENCES conta(id),
  categoria_id    uuid REFERENCES categoria(id),
  valor           numeric(14,2) NOT NULL CHECK (valor >= 0),
  data            date NOT NULL,
  descricao       text NOT NULL,
  tipo            tipo_lancamento NOT NULL,
  status          status_lancamento NOT NULL DEFAULT 'pendente',
  recorrencia     text,                       -- regra RRULE
  parcela_numero  smallint,
  parcela_total   smallint,
  grupo_parcelas  uuid,                       -- agrupa parcelas da mesma compra
  tags            text[] NOT NULL DEFAULT '{}',
  observacao      text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz,
  CHECK (parcela_numero IS NULL OR parcela_numero <= parcela_total)
);

-- ---------- 7. Orcamento ----------
CREATE TABLE orcamento (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  categoria_id    uuid NOT NULL REFERENCES categoria(id),
  mes             date NOT NULL,              -- sempre o dia 1 do mes
  valor_limite    numeric(14,2) NOT NULL CHECK (valor_limite >= 0),
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz,
  CHECK (date_trunc('month', mes) = mes)
);
CREATE UNIQUE INDEX ux_orcamento_categoria_mes
  ON orcamento (usuario_id, categoria_id, mes) WHERE excluido_em IS NULL;

-- ---------- 8. Meta ----------
CREATE TABLE meta (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id       uuid NOT NULL REFERENCES usuario(id),
  conta_id         uuid REFERENCES conta(id),
  nome             text NOT NULL,
  valor_alvo       numeric(14,2) NOT NULL CHECK (valor_alvo > 0),
  prazo            date,
  valor_acumulado  numeric(14,2) NOT NULL DEFAULT 0,
  criado_em        timestamptz NOT NULL DEFAULT now(),
  atualizado_em    timestamptz NOT NULL DEFAULT now(),
  excluido_em      timestamptz
);

-- ---------- 9. Consulta ----------
CREATE TABLE consulta (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  evento_id       uuid REFERENCES evento(id),       -- gera evento na agenda
  lancamento_id   uuid REFERENCES lancamento(id),   -- custo da consulta
  medico          text NOT NULL,
  especialidade   text,
  local           text,
  data_hora       timestamptz NOT NULL,
  preparo         text,                             -- jejum, documentos...
  resultado       text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- 10. Medicamento ----------
CREATE TABLE medicamento (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  nome            text NOT NULL,
  dose            text NOT NULL,
  horarios        time[] NOT NULL,                  -- horarios diarios
  inicio          date NOT NULL,
  fim             date,
  estoque         integer CHECK (estoque >= 0),
  estoque_minimo  integer,                          -- alerta de reposicao
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz,
  CHECK (fim IS NULL OR fim >= inicio)
);

-- ---------- 11. RegistroTomada ----------
CREATE TABLE registro_tomada (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id       uuid NOT NULL REFERENCES usuario(id),
  medicamento_id   uuid NOT NULL REFERENCES medicamento(id),
  horario_previsto timestamptz NOT NULL,
  status           status_tomada NOT NULL DEFAULT 'pendente',
  horario_real     timestamptz,
  criado_em        timestamptz NOT NULL DEFAULT now(),
  atualizado_em    timestamptz NOT NULL DEFAULT now(),
  excluido_em      timestamptz
);
CREATE UNIQUE INDEX ux_tomada_medicamento_horario
  ON registro_tomada (medicamento_id, horario_previsto) WHERE excluido_em IS NULL;

-- ---------- 12. Indicador ----------
CREATE TABLE indicador (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  tipo            tipo_indicador NOT NULL,
  valor           numeric(10,2) NOT NULL,
  valor_secundario numeric(10,2),                   -- ex.: pressao diastolica
  unidade         text NOT NULL,
  data_hora       timestamptz NOT NULL,
  origem          origem_indicador NOT NULL DEFAULT 'manual',
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- 13. Documento ----------
CREATE TABLE documento (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  consulta_id     uuid REFERENCES consulta(id),
  lancamento_id   uuid REFERENCES lancamento(id),
  arquivo_url     text NOT NULL,                    -- caminho no armazenamento
  nome_arquivo    text NOT NULL,
  tipo            tipo_documento NOT NULL,
  data            date NOT NULL DEFAULT current_date,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- 14. Lembrete ----------
-- O alvo e polimorfico: alvo_tipo + alvo_id (sem FK direta).
CREATE TABLE lembrete (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES usuario(id),
  alvo_tipo       alvo_lembrete NOT NULL,
  alvo_id         uuid NOT NULL,
  antecedencia_min integer NOT NULL DEFAULT 0 CHECK (antecedencia_min >= 0),
  canal           canal_lembrete NOT NULL DEFAULT 'local',
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now(),
  excluido_em     timestamptz
);

-- ---------- Indices para sincronizacao e consultas frequentes ----------
-- Sincronizacao: "o que mudou desde X" por usuario.
CREATE INDEX ix_conta_sync          ON conta          (usuario_id, atualizado_em);
CREATE INDEX ix_categoria_sync      ON categoria      (usuario_id, atualizado_em);
CREATE INDEX ix_lancamento_sync     ON lancamento     (usuario_id, atualizado_em);
CREATE INDEX ix_orcamento_sync      ON orcamento      (usuario_id, atualizado_em);
CREATE INDEX ix_meta_sync           ON meta           (usuario_id, atualizado_em);
CREATE INDEX ix_evento_sync         ON evento         (usuario_id, atualizado_em);
CREATE INDEX ix_tarefa_sync         ON tarefa         (usuario_id, atualizado_em);
CREATE INDEX ix_consulta_sync       ON consulta       (usuario_id, atualizado_em);
CREATE INDEX ix_medicamento_sync    ON medicamento    (usuario_id, atualizado_em);
CREATE INDEX ix_tomada_sync         ON registro_tomada(usuario_id, atualizado_em);
CREATE INDEX ix_indicador_sync      ON indicador      (usuario_id, atualizado_em);
CREATE INDEX ix_documento_sync      ON documento      (usuario_id, atualizado_em);
CREATE INDEX ix_lembrete_sync       ON lembrete       (usuario_id, atualizado_em);

-- Telas: tela Hoje, extrato, agenda.
CREATE INDEX ix_lancamento_data     ON lancamento (usuario_id, data) WHERE excluido_em IS NULL;
CREATE INDEX ix_lancamento_pendente ON lancamento (usuario_id, data) WHERE status = 'pendente' AND excluido_em IS NULL;
CREATE INDEX ix_evento_inicio       ON evento     (usuario_id, inicio) WHERE excluido_em IS NULL;
CREATE INDEX ix_consulta_data       ON consulta   (usuario_id, data_hora) WHERE excluido_em IS NULL;
CREATE INDEX ix_indicador_tipo_data ON indicador  (usuario_id, tipo, data_hora DESC) WHERE excluido_em IS NULL;
CREATE INDEX ix_lembrete_alvo       ON lembrete   (alvo_tipo, alvo_id);

-- =====================================================================
-- ACESSO: modulos, permissoes, perfis, grupos
-- Cada MODULO tem PROCESSOS; cada processo e uma PERMISSAO.
-- Um modulo so aparece para o usuario se estiver LIBERADO (ver
-- liberacao_modulo). Perfis agrupam permissoes. O usuario recebe perfis
-- de forma individual ou por GRUPO, e pode ter excecoes individuais
-- (usuario_permissao: concede ou nega uma permissao so para ele).
-- =====================================================================
CREATE TYPE tipo_periodo     AS ENUM ('gratuito', 'mensal', 'anual', 'vitalicio');
CREATE TYPE status_licenca   AS ENUM ('pendente', 'ativa', 'expirada', 'cancelada');
CREATE TYPE origem_licenca   AS ENUM ('gratuita', 'compra', 'cortesia');
CREATE TYPE metodo_pagamento AS ENUM ('pix', 'cartao_credito', 'cartao_debito');
CREATE TYPE status_pagamento AS ENUM ('pendente', 'aprovado', 'recusado', 'estornado', 'expirado');

CREATE TABLE modulo (
  codigo              text PRIMARY KEY,
  nome                text NOT NULL,
  descricao           text,
  ordem               integer NOT NULL,
  ativo               boolean NOT NULL DEFAULT true,
  liberado_para_todos boolean NOT NULL DEFAULT false,
  icone               text    NOT NULL DEFAULT 'extension',  -- nome do icone no app
  exibir_no_menu      boolean NOT NULL DEFAULT false,        -- true = modulo cadastrado pelo SuperUsuario
  no_pacote           boolean NOT NULL DEFAULT false         -- true = faz parte do pacote: vale para todos, sem liberacao
);

CREATE TABLE permissao (
  codigo        text PRIMARY KEY,           -- modulo.objeto.acao
  modulo_codigo text NOT NULL REFERENCES modulo (codigo),
  nome          text NOT NULL
);

INSERT INTO modulo (codigo, nome, descricao, ordem, liberado_para_todos) VALUES
  ('acesso',        'Acesso e usuários',        'Login, cadastro de usuários, perfis, grupos e permissões', 1, true),
  ('idiomas',       'Idiomas e países',         'Catálogo de países e idiomas do cadastro',                  2, true),
  ('licencas',      'Licenças e cobrança',      'Planos, licenças e pagamentos por Pix e cartão',            3, true),
  ('financas',      'Finanças',                 'Contas, lançamentos, orçamentos e metas',                   4, false),
  ('saude',         'Saúde',                    'Medicamentos, consultas, indicadores e documentos',         5, false),
  ('agenda',        'Agenda e compromissos',    'Eventos, tarefas e lembretes',                              6, false),
  ('painel',        'Painel Hoje e relatórios', 'Resumo do dia e relatórios',                                7, false),
  ('sincronizacao', 'Sincronização',            'Envio e recebimento de dados entre aparelho e servidor',    8, false),
  ('administracao', 'Administração',            'Cadastro de módulos e liberação para usuários',             9, true);

INSERT INTO permissao (codigo, modulo_codigo, nome) VALUES
  ('acesso.usuario.ver',            'acesso',        'Ver usuários'),
  ('acesso.usuario.cadastrar',      'acesso',        'Cadastrar usuários'),
  ('acesso.usuario.editar',         'acesso',        'Editar, desativar e excluir usuários'),
  ('acesso.perfil.gerenciar',       'acesso',        'Gerenciar perfis e permissões'),
  ('acesso.grupo.gerenciar',        'acesso',        'Gerenciar grupos'),
  ('idiomas.catalogo.gerenciar',    'idiomas',       'Gerenciar países e idiomas'),
  ('licencas.licenca.ver',          'licencas',      'Ver a própria licença'),
  ('licencas.licenca.conceder',     'licencas',      'Conceder licenças'),
  ('licencas.pagamento.ver',        'licencas',      'Ver pagamentos'),
  ('licencas.plano.gerenciar',      'licencas',      'Gerenciar planos e preços'),
  ('financas.conta.gerenciar',      'financas',      'Gerenciar contas'),
  ('financas.lancamento.ver',       'financas',      'Ver lançamentos'),
  ('financas.lancamento.editar',    'financas',      'Lançar receitas e despesas'),
  ('financas.orcamento.gerenciar',  'financas',      'Gerenciar orçamentos e metas'),
  ('saude.medicamento.ver',         'saude',         'Ver medicamentos'),
  ('saude.medicamento.editar',      'saude',         'Gerenciar medicamentos'),
  ('saude.consulta.gerenciar',      'saude',         'Gerenciar consultas'),
  ('saude.indicador.gerenciar',     'saude',         'Gerenciar indicadores de saúde'),
  ('saude.documento.gerenciar',     'saude',         'Gerenciar exames e documentos'),
  ('agenda.evento.ver',             'agenda',        'Ver compromissos'),
  ('agenda.evento.editar',          'agenda',        'Gerenciar compromissos'),
  ('agenda.tarefa.gerenciar',       'agenda',        'Gerenciar tarefas'),
  ('painel.hoje.ver',               'painel',        'Ver o painel Hoje'),
  ('painel.relatorio.exportar',     'painel',        'Exportar relatórios'),
  ('sincronizacao.sincronizar',     'sincronizacao', 'Sincronizar dados'),
  ('administracao.modulo.gerenciar',   'administracao', 'Cadastrar e editar módulos'),
  ('administracao.liberacao.gerenciar','administracao', 'Liberar módulos para usuários, grupos e planos');

CREATE TABLE perfil (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo        text NOT NULL UNIQUE,
  nome          text NOT NULL,
  descricao     text,
  sistema       boolean NOT NULL DEFAULT false,   -- perfis de fabrica nao se apagam
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE perfil_permissao (
  perfil_id       uuid NOT NULL REFERENCES perfil (id) ON DELETE CASCADE,
  permissao_codigo text NOT NULL REFERENCES permissao (codigo) ON DELETE CASCADE,
  PRIMARY KEY (perfil_id, permissao_codigo)
);

INSERT INTO perfil (codigo, nome, descricao, sistema) VALUES
  ('administrador', 'Administrador',   'Acesso total, inclusive cadastro de usuários e módulos', true),
  ('usuario',       'Usuário',         'Usa finanças, saúde, agenda e painel', true),
  ('leitura',       'Somente leitura', 'Só consulta; não altera dados', true);

INSERT INTO perfil_permissao (perfil_id, permissao_codigo)
  SELECT p.id, a.codigo FROM perfil p, permissao a WHERE p.codigo = 'administrador';
INSERT INTO perfil_permissao (perfil_id, permissao_codigo)
  SELECT p.id, a.codigo FROM perfil p, permissao a
   WHERE p.codigo = 'usuario'
     AND (a.modulo_codigo IN ('financas', 'saude', 'agenda', 'painel', 'sincronizacao')
          OR a.codigo = 'licencas.licenca.ver');
INSERT INTO perfil_permissao (perfil_id, permissao_codigo)
  SELECT p.id, a.codigo FROM perfil p, permissao a
   WHERE p.codigo = 'leitura'
     AND (a.codigo ~ '\.ver$' AND a.modulo_codigo IN ('financas', 'saude', 'agenda', 'painel')
          OR a.codigo = 'licencas.licenca.ver');

CREATE TABLE grupo (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome          text NOT NULL UNIQUE,
  descricao     text,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE grupo_perfil (
  grupo_id  uuid NOT NULL REFERENCES grupo (id) ON DELETE CASCADE,
  perfil_id uuid NOT NULL REFERENCES perfil (id) ON DELETE CASCADE,
  PRIMARY KEY (grupo_id, perfil_id)
);

CREATE TABLE usuario_grupo (
  usuario_id uuid NOT NULL REFERENCES usuario (id) ON DELETE CASCADE,
  grupo_id   uuid NOT NULL REFERENCES grupo (id) ON DELETE CASCADE,
  PRIMARY KEY (usuario_id, grupo_id)
);

CREATE TABLE usuario_perfil (
  usuario_id uuid NOT NULL REFERENCES usuario (id) ON DELETE CASCADE,
  perfil_id  uuid NOT NULL REFERENCES perfil (id) ON DELETE CASCADE,
  PRIMARY KEY (usuario_id, perfil_id)
);

-- Excecao individual: concedida = true libera, false nega (a negacao vence).
CREATE TABLE usuario_permissao (
  usuario_id       uuid NOT NULL REFERENCES usuario (id) ON DELETE CASCADE,
  permissao_codigo text NOT NULL REFERENCES permissao (codigo) ON DELETE CASCADE,
  concedida        boolean NOT NULL,
  PRIMARY KEY (usuario_id, permissao_codigo)
);

-- =====================================================================
-- LICENCAS: planos, precos, licencas e pagamentos
-- Por enquanto tudo e gratuito: configuracao.cobranca_ativa = 'false'.
-- Quando a cobranca for ligada, so quem tem licenca paga vigente
-- (mensal, anual ou vitalicia) tem acesso (ver tem_acesso).
-- NUNCA guardar numero de cartao: so os 4 ultimos digitos e a bandeira.
-- =====================================================================
CREATE TABLE configuracao (
  chave text PRIMARY KEY,
  valor text NOT NULL
);
INSERT INTO configuracao (chave, valor) VALUES ('cobranca_ativa', 'false');

CREATE TABLE plano (
  codigo        text PRIMARY KEY,
  nome          text NOT NULL,
  periodo       tipo_periodo NOT NULL,
  duracao_meses integer,                    -- mensal 1, anual 12; gratuito e vitalicio: nulo
  ativo         boolean NOT NULL DEFAULT true,
  CONSTRAINT ck_plano_duracao CHECK (
    (periodo IN ('gratuito', 'vitalicio') AND duracao_meses IS NULL)
    OR (periodo IN ('mensal', 'anual') AND coalesce(duracao_meses > 0, false)))
);
INSERT INTO plano (codigo, nome, periodo, duracao_meses) VALUES
  ('gratuito',  'Gratuito',  'gratuito',  NULL),
  ('mensal',    'Mensal',    'mensal',    1),
  ('anual',     'Anual',     'anual',     12),
  ('vitalicio', 'Vitalício', 'vitalicio', NULL);

-- Um preco por plano e por moeda (valores ainda a definir).
CREATE TABLE plano_preco (
  plano_codigo   text NOT NULL REFERENCES plano (codigo) ON DELETE CASCADE,
  moeda          char(3) NOT NULL,
  valor_centavos integer NOT NULL CHECK (valor_centavos > 0),
  PRIMARY KEY (plano_codigo, moeda)
);

-- Liberacao de modulo: para UM usuario, UM grupo ou UM plano.
CREATE TABLE liberacao_modulo (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  modulo_codigo text NOT NULL REFERENCES modulo (codigo) ON DELETE CASCADE,
  usuario_id    uuid REFERENCES usuario (id) ON DELETE CASCADE,
  grupo_id      uuid REFERENCES grupo (id) ON DELETE CASCADE,
  plano_codigo  text REFERENCES plano (codigo) ON DELETE CASCADE,
  concedida     boolean NOT NULL DEFAULT true,   -- false = bloqueio explicito
  ativa         boolean NOT NULL DEFAULT true,   -- false = liberacao desativada (nao vale, mas fica cadastrada)
  vitalicio     boolean NOT NULL DEFAULT true,   -- true = sem data de validade; false = vale entre inicio e fim
  inicio        timestamptz,
  fim           timestamptz,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_liberacao_alvo CHECK (num_nonnulls(usuario_id, grupo_id, plano_codigo) = 1),
  CONSTRAINT ck_liberacao_vigencia CHECK (fim IS NULL OR inicio IS NULL OR fim > inicio),
  CONSTRAINT ck_liberacao_validade CHECK (vitalicio OR (inicio IS NOT NULL AND fim IS NOT NULL))
);
CREATE INDEX ix_liberacao_modulo ON liberacao_modulo (modulo_codigo);
-- Uma liberacao por usuario em cada modulo.
CREATE UNIQUE INDEX ux_liberacao_usuario ON liberacao_modulo (modulo_codigo, usuario_id) WHERE usuario_id IS NOT NULL;

-- Todos os planos liberam, de partida, os modulos de uso diario.
INSERT INTO liberacao_modulo (modulo_codigo, plano_codigo)
  SELECT m.codigo, p.codigo
    FROM modulo m, plano p
   WHERE m.codigo IN ('financas', 'saude', 'agenda', 'painel', 'sincronizacao');
-- ...e fazem parte do pacote (o SuperUsuario pode mudar isso no cadastro de modulos).
UPDATE modulo SET no_pacote = true WHERE codigo IN ('financas', 'saude', 'agenda', 'painel', 'sincronizacao');

CREATE TABLE licenca (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    uuid NOT NULL REFERENCES usuario (id) ON DELETE CASCADE,
  plano_codigo  text NOT NULL REFERENCES plano (codigo),
  status        status_licenca NOT NULL DEFAULT 'ativa',
  origem        origem_licenca NOT NULL,
  inicio        timestamptz NOT NULL DEFAULT now(),
  fim           timestamptz,                 -- nulo = sem data de termino
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_licenca_fim CHECK (fim IS NULL OR fim > inicio)
);
CREATE INDEX ix_licenca_usuario ON licenca (usuario_id, status);

CREATE TABLE pagamento (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id     uuid NOT NULL REFERENCES usuario (id) ON DELETE CASCADE,
  licenca_id     uuid REFERENCES licenca (id),
  plano_codigo   text NOT NULL REFERENCES plano (codigo),
  metodo         metodo_pagamento NOT NULL,
  status         status_pagamento NOT NULL DEFAULT 'pendente',
  valor_centavos integer NOT NULL CHECK (valor_centavos > 0),
  moeda          char(3) NOT NULL,
  gateway        text,
  id_externo     text,
  pix_codigo     text,                       -- "copia e cola" do Pix
  pix_expira_em  timestamptz,
  cartao_final   char(4),
  cartao_bandeira text,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ck_pagamento_final CHECK (cartao_final IS NULL OR cartao_final ~ '^[0-9]{4}$'),
  UNIQUE (gateway, id_externo)
);
CREATE INDEX ix_pagamento_usuario ON pagamento (usuario_id, criado_em DESC);

-- =====================================================================
-- FUNCOES DE ACESSO (rodam com os direitos do dono do esquema)
-- =====================================================================

-- true quando a sessao esta em modo administrador (definido so pela API).
CREATE FUNCTION e_admin() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT coalesce(current_setting('app.admin', true), '') = 'on'
$$;

-- Tem acesso ao app? Cobranca desligada: todos. Ligada: licenca paga vigente.
CREATE FUNCTION tem_acesso(u uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  SELECT coalesce((SELECT valor FROM configuracao WHERE chave = 'cobranca_ativa'), 'false') <> 'true'
      OR EXISTS (
           SELECT 1 FROM licenca l
            WHERE l.usuario_id = u AND l.status = 'ativa'
              AND l.plano_codigo <> 'gratuito'
              AND l.inicio <= now() AND (l.fim IS NULL OR l.fim > now()))
$$;

-- O modulo esta liberado para o usuario (direto, por grupo ou por plano)?
-- Qualquer bloqueio vigente vence a liberacao.
CREATE FUNCTION modulo_liberado(u uuid, m text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  WITH alvo AS (
    SELECT l.concedida
      FROM liberacao_modulo l
     WHERE l.modulo_codigo = m
       AND l.ativa
       AND (l.vitalicio OR ((l.inicio IS NULL OR l.inicio <= now()) AND (l.fim IS NULL OR l.fim > now())))
       AND (l.usuario_id = u
            OR l.grupo_id IN (SELECT grupo_id FROM usuario_grupo WHERE usuario_id = u)
            OR l.plano_codigo IN (SELECT plano_codigo FROM licenca
                                   WHERE usuario_id = u AND status = 'ativa'
                                     AND inicio <= now() AND (fim IS NULL OR fim > now())))
  )
  SELECT EXISTS (SELECT 1 FROM modulo WHERE codigo = m AND ativo)
     AND ( coalesce((SELECT liberado_para_todos FROM modulo WHERE codigo = m), false)
           OR ( NOT EXISTS (SELECT 1 FROM alvo WHERE NOT concedida)
                AND ( coalesce((SELECT no_pacote FROM modulo WHERE codigo = m), false)
                      OR EXISTS (SELECT 1 FROM alvo WHERE concedida) ) ) )
$$;

-- Permissoes efetivas: perfis individuais + perfis dos grupos + concessoes
-- individuais, menos as negadas, e so de modulos liberados.
CREATE FUNCTION permissoes_do_usuario(u uuid) RETURNS SETOF text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  WITH base AS (
    SELECT pp.permissao_codigo
      FROM usuario_perfil up JOIN perfil_permissao pp ON pp.perfil_id = up.perfil_id
     WHERE up.usuario_id = u
    UNION
    SELECT pp.permissao_codigo
      FROM usuario_grupo ug
      JOIN grupo_perfil gp ON gp.grupo_id = ug.grupo_id
      JOIN perfil_permissao pp ON pp.perfil_id = gp.perfil_id
     WHERE ug.usuario_id = u
    UNION
    SELECT permissao_codigo FROM usuario_permissao WHERE usuario_id = u AND concedida
  )
  SELECT p.codigo
    FROM base b JOIN permissao p ON p.codigo = b.permissao_codigo
   WHERE NOT EXISTS (SELECT 1 FROM usuario_permissao x
                      WHERE x.usuario_id = u AND x.permissao_codigo = p.codigo AND NOT x.concedida)
     AND modulo_liberado(u, p.modulo_codigo)
   ORDER BY p.codigo
$$;

-- Modulos que o usuario pode abrir (liberados e com ao menos uma permissao).
CREATE FUNCTION modulos_do_usuario(u uuid) RETURNS SETOF text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  SELECT DISTINCT p.modulo_codigo
    FROM permissoes_do_usuario(u) c JOIN permissao p ON p.codigo = c
   ORDER BY 1
$$;

-- true se o usuario e o SuperUsuario (unico com acesso aos dados de todos).
CREATE FUNCTION e_superusuario(u uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  SELECT coalesce((SELECT superusuario FROM usuario WHERE id = u AND excluido_em IS NULL AND ativo), false)
$$;

-- Login: a API ainda nao sabe o id, so o e-mail. Devolve o necessario
-- para conferir a senha (a conferencia do hash e feita na API).
CREATE FUNCTION buscar_login(p_email text)
RETURNS TABLE (id uuid, nome text, senha_hash text, ativo boolean,
               bloqueado_ate timestamptz, tentativas_login integer,
               idioma text, pais char(2))
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = controle, public AS $$
  SELECT u.id, u.nome, u.senha_hash, u.ativo, u.bloqueado_ate, u.tentativas_login,
         u.idioma, u.pais
    FROM usuario u
   WHERE u.email = lower(btrim(p_email)) AND u.excluido_em IS NULL
$$;

-- Registra o resultado de uma tentativa de login. 5 erros seguidos
-- bloqueiam a conta por 15 minutos.
CREATE FUNCTION registrar_login(p_id uuid, p_ok boolean) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = controle, public AS $$
  UPDATE usuario
     SET tentativas_login = CASE WHEN p_ok THEN 0 ELSE tentativas_login + 1 END,
         bloqueado_ate    = CASE WHEN p_ok THEN NULL
                                 WHEN tentativas_login + 1 >= 5 THEN now() + interval '15 minutes'
                                 ELSE bloqueado_ate END,
         ultimo_login_em  = CASE WHEN p_ok THEN now() ELSE ultimo_login_em END
   WHERE id = p_id
$$;

-- Cadastro de usuario novo: cria o usuario com o perfil "usuario" e a
-- licenca gratuita. Pais e idioma em branco usam os padroes do pais.
CREATE FUNCTION cadastrar_usuario(p_nome text, p_email text, p_senha_hash text,
                                  p_pais text DEFAULT 'BR', p_idioma text DEFAULT NULL,
                                  p_cpf text DEFAULT NULL, p_telefone text DEFAULT NULL,
                                  p_nascimento date DEFAULT NULL, p_endereco jsonb DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = controle, public AS $$
DECLARE
  v_pais pais%ROWTYPE;
  v_idioma text;
  v_id uuid;
BEGIN
  SELECT * INTO v_pais FROM pais WHERE codigo = upper(coalesce(p_pais, 'BR')) AND ativo;
  IF NOT FOUND THEN RAISE EXCEPTION 'pais invalido ou inativo: %', p_pais; END IF;
  v_idioma := coalesce(p_idioma, v_pais.idioma_padrao);
  IF NOT EXISTS (SELECT 1 FROM idioma WHERE codigo = v_idioma AND ativo) THEN
    RAISE EXCEPTION 'idioma invalido ou inativo: %', v_idioma;
  END IF;
  IF p_senha_hash IS NULL OR length(p_senha_hash) < 20 THEN
    RAISE EXCEPTION 'senha_hash ausente: a API deve enviar o hash da senha';
  END IF;

  -- p_endereco: {"cep","logradouro","numero","complemento","bairro","cidade","uf"} (todos opcionais)
  INSERT INTO usuario (nome, email, senha_hash, pais, idioma, fuso_horario, moeda_padrao,
                       cpf, telefone, data_nascimento,
                       cep, logradouro, numero, complemento, bairro, cidade, uf)
  VALUES (btrim(p_nome), lower(btrim(p_email)), p_senha_hash, v_pais.codigo, v_idioma,
          v_pais.fuso_padrao, v_pais.moeda_padrao,
          nullif(p_cpf, ''), nullif(p_telefone, ''), p_nascimento,
          nullif(p_endereco->>'cep', ''), nullif(p_endereco->>'logradouro', ''),
          nullif(p_endereco->>'numero', ''), nullif(p_endereco->>'complemento', ''),
          nullif(p_endereco->>'bairro', ''), nullif(p_endereco->>'cidade', ''),
          nullif(upper(p_endereco->>'uf'), ''))
  RETURNING id INTO v_id;

  INSERT INTO usuario_perfil (usuario_id, perfil_id)
    SELECT v_id, id FROM perfil WHERE codigo = 'usuario';
  INSERT INTO licenca (usuario_id, plano_codigo, status, origem)
    VALUES (v_id, 'gratuito', 'ativa', 'gratuita');
  RETURN v_id;
END $$;

-- Execucao so para quem a API usa (o script de papel concede ao app_api).
REVOKE ALL ON FUNCTION tem_acesso(uuid), modulo_liberado(uuid, text),
  permissoes_do_usuario(uuid), modulos_do_usuario(uuid), buscar_login(text),
  registrar_login(uuid, boolean), e_superusuario(uuid),
  cadastrar_usuario(text, text, text, text, text, text, text, date, jsonb)
  FROM PUBLIC;

-- ---------- Triggers de atualizado_em ----------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'usuario','conta','categoria','evento','tarefa','lancamento','orcamento',
    'meta','consulta','medicamento','registro_tomada','indicador','documento','lembrete'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_atualizado BEFORE INSERT OR UPDATE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION set_atualizado_em()', t);
  END LOOP;
END $$;

-- ---------- Integridade entre usuarios, lembretes e dados do usuario ----------
-- A chave estrangeira nao passa pela RLS: sem isto, a usuaria A poderia gravar
-- um lancamento apontando para a conta da usuaria B. Cada referencia abaixo
-- precisa pertencer ao MESMO usuario. Argumentos: pares (coluna, tabela).
CREATE FUNCTION verifica_dono() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = controle, public AS $$
DECLARE
  i int := 0;
  v text;
  dono uuid;
  achou int;
BEGIN
  WHILE i < TG_NARGS LOOP
    v := to_jsonb(NEW) ->> TG_ARGV[i];
    IF v IS NOT NULL THEN
      EXECUTE format('SELECT usuario_id FROM %I WHERE id = $1', TG_ARGV[i + 1])
        INTO dono USING v::uuid;
      GET DIAGNOSTICS achou = ROW_COUNT;
      -- Referencia inexistente: deixa a chave estrangeira reportar o erro padrao.
      IF achou > 0 AND dono IS DISTINCT FROM NEW.usuario_id THEN
        RAISE EXCEPTION 'referencia invalida: % pertence a outro usuario', TG_ARGV[i]
          USING ERRCODE = '23503';
      END IF;
    END IF;
    i := i + 2;
  END LOOP;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_categoria_dono   BEFORE INSERT OR UPDATE ON categoria
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('categoria_mae_id', 'categoria');
CREATE TRIGGER trg_tarefa_dono      BEFORE INSERT OR UPDATE ON tarefa
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('evento_id', 'evento');
CREATE TRIGGER trg_lancamento_dono  BEFORE INSERT OR UPDATE ON lancamento
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('conta_id', 'conta', 'categoria_id', 'categoria');
CREATE TRIGGER trg_orcamento_dono   BEFORE INSERT OR UPDATE ON orcamento
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('categoria_id', 'categoria');
CREATE TRIGGER trg_meta_dono        BEFORE INSERT OR UPDATE ON meta
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('conta_id', 'conta');
CREATE TRIGGER trg_consulta_dono    BEFORE INSERT OR UPDATE ON consulta
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('evento_id', 'evento', 'lancamento_id', 'lancamento');
CREATE TRIGGER trg_tomada_dono      BEFORE INSERT OR UPDATE ON registro_tomada
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('medicamento_id', 'medicamento');
CREATE TRIGGER trg_documento_dono   BEFORE INSERT OR UPDATE ON documento
  FOR EACH ROW EXECUTE FUNCTION verifica_dono('consulta_id', 'consulta', 'lancamento_id', 'lancamento');

-- Lembrete: o alvo e polimorfico (sem chave estrangeira). Confere que o alvo
-- existe e e do mesmo usuario. Na sincronizacao, envie o lembrete DEPOIS do alvo.
CREATE FUNCTION verifica_alvo_lembrete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = controle, public AS $$
DECLARE dono uuid;
BEGIN
  EXECUTE format('SELECT usuario_id FROM %I WHERE id = $1', NEW.alvo_tipo::text)
    INTO dono USING NEW.alvo_id;
  IF dono IS DISTINCT FROM NEW.usuario_id THEN
    RAISE EXCEPTION 'lembrete aponta para % inexistente ou de outro usuario', NEW.alvo_tipo
      USING ERRCODE = '23503';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_lembrete_alvo BEFORE INSERT OR UPDATE ON lembrete
  FOR EACH ROW EXECUTE FUNCTION verifica_alvo_lembrete();

-- Usuario: fuso horario precisa existir e a moeda precisa estar no catalogo de paises.
CREATE FUNCTION verifica_preferencias_usuario() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = controle, public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.fuso_horario) THEN
    RAISE EXCEPTION 'fuso horario invalido: %', NEW.fuso_horario USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pais WHERE moeda_padrao = NEW.moeda_padrao) THEN
    RAISE EXCEPTION 'moeda invalida (fora do catalogo de paises): %', NEW.moeda_padrao
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_usuario_preferencias BEFORE INSERT OR UPDATE ON usuario
  FOR EACH ROW EXECUTE FUNCTION verifica_preferencias_usuario();

-- ---------- Seguranca por linha (RLS) ----------
-- Cada usuario enxerga so os proprios dados. A aplicacao define o usuario
-- da sessao, dentro da transacao, com:
--     SELECT set_config('app.usuario_id', '<uuid>', true);
-- Sem esse valor (ou com ele vazio, como fica numa conexao reaproveitada
-- apos o COMMIT) nenhuma linha e visivel.
-- A API deve conectar com um papel que NAO seja dono das tabelas nem
-- superusuario: donos e superusuarios ignoram a RLS.
-- No cadastro de um usuario novo, a API define app.usuario_id com o id
-- que sera criado antes do INSERT em "usuario".
-- (No Supabase, troque a expressao pelo auth.uid().)
DO $$
DECLARE
  t text;
  coluna text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'usuario','conta','categoria','evento','tarefa','lancamento','orcamento',
    'meta','consulta','medicamento','registro_tomada','indicador','documento','lembrete'
  ] LOOP
    coluna := CASE WHEN t = 'usuario' THEN 'id' ELSE 'usuario_id' END;
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY p_%1$s_dono ON %1$I
         USING (%2$I = nullif(current_setting(''app.usuario_id'', true), '''')::uuid)
         WITH CHECK (%2$I = nullif(current_setting(''app.usuario_id'', true), '''')::uuid)',
      t, coluna);
  END LOOP;
END $$;

-- ---------- Triggers de atualizado_em (tabelas de acesso e licenca) ----------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['perfil', 'grupo', 'licenca', 'pagamento'] LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_atualizado BEFORE UPDATE ON %1$s
         FOR EACH ROW EXECUTE FUNCTION set_atualizado_em()', t);
  END LOOP;
END $$;

-- ---------- Seguranca por linha: acesso, licencas e catalogos ----------
-- Modo administrador: a API so liga app.admin = 'on' depois de conferir a
-- permissao do usuario logado (ex.: acesso.usuario.editar). Nesse modo a
-- sessao pode ler e gravar o cadastro de todos.
--   SELECT set_config('app.admin', 'on', true);

-- Administrador enxerga e altera tambem os usuarios.
CREATE POLICY p_usuario_admin ON usuario USING (e_admin()) WITH CHECK (e_admin());

-- Catalogos e cadastros gerais: todos leem; so o administrador grava.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'idioma', 'pais', 'modulo', 'permissao', 'plano', 'plano_preco', 'configuracao',
    'perfil', 'perfil_permissao', 'grupo_perfil'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY p_%1$s_leitura ON %1$I FOR SELECT USING (true)', t);
    EXECUTE format('CREATE POLICY p_%1$s_admin ON %1$I USING (e_admin()) WITH CHECK (e_admin())', t);
  END LOOP;
END $$;

-- Vinculos do usuario (perfil, grupo, excecoes): o usuario so le os proprios;
-- quem concede e o administrador (ninguem se da permissao sozinho).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['usuario_perfil', 'usuario_grupo', 'usuario_permissao', 'licenca'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY p_%1$s_leitura ON %1$I FOR SELECT
         USING (usuario_id = nullif(current_setting(''app.usuario_id'', true), '''')::uuid)', t);
    EXECUTE format('CREATE POLICY p_%1$s_admin ON %1$I USING (e_admin()) WITH CHECK (e_admin())', t);
  END LOOP;
END $$;

-- Grupo: o membro enxerga os grupos de que participa.
ALTER TABLE grupo ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_grupo_membro ON grupo FOR SELECT
  USING (id IN (SELECT grupo_id FROM usuario_grupo
                 WHERE usuario_id = nullif(current_setting('app.usuario_id', true), '')::uuid));
CREATE POLICY p_grupo_admin ON grupo USING (e_admin()) WITH CHECK (e_admin());

-- Liberacao de modulo: ve as proprias e as de grupo/plano (sem usuario).
ALTER TABLE liberacao_modulo ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_liberacao_leitura ON liberacao_modulo FOR SELECT
  USING (usuario_id IS NULL
         OR usuario_id = nullif(current_setting('app.usuario_id', true), '')::uuid);
CREATE POLICY p_liberacao_admin ON liberacao_modulo USING (e_admin()) WITH CHECK (e_admin());

-- Pagamento: o usuario le os proprios e abre um pagamento pendente para si.
ALTER TABLE pagamento ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_pagamento_leitura ON pagamento FOR SELECT
  USING (usuario_id = nullif(current_setting('app.usuario_id', true), '')::uuid);
CREATE POLICY p_pagamento_abrir ON pagamento FOR INSERT
  WITH CHECK (usuario_id = nullif(current_setting('app.usuario_id', true), '')::uuid
              AND status = 'pendente');
CREATE POLICY p_pagamento_admin ON pagamento USING (e_admin()) WITH CHECK (e_admin());
