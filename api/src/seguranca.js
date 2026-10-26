import { hash, verify, Algorithm } from '@node-rs/argon2';
import { SignJWT, jwtVerify } from 'jose';

// Argon2id com os parametros minimos recomendados pela OWASP (19 MiB, 2 passes).
const OPCOES = { algorithm: Algorithm.Argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 };
const EMISSOR = 'controle-pessoal';

export const gerarHash = (senha) => hash(senha, OPCOES);

export async function conferirSenha(hashSalvo, senha) {
  try { return await verify(hashSalvo, senha); } catch { return false; }
}

// Hash descartavel: conferido quando o e-mail nao existe, para o tempo de
// resposta nao revelar se a conta existe.
let falso;
export function hashFalso() {
  falso ??= gerarHash('senha-que-ninguem-usa-' + Math.random());
  return falso;
}

const chave = (config) => new TextEncoder().encode(config.jwtSecret);

export async function emitirToken(config, usuarioId) {
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(usuarioId)
    .setIssuer(EMISSOR)
    .setIssuedAt()
    .setExpirationTime(`${config.tokenExpiraSegundos}s`)
    .sign(chave(config));
}

/** Devolve o id do usuario do token, ou lanca erro se for invalido ou expirado. */
export async function lerToken(config, token) {
  const { payload } = await jwtVerify(token, chave(config), {
    issuer: EMISSOR,
    algorithms: ['HS256'],
  });
  if (!payload.sub) throw new Error('token sem usuario');
  return payload.sub;
}
