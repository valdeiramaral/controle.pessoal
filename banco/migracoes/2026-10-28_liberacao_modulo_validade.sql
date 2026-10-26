-- Liberacao de modulos para varios usuarios, com validade (inicio/fim) ou vitalicia, e desativavel.
-- Substitui o "dono" do modulo (modulo.dono_id) por liberacoes por usuario. PowerShell:
--   Get-Content banco/migracoes/2026-10-28_liberacao_modulo_validade.sql -Raw | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
SET search_path TO controle, public;

ALTER TABLE liberacao_modulo ADD COLUMN IF NOT EXISTS ativa boolean NOT NULL DEFAULT true;
ALTER TABLE liberacao_modulo ADD COLUMN IF NOT EXISTS vitalicio boolean NOT NULL DEFAULT true;
-- Liberacoes antigas com as duas datas passam a ter validade; com so uma data, viram vitalicias.
UPDATE liberacao_modulo SET vitalicio = false WHERE inicio IS NOT NULL AND fim IS NOT NULL AND vitalicio;
UPDATE liberacao_modulo SET inicio = NULL, fim = NULL WHERE vitalicio AND (inicio IS NOT NULL OR fim IS NOT NULL);
ALTER TABLE liberacao_modulo DROP CONSTRAINT IF EXISTS ck_liberacao_validade;
ALTER TABLE liberacao_modulo ADD CONSTRAINT ck_liberacao_validade CHECK (vitalicio OR (inicio IS NOT NULL AND fim IS NOT NULL));

-- O dono de um modulo vira uma liberacao vitalicia para ele.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'controle' AND table_name = 'modulo' AND column_name = 'dono_id') THEN
    INSERT INTO liberacao_modulo (modulo_codigo, usuario_id)
      SELECT m.codigo, m.dono_id FROM modulo m
       WHERE m.dono_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM liberacao_modulo l WHERE l.modulo_codigo = m.codigo AND l.usuario_id = m.dono_id);
    ALTER TABLE modulo DROP COLUMN dono_id;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_liberacao_usuario ON liberacao_modulo (modulo_codigo, usuario_id) WHERE usuario_id IS NOT NULL;

CREATE OR REPLACE FUNCTION modulo_liberado(u uuid, m text) RETURNS boolean
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
                AND EXISTS (SELECT 1 FROM alvo WHERE concedida) ) )
$$;
