-- Dados bancarios na conta (cadastro de contas bancarias). Seguro rodar mais de uma vez.
SET search_path TO controle, public;

ALTER TABLE conta ADD COLUMN IF NOT EXISTS titularidade text NOT NULL DEFAULT 'propria';
ALTER TABLE conta ADD COLUMN IF NOT EXISTS banco        text;
ALTER TABLE conta ADD COLUMN IF NOT EXISTS agencia      text;
ALTER TABLE conta ADD COLUMN IF NOT EXISTS numero_conta text;
ALTER TABLE conta ADD COLUMN IF NOT EXISTS documento    text;
ALTER TABLE conta ADD COLUMN IF NOT EXISTS chave_pix    text;
ALTER TABLE conta ADD COLUMN IF NOT EXISTS apelido      text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_conta_titularidade') THEN
    ALTER TABLE conta ADD CONSTRAINT ck_conta_titularidade CHECK (titularidade IN ('propria', 'externa'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_conta_documento') THEN
    ALTER TABLE conta ADD CONSTRAINT ck_conta_documento
      CHECK (documento IS NULL OR documento ~ '^[0-9]{11}$|^[0-9]{14}$');
  END IF;
END $$;
