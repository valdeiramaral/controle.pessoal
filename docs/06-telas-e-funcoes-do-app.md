# Telas e funções do app

| Área (`app/lib/features`) | Função |
|---|---|
| `auth` | Login (abas Entrar / Criar conta), cadastro completo, sessão segura, "lembrar e-mail" |
| `nav` | Casca com menu lateral recolhível, ícones coloridos, barra de página com nome/e-mail/Sair (`acoes_usuario.dart`) |
| `hoje` | Tela inicial em abas, filtros de período, indicadores (KPIs) |
| `financas` | Contas, categorias, lançamentos, saldos |
| `saude` | Medicamentos, consultas, indicadores, documentos |
| `agenda` | Eventos, tarefas, lembretes |
| `aparencia` | Claro/Escuro/Sistema, tamanho da letra, cor do sistema |
| `admin` | Usuários, perfis, grupos, permissões, planos, cadastro de módulos (pacote, liberação por usuário, validade/vitalício, ícones com busca) |
| `modulos` | Menu dinâmico a partir de `/meus-modulos` |

Testes em `app/test/` (19 arquivos). Execução: `testar.bat`.
