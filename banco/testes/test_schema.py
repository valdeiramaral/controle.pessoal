#!/usr/bin/env python3
"""Testes do esquema PostgreSQL (banco/schema.sql).

Cria um banco novo, carrega o schema e verifica restricoes, triggers,
chaves estrangeiras e a seguranca por linha (RLS).

Uso:
    python3 test_schema.py [caminho/do/schema.sql]

Variaveis de ambiente (padrao do psql): PGHOST, PGPORT, PGUSER.
Requer o cliente `psql` e um servidor PostgreSQL 13+ acessivel.
"""
import os
import subprocess
import sys

SCHEMA = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "schema.sql")
DB = "ctrl_teste"

A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"   # usuaria A
B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"   # usuaria B
CONTA_A = "cccccccc-cccc-cccc-cccc-cccccccccccc"
CONTA_B = "cccccccc-cccc-cccc-cccc-dddddddddddd"
CAT_A = "dddddddd-dddd-dddd-dddd-dddddddddddd"


def psql(sql, db=DB, check=False):
    p = subprocess.run(
        ["psql", "-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", db],
        input=sql, capture_output=True, text=True)
    if check and p.returncode != 0:
        sys.exit("ERRO no preparo do teste:\n" + p.stderr)
    return p


def preparar():
    psql("DROP DATABASE IF EXISTS %s;" % DB, db="postgres")
    # DROP/CREATE DATABASE nao rodam em transacao; cada um em sua chamada.
    psql("CREATE DATABASE %s;" % DB, db="postgres", check=True)
    with open(SCHEMA, encoding="utf-8") as f:
        psql(f.read(), check=True)
    psql("""
        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_teste') THEN
            CREATE ROLE app_teste LOGIN NOSUPERUSER NOBYPASSRLS;
          END IF;
        END $$;
        GRANT USAGE ON SCHEMA controle TO app_teste;
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA controle TO app_teste;
        GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA controle TO app_teste;
        SET search_path TO controle, public;
        INSERT INTO usuario (id, nome, email) VALUES
          ('%(A)s', 'Ana', 'ana@exemplo.com'), ('%(B)s', 'Bia', 'bia@exemplo.com');
        INSERT INTO conta (id, usuario_id, nome, tipo) VALUES
          ('%(CA)s', '%(A)s', 'Carteira A', 'dinheiro'),
          ('%(CB)s', '%(B)s', 'Carteira B', 'dinheiro');
        INSERT INTO categoria (id, usuario_id, nome, tipo) VALUES
          ('%(CAT)s', '%(A)s', 'Mercado', 'despesa');
    """ % dict(A=A, B=B, CA=CONTA_A, CB=CONTA_B, CAT=CAT_A), check=True)


resultados = []


def teste(nome, sql, erro=None, valor=None, como=None, usuario=None, cru=False):
    """Roda `sql` em uma transacao revertida.

    erro:  texto que deve aparecer na mensagem de erro (o SQL DEVE falhar).
    valor: texto esperado na ultima linha de saida (o SQL NAO pode falhar).
    como:  papel (role) em que o SQL roda, ex. 'app_teste'.
    usuario: define app.usuario_id (so com `como`).
    cru:   nao envolve em transacao (para testar o uso da mesma sessao).
    """
    partes = ["SET search_path TO controle, public;"]
    if cru:
        partes.append(sql)
    else:
        partes.append("BEGIN;")
        if como:
            partes.append("SET LOCAL ROLE %s;" % como)
        if usuario:
            partes.append("SELECT set_config('app.usuario_id', '%s', true);" % usuario)
        partes.append(sql)
        partes.append("ROLLBACK;")
    p = psql("\n".join(partes))
    saida = [l for l in p.stdout.strip().splitlines() if l.strip()]
    ultima = saida[-1] if saida else ""
    if erro is not None:
        ok = p.returncode != 0 and erro.lower() in p.stderr.lower()
        detalhe = "esperava erro com '%s', veio: %s" % (
            erro, (p.stderr.strip().splitlines() or ["(sem erro)"])[0])
    elif valor is not None:
        ok = p.returncode == 0 and ultima == valor
        detalhe = "esperava '%s', veio '%s' %s" % (
            valor, ultima, p.stderr.strip()[:200])
    else:
        ok = p.returncode == 0
        detalhe = p.stderr.strip()[:200]
    resultados.append((nome, ok, "" if ok else detalhe))


