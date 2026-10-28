# Seminário CI/CD · GitHub Actions + Docker + Traefik

Pipeline que **compila**, **publica** e **implanta** uma aplicação em containers, atualizando
**só o cliente escolhido**, com versionamento SemVer + short hash, proxy reverso com HTTPS,
integração com o Azure Boards e observabilidade.

```
 Dev ── PR (Fixes AB#12) ──► GitHub ──► Azure Boards (item vinculado / fechado no merge)
                               │
                     tag v1.2.0 ou "Run workflow"
                               ▼
              ┌──────────── GitHub Actions ─────────────┐
              │ 1 Build   testes + docker build         │
              │ 2 Push    Docker Hub  user/app:1.2.0-a1b2c3d │
              │ 3 Deploy  SSH → deploy.sh cliente-a 1.2.0-a1b2c3d │
              └─────────────────────────────────────────┘
                               ▼
     EC2 (18.118.57.123)  ┌──────── Traefik :80/:443 (Let's Encrypt) ────────┐
                          │ cliente-a.…  cliente-b.…  logs.…  grafana.…      │
                          └──────┬────────────┬──────────┬────────┬──────────┘
                            cliente-a-app  cliente-b-app  Dozzle  Prometheus/Grafana/cAdvisor
```

## Estrutura

```
.github/
  workflows/ci-cd.yml            Pipeline Build → Push → Deploy
  workflows/pr-azure-boards.yml  Bloqueia PR sem AB#<id>
  pull_request_template.md       Modelo de PR já com "Fixes AB#"
app/                             App Node de exemplo (página, /health, /metrics) + Dockerfile
server/
  setup.sh                       Prepara a EC2 (swap, Docker, usuário deploy, Traefik, Dozzle)
  config.env.example             Configurações que o setup.sh lê
  scripts/deploy.sh              Chamado via SSH: atualiza só o cliente informado (com rollback)
  clientes/docker-compose.yml    Compose de um cliente (cada um vira um projeto separado)
  traefik/                       Proxy reverso
  observabilidade/               Dozzle + (opcional) Prometheus, Grafana, cAdvisor
```

## Requisitos do enunciado → onde estão

