import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

const geradorUuid = Uuid();

/// Colunas comuns a todas as tabelas (base da sincronizacao):
/// UUID gerado no aparelho, dono, datas e exclusao logica.
mixin ColunasSync on Table {
  TextColumn get id => text().clientDefault(() => geradorUuid.v4())();
  TextColumn get usuarioId => text().withDefault(const Constant('local'))();
  DateTimeColumn get criadoEm =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get atualizadoEm =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get excluidoEm => dateTime().nullable()();
}

// Valores monetarios em CENTAVOS (inteiro). O servidor usa numeric(14,2);
// a conversao e feita na sincronizacao.
// Enumeracoes sao guardadas como texto (mesmos valores do schema.sql).

@DataClassName('Usuario')
class Usuarios extends Table with ColunasSync {
  TextColumn get nome => text()();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get fusoHorario =>
      text().withDefault(const Constant('America/Sao_Paulo'))();
  TextColumn get moedaPadrao => text().withDefault(const Constant('BRL'))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Conta')
class Contas extends Table with ColunasSync {
  TextColumn get nome => text()();
  TextColumn get tipo => text()(); // corrente | poupanca | dinheiro | cartao
  IntColumn get saldoInicialCentavos => integer().withDefault(const Constant(0))();
  IntColumn get diaFechamento => integer().nullable()();
  IntColumn get diaVencimento => integer().nullable()();
  // Conta bancaria: propria (do usuario) ou externa (de terceiros, so cadastro).
  TextColumn get titularidade => text().withDefault(const Constant('propria'))(); // propria | externa
  TextColumn get banco => text().nullable()(); // codigo do banco (ver core/bancos.dart)
  TextColumn get agencia => text().nullable()();
  TextColumn get numeroConta => text().nullable()();
  TextColumn get documento => text().nullable()(); // CPF/CNPJ do titular, so digitos
  TextColumn get chavePix => text().nullable()();
  TextColumn get apelido => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Categoria')
class Categorias extends Table with ColunasSync {
  TextColumn get nome => text()();
  TextColumn get tipo => text()(); // receita | despesa
  TextColumn get cor => text().nullable()();
  TextColumn get categoriaMaeId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Evento')
class Eventos extends Table with ColunasSync {
  TextColumn get titulo => text()();
  DateTimeColumn get inicio => dateTime()();
  DateTimeColumn get fim => dateTime().nullable()();
  BoolColumn get diaInteiro => boolean().withDefault(const Constant(false))();
  TextColumn get local => text().nullable()();
  TextColumn get tipo => text().withDefault(const Constant('pessoal'))();
  TextColumn get recorrencia => text().nullable()(); // RRULE
  TextColumn get link => text().nullable()();
  TextColumn get notas => text().nullable()();
  TextColumn get origem => text().withDefault(const Constant('local'))();
  TextColumn get idExterno => text().nullable()();
  // Cadastro completo do compromisso (schema v9):
  TextColumn get projeto => text().nullable()();
  TextColumn get prioridade => text().withDefault(const Constant('media'))(); // alta | media | baixa
  TextColumn get participantes => text().nullable()();
  TextColumn get observacoes => text().nullable()();
  TextColumn get comentarios => text().nullable()(); // anotados ao concluir
  TextColumn get tags => text().withDefault(const Constant(''))();
  IntColumn get lembreteMinutos => integer().withDefault(const Constant(30))(); // 0 = sem lembrete
  TextColumn get status => text().withDefault(const Constant('agendado'))(); // agendado | realizado
  DateTimeColumn get concluidoEm => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Tarefa')
class Tarefas extends Table with ColunasSync {
  TextColumn get eventoId => text().nullable()();
  TextColumn get titulo => text()();
  DateTimeColumn get prazo => dateTime().nullable()();
  TextColumn get prioridade => text().withDefault(const Constant('media'))();
  TextColumn get status => text().withDefault(const Constant('aberta'))(); // aberta | concluida
  // Cadastro completo (schema v8):
  TextColumn get descricao => text().nullable()();
  TextColumn get projeto => text().nullable()();
  TextColumn get etapa => text().withDefault(const Constant('a_fazer'))(); // a_fazer | em_andamento | aguardando | concluida
  IntColumn get estimativa => integer().nullable()(); // tempo previsto
  TextColumn get estimativaUnidade => text().withDefault(const Constant('minutos'))(); // minutos | horas | dias
  TextColumn get responsavel => text().nullable()();
  TextColumn get observacoes => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))(); // "casa,urgente"
  TextColumn get comentarios => text().nullable()(); // anotados ao concluir (schema v9)
  DateTimeColumn get concluidoEm => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Ficha de leitura (schema v10): um registro por livro lido.
@DataClassName('Leitura')
class Leituras extends Table with ColunasSync {
  TextColumn get titulo => text()();
  TextColumn get autor => text().nullable()();
  BlobColumn get capa => blob().nullable()(); // foto da capa
  DateTimeColumn get iniciouEm => dateTime().nullable()();
  DateTimeColumn get terminouEm => dateTime().nullable()();
  TextColumn get formato => text().withDefault(const Constant('fisico'))(); // fisico | digital
  // Classificacao dos temas, de 0 a 5.
  IntColumn get notaDrama => integer().withDefault(const Constant(0))();
  IntColumn get notaFantasia => integer().withDefault(const Constant(0))();
  IntColumn get notaRomance => integer().withDefault(const Constant(0))();
  IntColumn get notaReflexao => integer().withDefault(const Constant(0))();
  TextColumn get fraseFavorita => text().nullable()();
  TextColumn get personagens => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Cadastro de obras da biblioteca (schema v11). Campos de lista (tipo, colecao, idioma...) guardam
/// codigo + descricao, como na tela de catalogacao.
@DataClassName('Obra')
class Obras extends Table with ColunasSync {
  IntColumn get tombo => integer()();
  TextColumn get isbn => text().nullable()();
  BoolColumn get noAcervo => boolean().withDefault(const Constant(true))();
  TextColumn get tipoCodigo => text().nullable()();
  TextColumn get tipoDescricao => text().nullable()();
  TextColumn get titulo => text()();
  TextColumn get subtitulo => text().nullable()();
  TextColumn get edicao => text().nullable()();
  TextColumn get referenciaEdicao => text().nullable()();
  IntColumn get ano => integer().nullable()();
  IntColumn get diasPrevisao => integer().nullable()();
  TextColumn get classifTipoCodigo => text().nullable()();
  TextColumn get classifTipoDescricao => text().nullable()();
  TextColumn get codClassificacao => text().nullable()();
  TextColumn get codAutor => text().nullable()();
  TextColumn get tomo => text().nullable()();
  TextColumn get volume => text().nullable()();
  IntColumn get exemplar => integer().withDefault(const Constant(1))();
  TextColumn get faixaEtaria => text().withDefault(const Constant('00-99'))();
  IntColumn get nroPaginas => integer().nullable()();
  TextColumn get serie => text().nullable()();
  TextColumn get colecaoCodigo => text().nullable()();
  TextColumn get colecaoDescricao => text().nullable()();
  TextColumn get idiomaCodigo => text().nullable()();
  TextColumn get idiomaDescricao => text().nullable()();
  TextColumn get editoraCodigo => text().nullable()();
  TextColumn get editoraDescricao => text().nullable()();
  TextColumn get editoraComplemento => text().nullable()();
  TextColumn get categoriaCobrancaCodigo => text().nullable()();
  TextColumn get categoriaCobrancaDescricao => text().nullable()();
  IntColumn get valorCentavos => integer().nullable()();
  TextColumn get localizacaoCodigo => text().nullable()();
  TextColumn get localizacaoDescricao => text().nullable()();
  TextColumn get situacaoCodigo => text().nullable()();
  TextColumn get situacaoDescricao => text().nullable()();
  BlobColumn get capa => blob().nullable()();
  BoolColumn get capaAutoAjuste => boolean().withDefault(const Constant(true))();
  BoolColumn get capaCentralizar => boolean().withDefault(const Constant(true))();
  TextColumn get observacoes => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Cofre de senhas (schema v12). Senhas, segredo e notas ficam CIFRADOS (AES-256-GCM, texto "v1:...");
/// o texto puro nunca e gravado no banco. Veja core/cofre.dart.
@DataClassName('Credencial')
class Credenciais extends Table with ColunasSync {
  TextColumn get titulo => text()();
  TextColumn get tipo => text().withDefault(const Constant('acesso'))(); // acesso | cartao | nota | 2fa | chave
  TextColumn get aplicativo => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get usuario => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get senhaAtual => text().withDefault(const Constant(''))(); // cifrada
  TextColumn get senhaPadrao => text().withDefault(const Constant(''))(); // cifrada
  TextColumn get senhaUltimaValida => text().withDefault(const Constant(''))(); // cifrada
  TextColumn get segredo => text().withDefault(const Constant(''))(); // cifrado: numero do cartao, chave 2FA...
  TextColumn get notas => text().withDefault(const Constant(''))(); // cifradas
  TextColumn get tags => text().withDefault(const Constant(''))();
  BoolColumn get favorito => boolean().withDefault(const Constant(false))();
  BoolColumn get autopreencher => boolean().withDefault(const Constant(true))();
  DateTimeColumn get acessadoEm => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Lancamento')
class Lancamentos extends Table with ColunasSync {
  TextColumn get contaId => text()();
  TextColumn get categoriaId => text().nullable()();
  IntColumn get valorCentavos => integer()();
  DateTimeColumn get dia => dateTime()(); // coluna "data" no servidor
  TextColumn get descricao => text()();
  TextColumn get tipo => text()(); // receita | despesa | transferencia
  TextColumn get status => text().withDefault(const Constant('pendente'))();
  TextColumn get recorrencia => text().nullable()();
  IntColumn get parcelaNumero => integer().nullable()();
  IntColumn get parcelaTotal => integer().nullable()();
  TextColumn get grupoParcelas => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant(''))(); // separadas por virgula
  TextColumn get observacao => text().nullable()();
  // Pagamento (despesa) ou recebimento (receita) registrado:
  DateTimeColumn get dataPagamento => dateTime().nullable()();
  TextColumn get formaPagamento => text().nullable()(); // ver core/pagamento.dart
  TextColumn get contaPagamentoId => text().nullable()(); // conta/banco de onde saiu ou entrou o dinheiro
  TextColumn get tipoPagamento => text().nullable()(); // total | parcial
  IntColumn get valorPagoCentavos => integer().nullable()();
  IntColumn get descontoCentavos => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Arquivo anexado a um lancamento (comprovante, cupom...). O conteudo fica no proprio banco local.
@DataClassName('Anexo')
class Anexos extends Table with ColunasSync {
  TextColumn get lancamentoId => text()();
  TextColumn get nomeArquivo => text()();
  TextColumn get tipoMime => text().nullable()();
  IntColumn get tamanhoBytes => integer()();
  BlobColumn get dados => blob()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Orcamento')
class Orcamentos extends Table with ColunasSync {
  TextColumn get categoriaId => text()();
  DateTimeColumn get mes => dateTime()(); // sempre dia 1
  IntColumn get valorLimiteCentavos => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Meta')
class Metas extends Table with ColunasSync {
  TextColumn get contaId => text().nullable()();
  TextColumn get nome => text()();
  IntColumn get valorAlvoCentavos => integer()();
  DateTimeColumn get prazo => dateTime().nullable()();
  IntColumn get valorAcumuladoCentavos => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Consulta')
class Consultas extends Table with ColunasSync {
  TextColumn get eventoId => text().nullable()();
  TextColumn get lancamentoId => text().nullable()();
  TextColumn get medico => text()();
  TextColumn get especialidade => text().nullable()();
  TextColumn get local => text().nullable()();
  DateTimeColumn get dataHora => dateTime()();
  TextColumn get preparo => text().nullable()();
  TextColumn get resultado => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Medicamento')
class Medicamentos extends Table with ColunasSync {
  TextColumn get nome => text()();
  TextColumn get dose => text()();
  TextColumn get horarios => text()(); // "08:00,20:00"
  DateTimeColumn get inicio => dateTime()();
  DateTimeColumn get fim => dateTime().nullable()();
  IntColumn get estoque => integer().nullable()();
  IntColumn get estoqueMinimo => integer().nullable()();
  // Posologia e controle (schema v5):
  TextColumn get formato => text().withDefault(const Constant('comprimido'))(); // ver core/saude_calculo.dart
  TextColumn get tratamento => text().nullable()(); // para que serve (ex.: Colesterol alto)
  TextColumn get instrucoes => text().nullable()();
  IntColumn get quantidade => integer().withDefault(const Constant(1))(); // unidades por tomada
  TextColumn get frequencia => text().withDefault(const Constant('diaria'))(); // diaria | dias_semana | intervalo | necessario
  TextColumn get diasSemana => text().withDefault(const Constant(''))(); // "1,3,5" (1 = segunda)
  IntColumn get intervaloDias => integer().withDefault(const Constant(1))();
  BoolColumn get ativo => boolean().withDefault(const Constant(true))(); // false = "nao estou tomando"
  BoolColumn get lembreteReabastecer => boolean().withDefault(const Constant(true))();
  // Identificacao (schema v6):
  TextColumn get tipoMedicamento => text().nullable()(); // referencia | generico | similar (classificacao da Anvisa)
  TextColumn get fabricante => text().nullable()(); // fabricante/laboratorio
  DateTimeColumn get validade => dateTime().nullable()();
  TextColumn get posologia => text().nullable()(); // como a receita manda tomar (texto livre)
  TextColumn get informacoes => text().nullable()(); // breve informacao sobre o medicamento
  // Periodo de uso (schema v7): a data final (fim) e calculada a partir daqui.
  TextColumn get periodoUso => text().withDefault(const Constant('continuo'))(); // continuo | diario | semanal | mensal
  IntColumn get duracaoUso => integer().nullable()(); // quantos dias/semanas/meses (nao continuo)
  @override
  Set<Column> get primaryKey => {id};
}

/// Consulta, exame, retorno ou vacina agendados (unicos ou em serie periodica).
@DataClassName('AgendamentoSaude')
class AgendamentosSaude extends Table with ColunasSync {
  TextColumn get tipo => text()(); // consulta | exame | retorno | vacina | outro
  TextColumn get titulo => text()(); // especialidade/motivo ou nome do exame
  TextColumn get profissional => text().nullable()();
  TextColumn get especialidade => text().nullable()();
  TextColumn get local => text().nullable()();
  DateTimeColumn get dataHora => dateTime()();
  TextColumn get preparo => text().nullable()(); // jejum, documentos...
  TextColumn get observacao => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('agendado'))(); // agendado | realizado | cancelado | faltou
  TextColumn get resultado => text().nullable()();
  IntColumn get lembreteMin => integer().nullable()(); // antecedencia do lembrete; null = sem
  TextColumn get eventoId => text().nullable()(); // compromisso espelhado na Agenda
  TextColumn get grupoSerie => text().nullable()();
  IntColumn get serieNumero => integer().nullable()();
  IntColumn get serieTotal => integer().nullable()();
  TextColumn get repeticao => text().nullable()(); // "meses:3"
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RegistroTomada')
class RegistrosTomada extends Table with ColunasSync {
  TextColumn get medicamentoId => text()();
  DateTimeColumn get horarioPrevisto => dateTime()();
  TextColumn get status => text().withDefault(const Constant('pendente'))(); // tomou | pulou | atrasou | pendente
  DateTimeColumn get horarioReal => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Indicador')
class Indicadores extends Table with ColunasSync {
  TextColumn get tipo => text()(); // peso | pressao | glicemia | sono | agua | passos | frequencia_cardiaca
  RealColumn get valor => real()();
  RealColumn get valorSecundario => real().nullable()();
  TextColumn get unidade => text()();
  DateTimeColumn get dataHora => dateTime()();
  TextColumn get origem => text().withDefault(const Constant('manual'))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Documento')
class Documentos extends Table with ColunasSync {
  TextColumn get consultaId => text().nullable()();
  TextColumn get lancamentoId => text().nullable()();
  TextColumn get arquivoCaminho => text()(); // caminho local; URL apos sincronizar
  TextColumn get nomeArquivo => text()();
  TextColumn get tipo => text()(); // exame | receita | laudo | nota
  DateTimeColumn get dia => dateTime().clientDefault(() => DateTime.now())();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Lembrete')
class Lembretes extends Table with ColunasSync {
  TextColumn get alvoTipo => text()(); // evento | consulta | medicamento | lancamento | tarefa
  TextColumn get alvoId => text()();
  IntColumn get antecedenciaMin => integer().withDefault(const Constant(0))();
  TextColumn get canal => text().withDefault(const Constant('local'))();
  @override
  Set<Column> get primaryKey => {id};
}