def main():
    preparar()

    # ---------------- Estrutura ----------------
    teste("31 tabelas criadas (14 de dados + 17 de acesso, licencas e catalogos)",
          "SELECT count(*) FROM information_schema.tables "
          "WHERE table_schema='controle' AND table_type='BASE TABLE';",
          valor="31")
    teste("toda tabela tem id, usuario_id, criado_em, atualizado_em, excluido_em",
          """SELECT count(*) FROM information_schema.tables t
             WHERE table_schema='controle' AND table_type='BASE TABLE'
               AND t.table_name IN ('usuario','conta','categoria','evento','tarefa','lancamento',
                   'orcamento','meta','consulta','medicamento','registro_tomada','indicador',
                   'documento','lembrete')
               AND (SELECT count(*) FROM information_schema.columns c
                    WHERE c.table_schema='controle' AND c.table_name=t.table_name
                      AND c.column_name IN ('id','usuario_id','criado_em','atualizado_em','excluido_em'))
                   <> CASE WHEN t.table_name='usuario' THEN 4 ELSE 5 END;""",
          valor="0")

    # ---------------- Defaults e triggers ----------------
    teste("UUID e datas preenchidos por padrao",
          "INSERT INTO usuario (nome, email) VALUES ('Cris','c@x.com') "
          "RETURNING length(id::text) = 36 AND criado_em IS NOT NULL;",
          valor="t")
    teste("trigger atualiza atualizado_em no UPDATE",
          "UPDATE conta SET nome = 'Renomeada' WHERE id = '%s'; "
          "SELECT atualizado_em > criado_em FROM conta WHERE id = '%s';" % (CONTA_A, CONTA_A),
          valor="t")
    teste("exclusao logica: linha continua gravada com excluido_em",
          "UPDATE conta SET excluido_em = now() WHERE id = '%s'; "
          "SELECT count(*) FROM conta WHERE id = '%s' AND excluido_em IS NOT NULL;" % (CONTA_A, CONTA_A),
          valor="1")

    # ---------------- Restricoes de dados ----------------
    ins_lanc = ("INSERT INTO lancamento (usuario_id, conta_id, valor, data, descricao, tipo%s) "
                "VALUES ('%s', '%s', %s, '2026-10-19', 'Teste', 'despesa'%s);")
    teste("lancamento valido entra (tags vazias por padrao)",
          ins_lanc % ("", A, CONTA_A, "12.50", "") +
          " SELECT count(*) FROM lancamento WHERE tags = '{}';",
          valor="1")
    teste("lancamento com valor negativo e recusado",
          ins_lanc % ("", A, CONTA_A, "-1", ""), erro="check constraint")
    teste("lancamento com parcela 3 de 2 e recusado",
          ins_lanc % (", parcela_numero, parcela_total", A, CONTA_A, "10", ", 3, 2"),
          erro="check constraint")
    teste("lancamento com conta inexistente e recusado (chave estrangeira)",
          ins_lanc % ("", A, "00000000-0000-0000-0000-000000000000", "10", ""),
          erro="foreign key")
    teste("tipo (enum) invalido e recusado",
          "INSERT INTO conta (usuario_id, nome, tipo) VALUES ('%s','X','investimento');" % A,
          erro="invalid input value for enum")
    teste("evento com fim antes do inicio e recusado",
          "INSERT INTO evento (usuario_id, titulo, inicio, fim) VALUES "
          "('%s','Reuniao','2026-10-20 10:00+00','2026-10-20 09:00+00');" % A,
          erro="check constraint")
    teste("conta com dia de fechamento 32 e recusada",
          "INSERT INTO conta (usuario_id, nome, tipo, dia_fechamento) "
          "VALUES ('%s','Cartao','cartao',32);" % A,
          erro="check constraint")
    teste("e-mail de usuario duplicado e recusado",
          "INSERT INTO usuario (nome, email) VALUES ('Outra','ana@exemplo.com');",
          erro="duplicate key")
    teste("e-mail de usuario excluido logicamente pode ser reaproveitado",
          "UPDATE usuario SET excluido_em = now() WHERE id = '%s'; "
          "INSERT INTO usuario (nome, email) VALUES ('Nova Bia','bia@exemplo.com') "
          "RETURNING 'ok';" % B, valor="ok")
    teste("medicamento com fim antes do inicio e recusado",
          "INSERT INTO medicamento (usuario_id, nome, dose, horarios, inicio, fim) "
          "VALUES ('%s','Dipirona','1 comp','{08:00}','2026-10-20','2026-10-19');" % A,
          erro="check constraint")
    teste("medicamento com estoque negativo e recusado",
          "INSERT INTO medicamento (usuario_id, nome, dose, horarios, inicio, estoque) "
          "VALUES ('%s','Dipirona','1 comp','{08:00}','2026-10-20',-1);" % A,
          erro="check constraint")

    # ---------------- Orcamento ----------------
    orc = ("INSERT INTO orcamento (usuario_id, categoria_id, mes, valor_limite) "
           "VALUES ('%s','%s','%%s',500);" % (A, CAT_A))
    teste("orcamento so aceita mes no dia 1",
          orc % "2026-10-15", erro="check constraint")
    teste("orcamento duplicado (categoria + mes) e recusado",
          (orc % "2026-10-01") + (orc % "2026-10-01"), erro="duplicate key")
    teste("orcamento pode ser refeito depois de excluido logicamente",
          (orc % "2026-10-01") +
          "UPDATE orcamento SET excluido_em = now(); " + (orc % "2026-10-01") +
          " SELECT count(*) FROM orcamento WHERE excluido_em IS NULL;",
          valor="1")

    # ---------------- Medicamentos e tomadas ----------------
    med = ("INSERT INTO medicamento (id, usuario_id, nome, dose, horarios, inicio) VALUES "
           "('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','%s','Losartana','1 comp','{08:00,20:00}','2026-10-19');" % A)
    tom = ("INSERT INTO registro_tomada (usuario_id, medicamento_id, horario_previsto) VALUES "
           "('%s','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','2026-10-19 08:00+00');" % A)
    teste("medicamento guarda varios horarios",
          med + " SELECT array_length(horarios, 1) FROM medicamento;", valor="2")
    teste("tomada duplicada no mesmo horario e recusada",
          med + tom + tom, erro="duplicate key")
    teste("tomada comeca como pendente",
          med + tom + " SELECT status FROM registro_tomada;", valor="pendente")

    # ---------------- Ligacoes entre modulos ----------------
    teste("consulta gera evento e lancamento de custo; documento e lembrete se ligam",
          """INSERT INTO evento (id, usuario_id, titulo, inicio, tipo) VALUES
               ('11111111-1111-1111-1111-111111111111','%(A)s','Cardiologista','2026-10-25 14:00+00','saude');
             INSERT INTO lancamento (id, usuario_id, conta_id, valor, data, descricao, tipo) VALUES
               ('22222222-2222-2222-2222-222222222222','%(A)s','%(C)s',350,'2026-10-25','Consulta','despesa');
             INSERT INTO consulta (id, usuario_id, evento_id, lancamento_id, medico, data_hora) VALUES
               ('33333333-3333-3333-3333-333333333333','%(A)s','11111111-1111-1111-1111-111111111111',
                '22222222-2222-2222-2222-222222222222','Dr. Souza','2026-10-25 14:00+00');
             INSERT INTO documento (usuario_id, consulta_id, arquivo_url, nome_arquivo, tipo) VALUES
               ('%(A)s','33333333-3333-3333-3333-333333333333','exames/ecg.pdf','ecg.pdf','exame');
             INSERT INTO lembrete (usuario_id, alvo_tipo, alvo_id, antecedencia_min) VALUES
               ('%(A)s','consulta','33333333-3333-3333-3333-333333333333',1440);
             SELECT count(*) FROM consulta c
               JOIN evento e ON e.id = c.evento_id
               JOIN lancamento l ON l.id = c.lancamento_id
               JOIN documento d ON d.consulta_id = c.id
               JOIN lembrete m ON m.alvo_id = c.id;""" % dict(A=A, C=CONTA_A),
          valor="1")
    teste("indicador de pressao guarda sistolica e diastolica",
          "INSERT INTO indicador (usuario_id, tipo, valor, valor_secundario, unidade, data_hora) "
          "VALUES ('%s','pressao',120,80,'mmHg','2026-10-19 08:00+00'); "
          "SELECT valor_secundario FROM indicador;" % A,
          valor="80.00")

    # ---------------- Seguranca por linha (RLS) ----------------
    teste("RLS: usuaria A enxerga so a propria conta",
          "SELECT count(*) FILTER (WHERE usuario_id = '%s') || '/' || count(*) FROM conta;" % A,
          como="app_teste", usuario=A, valor="1/1")
    teste("RLS: usuaria B nao enxerga contas de A",
          "SELECT count(*) FROM conta WHERE usuario_id = '%s';" % A,
          como="app_teste", usuario=B, valor="0")
    teste("RLS: sem usuario definido nao enxerga nada",
          "SELECT count(*) FROM conta;", como="app_teste", valor="0")
    teste("RLS: B nao consegue criar conta em nome de A",
          "INSERT INTO conta (usuario_id, nome, tipo) VALUES ('%s','Invasora','dinheiro');" % A,
          como="app_teste", usuario=B, erro="row-level security")
    teste("RLS: B nao altera dado de A (0 linhas afetadas)",
          "WITH u AS (UPDATE conta SET nome = 'hack' WHERE id = '%s' RETURNING 1) "
          "SELECT count(*) FROM u;" % CONTA_A,
          como="app_teste", usuario=B, valor="0")
    teste("RLS: B nao apaga dado de A (0 linhas afetadas)",
          "WITH d AS (DELETE FROM conta WHERE id = '%s' RETURNING 1) "
          "SELECT count(*) FROM d;" % CONTA_A,
          como="app_teste", usuario=B, valor="0")
    teste("RLS: sessao reaproveitada apos COMMIT (pool de conexoes) nao quebra",
          "SET ROLE app_teste; BEGIN; "
          "SELECT set_config('app.usuario_id', '%s', true); COMMIT; "
          "SELECT count(*) FROM conta;" % A,
          cru=True, valor="0")
    teste("RLS: tabela usuario tambem isola (A nao ve o e-mail de B)",
          "SELECT count(*) FROM usuario;",
          como="app_teste", usuario=A, valor="1")


    # =================================================================
    # ACESSO, MODULOS, PERFIS, GRUPOS, LICENCAS, PAGAMENTOS
    # =================================================================
    H = "h" * 30                      # hash de mentira, so para o teste
    def novo(email="novo@x.com", pais="BR", idioma="NULL"):
        # cria o usuario pela funcao e guarda o id na variavel :id do psql
        return ("SELECT cadastrar_usuario('Novo', '%s', '%s', '%s', %s) AS id \\gset\n"
                % (email, H, pais, idioma))
    ID = ":'id'"

    # ---- Catalogos
    teste("catalogo: 4 idiomas e 7 paises", "SELECT (SELECT count(*) FROM idioma) || '/' || (SELECT count(*) FROM pais);", valor="4/7")
    teste("catalogo: 4 planos; cobranca comeca desligada",
          "SELECT (SELECT count(*) FROM plano) || (SELECT valor FROM configuracao WHERE chave='cobranca_ativa');",
          valor="4false")
    teste("9 modulos e 27 permissoes (processos)",
          "SELECT (SELECT count(*) FROM modulo) || '/' || (SELECT count(*) FROM permissao);", valor="9/27")
    teste("perfil administrador tem as 27 permissoes",
          "SELECT count(*) FROM perfil_permissao pp JOIN perfil p ON p.id=pp.perfil_id WHERE p.codigo='administrador';", valor="27")
    teste("perfil usuario tem 16 permissoes",
          "SELECT count(*) FROM perfil_permissao pp JOIN perfil p ON p.id=pp.perfil_id WHERE p.codigo='usuario';", valor="16")
    teste("perfil leitura tem 5 permissoes",
          "SELECT count(*) FROM perfil_permissao pp JOIN perfil p ON p.id=pp.perfil_id WHERE p.codigo='leitura';", valor="5")

    # ---- Usuario: pais, idioma, e-mail
    teste("usuario com pais inexistente e recusado",
          "INSERT INTO usuario (nome, email, pais) VALUES ('X','x@x.com','ZZ');", erro="foreign key")
    teste("usuario com idioma inexistente e recusado",
          "INSERT INTO usuario (nome, email, idioma) VALUES ('X','x@x.com','xx');", erro="foreign key")
    teste("e-mail em maiusculas e recusado",
          "INSERT INTO usuario (nome, email) VALUES ('X','ANA@X.COM');", erro="ck_usuario_email")
    teste("e-mail sem arroba e recusado",
          "INSERT INTO usuario (nome, email) VALUES ('X','sem-arroba');", erro="ck_usuario_email")

    # ---- Cadastro e login
    teste("cadastro usa os padroes do pais (PT -> pt-PT, EUR)",
          novo(pais="pt") + "SELECT idioma || moeda_padrao FROM usuario WHERE id = %s;" % ID, valor="pt-PTEUR")
    teste("cadastro aceita idioma escolhido diferente do padrao do pais",
          novo(pais="BR", idioma="'en'") + "SELECT pais || idioma FROM usuario WHERE id = %s;" % ID, valor="BRen")
    teste("cadastro grava e-mail em minusculas e sem espacos",
          novo(email=" NOVO@X.COM ") + "SELECT email FROM usuario WHERE id = %s;" % ID, valor="novo@x.com")
    teste("cadastro cria perfil usuario e licenca gratuita",
          novo() + "SELECT (SELECT count(*) FROM usuario_perfil WHERE usuario_id=%s) || (SELECT plano_codigo FROM licenca WHERE usuario_id=%s);" % (ID, ID),
          valor="1gratuito")
    teste("cadastro com e-mail repetido e recusado",
          novo() + "SELECT cadastrar_usuario('Outro','novo@x.com','%s','BR',NULL);" % H, erro="duplicate key")
    teste("cadastro com pais inexistente e recusado",
          "SELECT cadastrar_usuario('N','n@x.com','%s','ZZ',NULL);" % H, erro="pais invalido")
    teste("cadastro com idioma inativo e recusado",
          "UPDATE idioma SET ativo=false WHERE codigo='es'; SELECT cadastrar_usuario('N','n@x.com','%s','MX',NULL);" % H,
          erro="idioma invalido")
    teste("cadastro sem hash de senha e recusado",
          "SELECT cadastrar_usuario('N','n@x.com','curto','BR',NULL);", erro="senha_hash")
    # ---- Dados da pessoa: CPF, telefone, nascimento, endereco
    teste("cpf_valido: validos e invalidos",
          "SELECT concat_ws(',', cpf_valido('52998224725'), cpf_valido('11144477735'), cpf_valido('52998224724'), "
          "cpf_valido('11111111111'), cpf_valido('1234'), cpf_valido(NULL));",
          valor="t,t,f,f,f,f")
    teste("cadastro grava CPF, telefone, nascimento e endereco",
          "SELECT cadastrar_usuario('Cida','cida@x.com','%s','BR',NULL,'52998224725','11987654321','1990-05-17',"
          "'{\"cep\":\"01310100\",\"logradouro\":\"Av. Paulista\",\"numero\":\"1000\",\"cidade\":\"Sao Paulo\",\"uf\":\"sp\"}'::jsonb) AS id \\gset\n" % H +
          "SELECT cpf || '|' || telefone || '|' || data_nascimento || '|' || cep || '|' || logradouro || '|' || uf FROM usuario WHERE id = :'id';",
          valor="52998224725|11987654321|1990-05-17|01310100|Av. Paulista|SP")
    teste("cadastro com CPF invalido e recusado",
          "SELECT cadastrar_usuario('N','n@x.com','%s','BR',NULL,'52998224724');" % H, erro="ck_usuario_cpf")
    teste("CPF repetido entre usuarios ativos e recusado",
          "SELECT cadastrar_usuario('A1','a1@x.com','%s','BR',NULL,'52998224725');" % H +
          "SELECT cadastrar_usuario('A2','a2@x.com','%s','BR',NULL,'52998224725');" % H, erro="ux_usuario_cpf")
    teste("CPF de usuario excluido pode ser reaproveitado",
          "SELECT cadastrar_usuario('A1','a1@x.com','%s','BR',NULL,'52998224725') AS id \\gset\n" % H +
          "UPDATE usuario SET excluido_em = now() WHERE id = :'id';" +
          "SELECT cadastrar_usuario('A2','a2@x.com','%s','BR',NULL,'52998224725') IS NOT NULL;" % H, valor="t")
    teste("telefone com letras ou curto demais e recusado",
          "SELECT cadastrar_usuario('N','n@x.com','%s','BR',NULL,NULL,'12ab');" % H, erro="ck_usuario_telefone")
    teste("nascimento no futuro e recusado",
          "SELECT cadastrar_usuario('N','n@x.com','%s','BR',NULL,NULL,NULL,current_date + 1);" % H, erro="ck_usuario_nascimento")
    teste("CEP invalido e recusado",
          "SELECT cadastrar_usuario('N','n@x.com','%s','BR',NULL,NULL,NULL,NULL,'{\"cep\":\"123\"}'::jsonb);" % H, erro="ck_usuario_cep")
    teste("UF com tres letras e recusada",
          "SELECT cadastrar_usuario('N','n@x.com','%s','BR',NULL,NULL,NULL,NULL,'{\"uf\":\"SPP\"}'::jsonb);" % H, erro="value too long")
    teste("cadastro sem dados pessoais continua valendo (campos opcionais no banco)",
          novo() + "SELECT cpf IS NULL AND telefone IS NULL FROM usuario WHERE id = %s;" % ID, valor="t")

    teste("buscar_login acha pelo e-mail (sem diferenciar maiusculas)",
          novo() + "SELECT length(senha_hash) FROM buscar_login(' NOVO@X.COM ');", valor="30")
    teste("buscar_login de e-mail desconhecido nao devolve nada",
          "SELECT count(*) FROM buscar_login('ninguem@x.com');", valor="0")
    teste("4 erros de senha ainda nao bloqueiam",
          novo() + "SELECT registrar_login(%s, false) FROM generate_series(1,4); "
                   "SELECT bloqueado_ate IS NULL FROM usuario WHERE id=%s;" % (ID, ID), valor="t")
    teste("5 erros de senha bloqueiam a conta por 15 minutos",
          novo() + "SELECT registrar_login(%s, false) FROM generate_series(1,5); "
                   "SELECT bloqueado_ate > now() + interval '14 minutes' FROM usuario WHERE id=%s;" % (ID, ID), valor="t")
    teste("login correto zera as tentativas e libera o bloqueio",
          novo() + "SELECT registrar_login(%s, false) FROM generate_series(1,5); SELECT registrar_login(%s, true); "
                   "SELECT tentativas_login || (bloqueado_ate IS NULL)::text FROM usuario WHERE id=%s;" % (ID, ID, ID),
          valor="0true")

    # ---- Permissoes efetivas
    def perms(extra="", filtro=""):
        return novo() + extra + "SELECT count(*) FROM permissoes_do_usuario(%s) p %s;" % (ID, filtro)
    teste("usuario novo tem 16 permissoes", perms(), valor="16")
    teste("usuario novo pode lancar despesa",
          perms(filtro="WHERE p = 'financas.lancamento.editar'"), valor="1")
    teste("usuario novo NAO pode cadastrar usuarios",
          perms(filtro="WHERE p = 'acesso.usuario.cadastrar'"), valor="0")
    teste("excecao individual nega uma permissao do perfil",
          perms(extra="INSERT INTO usuario_permissao VALUES (%s, 'financas.lancamento.editar', false);\n" % ID), valor="15")
    teste("excecao individual concede permissao fora do perfil",
          perms(extra="INSERT INTO usuario_permissao VALUES (%s, 'idiomas.catalogo.gerenciar', true);\n" % ID), valor="17")
    teste("grupo com perfil administrador da as permissoes de administrador ao membro",
          perms(extra=("INSERT INTO grupo (id, nome) VALUES ('99999999-9999-9999-9999-999999999999','Admins');\n"
                       "INSERT INTO grupo_perfil SELECT '99999999-9999-9999-9999-999999999999', id FROM perfil WHERE codigo='administrador';\n"
                       "INSERT INTO usuario_grupo VALUES (%s, '99999999-9999-9999-9999-999999999999');\n" % ID),
                filtro="WHERE p = 'acesso.usuario.cadastrar'"), valor="1")
    teste("perfil individual e perfil de grupo se somam",
          perms(extra=("INSERT INTO usuario_perfil SELECT %s, id FROM perfil WHERE codigo='administrador';\n" % ID)), valor="27")

    # ---- Liberacao de modulos
    teste("usuario novo abre 6 modulos (uso diario + licencas)",
          novo() + "SELECT count(*) FROM modulos_do_usuario(%s);" % ID, valor="6")
    teste("modulo liberado pelo plano: financas aberto para plano gratuito",
          novo() + "SELECT modulo_liberado(%s, 'financas');" % ID, valor="t")
    teste("bloqueio individual vence a liberacao do plano",
          novo() + "INSERT INTO liberacao_modulo (modulo_codigo, usuario_id, concedida) VALUES ('financas', %s, false);\n"
                   "SELECT modulo_liberado(%s, 'financas')::text || (SELECT count(*) FROM permissoes_do_usuario(%s) p WHERE p LIKE 'financas.%%');"
                   % (ID, ID, ID), valor="false0")
    teste("sem liberacao do plano o modulo fecha",
          novo() + "DELETE FROM liberacao_modulo WHERE plano_codigo='gratuito' AND modulo_codigo='saude';\n"
                   "SELECT modulo_liberado(%s, 'saude');" % ID, valor="f")
    teste("liberacao individual reabre o modulo",
          novo() + "DELETE FROM liberacao_modulo WHERE plano_codigo='gratuito' AND modulo_codigo='saude';\n"
                   "INSERT INTO liberacao_modulo (modulo_codigo, usuario_id) VALUES ('saude', %s);\n"
                   "SELECT modulo_liberado(%s, 'saude');" % (ID, ID), valor="t")
    teste("liberacao por grupo reabre o modulo para o membro",
          novo() + "DELETE FROM liberacao_modulo WHERE plano_codigo='gratuito' AND modulo_codigo='agenda';\n"
                   "INSERT INTO grupo (id, nome) VALUES ('99999999-9999-9999-9999-999999999999','Familia');\n"
                   "INSERT INTO usuario_grupo VALUES (%s, '99999999-9999-9999-9999-999999999999');\n"
                   "INSERT INTO liberacao_modulo (modulo_codigo, grupo_id) VALUES ('agenda','99999999-9999-9999-9999-999999999999');\n"
                   "SELECT modulo_liberado(%s, 'agenda');" % (ID, ID), valor="t")
    teste("liberacao vencida (fim no passado) nao vale",
          novo() + "DELETE FROM liberacao_modulo WHERE plano_codigo='gratuito' AND modulo_codigo='saude';\n"
                   "INSERT INTO liberacao_modulo (modulo_codigo, usuario_id, inicio, fim) "
                   "VALUES ('saude', %s, now() - interval '2 days', now() - interval '1 day');\n"
                   "SELECT modulo_liberado(%s, 'saude');" % (ID, ID), valor="f")
    teste("modulo desativado fecha para todos",
          novo() + "UPDATE modulo SET ativo=false WHERE codigo='financas';\n"
                   "SELECT modulo_liberado(%s, 'financas');" % ID, valor="f")
    teste("liberacao com dois alvos (usuario e grupo) e recusada",
          "INSERT INTO usuario (id, nome, email) VALUES ('77777777-7777-7777-7777-777777777777','Z','z@x.com');\n"
          "INSERT INTO grupo (id, nome) VALUES ('99999999-9999-9999-9999-999999999999','G');\n"
          "INSERT INTO liberacao_modulo (modulo_codigo, usuario_id, grupo_id) "
          "VALUES ('saude','77777777-7777-7777-7777-777777777777','99999999-9999-9999-9999-999999999999');",
          erro="ck_liberacao_alvo")
    teste("liberacao sem nenhum alvo e recusada",
          "INSERT INTO liberacao_modulo (modulo_codigo) VALUES ('saude');", erro="ck_liberacao_alvo")

    # ---- Licenca e cobranca
    def cobranca(on, licenca_sql=""):
        return (novo() + "UPDATE configuracao SET valor='%s' WHERE chave='cobranca_ativa';\n" % ("true" if on else "false")
                + licenca_sql + "SELECT tem_acesso(%s);" % ID)
    lic = "INSERT INTO licenca (usuario_id, plano_codigo, status, origem, inicio, fim) VALUES (%s, '%s', '%s', 'compra', %s, %s);\n"
    teste("cobranca desligada: todos tem acesso", cobranca(False), valor="t")
    teste("cobranca ligada: licenca gratuita nao da acesso", cobranca(True), valor="f")
    teste("cobranca ligada: licenca mensal vigente da acesso",
          cobranca(True, lic % (ID, 'mensal', 'ativa', "now()", "now() + interval '1 month'")), valor="t")
    teste("cobranca ligada: licenca anual vencida nao da acesso",
          cobranca(True, lic % (ID, 'anual', 'ativa', "now() - interval '13 months'", "now() - interval '1 month'")), valor="f")
    teste("cobranca ligada: licenca vitalicia (sem fim) da acesso",
          cobranca(True, lic % (ID, 'vitalicio', 'ativa', "now()", "NULL")), valor="t")
    teste("cobranca ligada: licenca cancelada nao da acesso",
          cobranca(True, lic % (ID, 'vitalicio', 'cancelada', "now()", "NULL")), valor="f")
    teste("licenca com fim antes do inicio e recusada",
          novo() + lic % (ID, 'mensal', 'ativa', "now()", "now() - interval '1 day'"), erro="ck_licenca_fim")
    teste("plano mensal sem duracao e recusado",
          "INSERT INTO plano (codigo, nome, periodo, duracao_meses) VALUES ('x','X','mensal',NULL);", erro="ck_plano_duracao")
    teste("preco do plano precisa ser maior que zero",
          "INSERT INTO plano_preco VALUES ('mensal','BRL',0);", erro="check")

    # ---- Pagamento
    pg = ("INSERT INTO pagamento (usuario_id, plano_codigo, metodo, valor_centavos, moeda%s) "
          "VALUES (%s, 'mensal', '%s', %s, 'BRL'%s);\n")
    teste("pagamento Pix valido e aceito",
          novo() + pg % ("", ID, "pix", 1990, "") + "SELECT 'ok';", valor="ok")
    teste("pagamento com valor zero e recusado",
          novo() + pg % ("", ID, "pix", 0, ""), erro="check")
    teste("final do cartao precisa ter 4 digitos",
          novo() + pg % (", cartao_final", ID, "cartao_credito", 1990, ", 'abcd'"), erro="ck_pagamento_final")
    teste("mesmo pagamento do gateway nao entra duas vezes",
          novo() + pg % (", gateway, id_externo", ID, "pix", 1990, ", 'g', '1'") * 2, erro="duplicate key")
    teste("a tabela de pagamento nao tem coluna para numero de cartao",
          "SELECT count(*) FROM information_schema.columns WHERE table_name='pagamento' AND column_name ~ '(numero|cvv|pan)';",
          valor="0")

    # ---- Seguranca por linha: acesso e licencas
    teste("usuario comum NAO consegue se dar um perfil (RLS)",
          "INSERT INTO usuario_perfil SELECT '%s', id FROM perfil WHERE codigo='administrador';" % A,
          erro="row-level security", como="app_teste", usuario=A)
    teste("modo administrador consegue dar perfil",
          "SELECT set_config('app.admin','on',true);\n"
          "INSERT INTO usuario_perfil SELECT '%s', id FROM perfil WHERE codigo='administrador';\nSELECT 'ok';" % A,
          valor="ok", como="app_teste", usuario=A)
    teste("usuario comum NAO altera catalogo de modulos (RLS)",
          "INSERT INTO modulo (codigo, nome, ordem) VALUES ('novo','Novo',99);",
          erro="row-level security", como="app_teste", usuario=A)
    teste("modo administrador cadastra modulo novo",
          "SELECT set_config('app.admin','on',true);\n"
          "INSERT INTO modulo (codigo, nome, ordem) VALUES ('novo','Novo',99);\nSELECT 'ok';",
          valor="ok", como="app_teste", usuario=A)
    teste("todos leem o catalogo de modulos",
          "SELECT count(*) FROM modulo;", valor="9", como="app_teste", usuario=A)
    teste("A ve so a propria licenca",
          "RESET ROLE;\nINSERT INTO licenca (usuario_id, plano_codigo, origem) VALUES ('%s','gratuito','gratuita'), ('%s','gratuito','gratuita');\n"
          "SET LOCAL ROLE app_teste;\nSELECT count(*) FROM licenca;" % (A, B),
          valor="1", como="app_teste", usuario=A)
    teste("usuario comum NAO consegue trocar o proprio plano (0 linhas)",
          "RESET ROLE;\nINSERT INTO licenca (usuario_id, plano_codigo, origem) VALUES ('%s','gratuito','gratuita');\n"
          "SET LOCAL ROLE app_teste;\nUPDATE licenca SET plano_codigo='vitalicio' WHERE usuario_id='%s';\n"
          "SELECT plano_codigo FROM licenca WHERE usuario_id='%s';" % (A, A, A),
          valor="gratuito", como="app_teste", usuario=A)
    teste("A abre um pagamento pendente para si",
          pg % ("", "'%s'" % A, "pix", 1990, "") + "SELECT 'ok';", valor="ok", como="app_teste", usuario=A)
    teste("A NAO abre pagamento em nome de B (RLS)",
          pg % ("", "'%s'" % B, "pix", 1990, ""), erro="row-level security", como="app_teste", usuario=A)
    teste("A NAO cria pagamento ja aprovado (RLS)",
          pg % (", status", "'%s'" % A, "pix", 1990, ", 'aprovado'"), erro="row-level security", como="app_teste", usuario=A)
    teste("API consulta login mesmo sem usuario definido (funcao protegida)",
          "SELECT count(*) FROM buscar_login('ana@exemplo.com');", valor="1", como="app_teste")
    teste("API cadastra usuario novo sem ser dona das tabelas",
          "SELECT cadastrar_usuario('N','n@x.com','%s','BR',NULL) IS NOT NULL;" % H, valor="t", como="app_teste")
    teste("modo administrador lista todos os usuarios",
          "SELECT set_config('app.admin','on',true);\nSELECT count(*) FROM usuario;", valor="2", como="app_teste", usuario=A)

    # ---------------- Integridade entre usuarios (correcoes da revisao) ----------------
    LANC = ("INSERT INTO lancamento (usuario_id, conta_id, valor, data, descricao, tipo) "
            "VALUES ('%s','%s',10,current_date,'x','despesa');")
    teste("A NAO cria lancamento na conta de B (referencia cruzada)",
          LANC % (A, CONTA_B), erro="outro usuario", como="app_teste", usuario=A)
    teste("A cria lancamento na propria conta",
          LANC % (A, CONTA_A) + "SELECT 'ok';", valor="ok", como="app_teste", usuario=A)
    teste("A NAO cria orcamento com categoria de B",
          "INSERT INTO categoria (id, usuario_id, nome, tipo) VALUES "
          "('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','%s','CatB','despesa');" % B +
          "INSERT INTO orcamento (usuario_id, categoria_id, mes, valor_limite) "
          "VALUES ('%s','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','2026-10-01',100);" % A,
          erro="outro usuario")
    teste("lembrete com alvo inexistente e recusado",
          "INSERT INTO lembrete (usuario_id, alvo_tipo, alvo_id) "
          "VALUES ('%s','evento',gen_random_uuid());" % A, erro="inexistente")
    teste("lembrete para evento de outro usuario e recusado",
          "INSERT INTO evento (id, usuario_id, titulo, inicio) VALUES "
          "('ffffffff-ffff-ffff-ffff-ffffffffffff','%s','Evento B', now());" % B +
          "INSERT INTO lembrete (usuario_id, alvo_tipo, alvo_id) "
          "VALUES ('%s','evento','ffffffff-ffff-ffff-ffff-ffffffffffff');" % A,
          erro="outro usuario")
    teste("lembrete para evento proprio e aceito",
          "INSERT INTO evento (id, usuario_id, titulo, inicio) VALUES "
          "('ffffffff-ffff-ffff-ffff-fffffffffff1','%s','Evento A', now());" % A +
          "INSERT INTO lembrete (usuario_id, alvo_tipo, alvo_id) "
          "VALUES ('%s','evento','ffffffff-ffff-ffff-ffff-fffffffffff1') RETURNING 'ok';" % A,
          valor="ok")
    teste("fuso horario inexistente e recusado",
          "UPDATE usuario SET fuso_horario = 'Marte/Olimpo' WHERE id = '%s';" % A,
          erro="fuso horario invalido")
    teste("moeda fora do catalogo e recusada",
          "UPDATE usuario SET moeda_padrao = 'XXX' WHERE id = '%s';" % A,
          erro="moeda invalida")
    teste("atualizado_em usa a hora real da gravacao, nao o inicio da transacao",
          "SELECT pg_sleep(1.2); "
          "UPDATE conta SET nome = 'Y' WHERE id = '%s'; " % CONTA_A +
          "SELECT atualizado_em > transaction_timestamp() + interval '1 second' "
          "FROM conta WHERE id = '%s';" % CONTA_A, valor="t")

    # ---------------- Resultado ----------------
    falhas = 0
    for nome, ok, detalhe in resultados:
        print(("PASSOU  " if ok else "FALHOU  ") + nome)
        if not ok:
            falhas += 1
            print("        -> " + detalhe)
    print("\n%d testes, %d passaram, %d falharam" % (
        len(resultados), len(resultados) - falhas, falhas))
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