| Requisito | Onde |
|---|---|
| Build com GitHub Actions + imagem Docker | job `1 · Build` em `ci-cd.yml`, `app/Dockerfile` |
| Push para registro | job `2 · Push` (Docker Hub) |
| Deploy via SSH só no container do cliente | job `3 · Deploy` + `server/scripts/deploy.sh` |
| Tag SemVer + short hash | passo "Calcular versão": `1.2.0-a1b2c3d` |
| Proxy reverso | `server/traefik/` (Traefik v3 + Let's Encrypt) |
| Integração com Azure DevOps | `AB#<id>` nos PRs + checagem `pr-azure-boards.yml` |
| Container de observabilidade | `server/observabilidade/` (Dozzle; Prometheus/Grafana opcionais) |

---

## Passo a passo

### 1. Docker Hub
1. Crie uma conta em hub.docker.com (uma só para a equipe).
2. **Account settings → Personal access tokens → Generate**, permissão *Read & Write*. Guarde o token.
3. O repositório `seminario-cicd-app` é criado sozinho no primeiro push. Deixe **público**
   (assim o servidor baixa a imagem sem login).

### 2. Repositório no GitHub
1. Crie o repositório e suba estes arquivos na branch `main`.
2. Adicione os 4 integrantes como colaboradores.

### 3. Chave SSH exclusiva do pipeline
Não use a `chaveatt.pem` no GitHub. Gere uma chave só para o deploy, na sua máquina:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github_deploy -N "" -C "github-actions"
cat ~/.ssh/github_deploy.pub    # esta vai no config.env (DEPLOY_PUBKEY)
cat ~/.ssh/github_deploy        # esta vai no secret SSH_PRIVATE_KEY
```

### 4. Preparar o servidor
Da sua máquina (usando o atalho `seminario` do `~/.ssh/config`):

```bash
scp -r server seminario:~/
ssh seminario
cd ~/server
cp config.env.example config.env
nano config.env          # preencha e-mail, usuário do Docker Hub, senhas e DEPLOY_PUBKEY
sudo ./setup.sh
```

Ao final ele mostra os endereços. Teste o usuário do pipeline, da sua máquina:

```bash
ssh -i ~/.ssh/github_deploy deploy@18.118.57.123 "docker ps"
```

### 5. Secrets e variáveis no GitHub
**Settings → Secrets and variables → Actions**

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `SSH_HOST` | `18.118.57.123` |
| Secret | `SSH_USER` | `deploy` |
| Secret | `SSH_PRIVATE_KEY` | conteúdo de `~/.ssh/github_deploy` (inteiro, com BEGIN/END) |
| Secret | `DOCKERHUB_TOKEN` | token do passo 1 |
| Variable | `DOCKERHUB_USERNAME` | seu usuário do Docker Hub |
| Variable | `DEFAULT_CLIENTE` | `cliente-a` (cliente piloto das releases) |

**Settings → Environments**: crie `cliente-a` e `cliente-b`. Em `cliente-b`, marque
*Required reviewers*: o deploy dele passa a pedir aprovação (ótimo para mostrar na apresentação).

### 6. Azure DevOps (Azure Boards)
1. Em dev.azure.com, crie uma organização e um projeto (processo *Agile* ou *Basic*).
2. Crie alguns work items (ex.: "Configurar pipeline", "Adicionar proxy reverso").
3. **Project settings → Boards → GitHub connections → Connect your GitHub account** e
   selecione o repositório. Isso instala o app *Azure Boards* no GitHub.
4. A partir daí:
   - `AB#12` no título/descrição do PR ou na mensagem de commit **vincula** o item;
   - `Fixes AB#12` também **move o item para Done** quando o PR é mergeado na `main`.
5. No GitHub, **Settings → Branches → Add rule** para `main`: exija PR e marque os checks
   `checar-work-item` e `1 · Build`. Assim nenhum código entra sem item vinculado e sem testes passando.

### 7. Primeira release
```bash
git tag v1.0.0
git push origin v1.0.0
```
O pipeline roda Build → Push → Deploy no `cliente-a`. Abra `https://cliente-a.18-118-57-123.sslip.io`.

### 8. Deploy em outro cliente / rollback
**Actions → CI/CD → Run workflow**
- Escolha `cliente-b` e deixe *tag_existente* vazio → build novo e deploy só no B.
- Informe uma tag antiga (ex.: `1.0.0-a1b2c3d`) → só o deploy, sem build (**rollback**).

O `deploy.sh` também faz rollback sozinho se a nova versão não ficar saudável em 60 s.
Histórico em `/opt/seminario/deploys.log`.

### 9. Observabilidade
- **Dozzle** (sempre ligado): `https://logs.<DOMINIO>`, logs de todos os containers em tempo real.
- **Completo** (Prometheus + Grafana + cAdvisor):
  ```bash
  cd /opt/seminario/observabilidade && sudo docker compose --profile completo up -d
  ```
  Grafana em `https://grafana.<DOMINIO>` (usuário `admin`). Consultas úteis no Explore:
  `app_info`, `rate(app_http_requests_total[5m])`, `container_memory_usage_bytes{name=~".*-app"}`,
  `traefik_service_requests_total`.
  Na t3.micro isso aperta a memória; se ficar lento, mude a instância para t3.small.

---

## Roteiro da demonstração (≈10 min)

1. **Azure Boards**: mostrar o item "Mudar cor do cliente A" aberto.
2. Criar branch, alterar algo visível na `app/server.js`, abrir PR **sem** `AB#` → check falha.
   Editar a descrição para `Fixes AB#<id>` → check passa. Merge.
3. Mostrar o item indo para **Done** no Azure Boards.
4. `git tag v1.1.0 && git push origin v1.1.0` → acompanhar os 3 jobs no Actions.
5. Abrir cliente-a (versão nova) e cliente-b (versão antiga, **não foi tocado**).
6. Dozzle: mostrar o container do cliente-a reiniciando e o B intacto.
7. Run workflow → cliente-b → aprovação do Environment → B atualizado.
8. Rollback do cliente-a com *tag_existente* = tag anterior.
9. Grafana: `app_info` mostrando cada cliente em uma versão.

## Divisão da equipe

| Pessoa | Responsabilidade | Na apresentação |
|---|---|---|
| 1 | AWS (EC2, Elastic IP, Security Group), `setup.sh`, Traefik + HTTPS | Arquitetura e proxy reverso |
| 2 | App, Dockerfile, estratégia de tags SemVer + short hash | Build e versionamento |
| 3 | `ci-cd.yml`, secrets, Environments, `deploy.sh` e rollback | Push, deploy por SSH, rollback |
| 4 | Azure Boards, branch protection, Dozzle/Prometheus/Grafana | Integração e observabilidade |

## Problemas comuns

- **Certificado inválido no navegador**: o Let's Encrypt às vezes limita domínios compartilhados
  como o sslip.io. O site continua funcionando (aceite o aviso) ou use um subdomínio grátis do
  DuckDNS e troque o `DOMINIO`. Logs: `docker logs traefik`.
- **`Permission denied (publickey)` no deploy**: a chave pública não está em
  `/home/deploy/.ssh/authorized_keys`, ou o secret foi colado sem as linhas BEGIN/END.
- **`pull access denied`**: o repositório no Docker Hub está privado ou o `DOCKERHUB_USERNAME`
  no `config.env` está diferente do usado no GitHub.
- **404 do Traefik**: o container não está na rede `proxy` ou o host digitado não bate com o
  `DOMINIO`. Veja o painel em `https://traefik.<DOMINIO>`.
- **Adicionar um cliente**: coloque o nome em `CLIENTES` no `config.env`, rode o `setup.sh` de novo,
  e inclua a opção no `ci-cd.yml` (input `cliente`) e no `prometheus.yml`.

## Segurança (vale citar na apresentação)

- O GitHub usa uma chave própria e um usuário `deploy`, não a chave pessoal nem o `ubuntu`.
- Parâmetros do deploy são validados no pipeline **e** no servidor (evita injeção de comando).
- A imagem roda como usuário `node`, não root, e tem `HEALTHCHECK`.
- Painéis protegidos por senha no Traefik; só as portas 22, 80 e 443 ficam abertas.
