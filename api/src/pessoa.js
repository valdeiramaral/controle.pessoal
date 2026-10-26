// Dados da pessoa (CPF, telefone, nascimento, endereco): normalizacao e validacao.
// A API tira mascaras ("123.456.789-09" vira "12345678909") e devolve so digitos.
// O banco confere tudo de novo (constraints ck_usuario_*): esta camada existe para
// dar mensagens claras ao app.

export const apenasDigitos = (s) => String(s ?? '').replace(/\D/g, '');

/** CPF com 11 digitos, digitos verificadores corretos e sem sequencia repetida. */
export function cpfValido(c) {
  if (!/^\d{11}$/.test(c) || /^(\d)\1{10}$/.test(c)) return false;
  const dv = (n) => {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(c[i]) * (n + 1 - i);
    const r = (s * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return dv(9) === Number(c[9]) && dv(10) === Number(c[10]);
}

const UFS = new Set(('AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO').split(' '));

export const CAMPOS_ENDERECO = {
  cep: 8, logradouro: 120, numero: 20, complemento: 60, bairro: 60, cidade: 80, uf: 2,
};

class ErroDado extends Error {
  constructor(campo, detalhe) { super(detalhe); this.campo = campo; this.detalhe = detalhe; }
}

function dataValida(texto) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(texto)) return false;
  const d = new Date(`${texto}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== texto) return false;
  return texto >= '1900-01-01' && d.getTime() <= Date.now();
}

const vazio = (v) => v === undefined || v === null || (typeof v === 'string' && v.trim() === '');

/**
 * Converte o corpo da requisicao em colunas da tabela usuario.
 * So devolve as colunas cujos campos vieram no corpo (campo vazio vira null).
 * Lanca ErroDado (campo, detalhe) quando algo e invalido.
 */
export function colunasDaPessoa(corpo) {
  const col = {};
  if ('nome' in corpo) {
    const nome = String(corpo.nome ?? '').trim();
    if (!nome) throw new ErroDado('nome', 'Informe o nome.');
    col.nome = nome;
  }
  if ('cpf' in corpo) {
    if (vazio(corpo.cpf)) col.cpf = null;
    else {
      const cpf = apenasDigitos(corpo.cpf);
      if (!cpfValido(cpf)) throw new ErroDado('cpf', 'CPF inválido.');
      col.cpf = cpf;
    }
  }
  if ('telefone' in corpo) {
    if (vazio(corpo.telefone)) col.telefone = null;
    else {
      const t = apenasDigitos(corpo.telefone);
      if (t.length < 10 || t.length > 13) throw new ErroDado('telefone', 'Telefone inválido. Use DDD + número.');
      col.telefone = t;
    }
  }
  if ('nascimento' in corpo) {
    if (vazio(corpo.nascimento)) col.data_nascimento = null;
    else {
      if (!dataValida(corpo.nascimento)) throw new ErroDado('nascimento', 'Data de nascimento inválida.');
      col.data_nascimento = corpo.nascimento;
    }
  }
  if (corpo.endereco && typeof corpo.endereco === 'object') {
    for (const [campo, max] of Object.entries(CAMPOS_ENDERECO)) {
      if (!(campo in corpo.endereco)) continue;
      const bruto = corpo.endereco[campo];
      if (vazio(bruto)) { col[campo] = null; continue; }
      let v = String(bruto).trim();
      if (campo === 'cep') {
        v = apenasDigitos(v);
        if (v.length !== 8) throw new ErroDado('cep', 'CEP inválido.');
      } else if (campo === 'uf') {
        v = v.toUpperCase();
        if (!UFS.has(v)) throw new ErroDado('uf', 'UF inválida.');
      } else if (v.length > max) {
        throw new ErroDado(campo, `Texto muito longo (máximo ${max}).`);
      }
      col[campo] = v;
    }
  }
  return col;
}

/** Endereco para a funcao cadastrar_usuario (jsonb). */
export function enderecoJson(col) {
  const e = {};
  for (const campo of Object.keys(CAMPOS_ENDERECO)) if (col[campo]) e[campo] = col[campo];
  return Object.keys(e).length ? e : null;
}

export const COLUNAS_USUARIO = `id, nome, email, pais, idioma, fuso_horario, moeda_padrao, email_verificado_em,
  ativo, cpf, telefone, data_nascimento::text AS nascimento,
  cep, logradouro, numero, complemento, bairro, cidade, uf`;

/** Linha da tabela usuario -> JSON da API (endereco aninhado). */
export function serializarUsuario(r) {
  if (!r) return r;
  const { cep, logradouro, numero, complemento, bairro, cidade, uf, ...resto } = r;
  return { ...resto, endereco: { cep, logradouro, numero, complemento, bairro, cidade, uf } };
}

export { ErroDado };

/** Monta "col1 = $2, col2 = $3" e os valores, a partir de nomes de coluna FIXOS (nunca texto do usuario). */
export function montarSet(col, primeiroParametro = 2) {
  const nomes = Object.keys(col);
  return {
    sql: nomes.map((n, i) => `${n} = $${primeiroParametro + i}`).join(', '),
    valores: nomes.map((n) => col[n]),
    vazio: nomes.length === 0,
  };
}

// Pedacos de JSON Schema (Fastify) reaproveitados pelas rotas.
export const esquemaEndereco = {
  type: 'object',
  additionalProperties: false,
  properties: Object.fromEntries(
    Object.keys(CAMPOS_ENDERECO).map((c) => [c, { type: ['string', 'null'], maxLength: 200 }])),
};
export const esquemaDadosPessoais = {
  cpf: { type: 'string', maxLength: 20 },
  telefone: { type: 'string', maxLength: 30 },
  nascimento: { type: ['string', 'null'], maxLength: 10 },
  endereco: esquemaEndereco,
};
