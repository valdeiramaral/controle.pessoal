// Le a configuracao do ambiente (.env). Falha cedo, com mensagem clara.
export function lerConfig(env = process.env) {
  const falhas = [];
  if (!env.APP_API_SENHA) falhas.push('APP_API_SENHA');
  if (!env.JWT_SECRET || env.JWT_SECRET.length < 32) {
    falhas.push('JWT_SECRET (minimo 32 caracteres)');
  }
  if (falhas.length) {
    throw new Error(
      'Configuracao invalida. Defina no arquivo .env: ' + falhas.join(', ') +
      '. Rode .\\iniciar.ps1, que acrescenta o JWT_SECRET sozinho.');
  }
  return {
    host: env.API_HOST || '0.0.0.0',
    porta: Number(env.API_PORTA_INTERNA || 3000),
    db: {
      host: env.API_DB_HOST || 'localhost',
      port: Number(env.API_DB_PORTA || env.POSTGRES_PORT || 5432),
      database: env.POSTGRES_DB || 'controle_pessoal',
      user: env.API_DB_USUARIO || 'app_api',
      password: env.APP_API_SENHA,
    },
    jwtSecret: env.JWT_SECRET,
    tokenExpiraSegundos: Number(env.API_TOKEN_EXPIRA_SEG || 3600),
    // Tentativas por minuto e por IP em /login e /cadastro.
    limiteAuth: Number(env.API_LIMITE_AUTH || 20),
  };
}
