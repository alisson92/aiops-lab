# CLAUDE.md — aiops-lab

> Instruções operacionais para o Claude Code neste repositório.
> Fonte de verdade do projeto: `README.md`. Este arquivo é o complemento operacional.

---

## 1. O que é este projeto

Bake-off técnico de três ferramentas AIOps open-source (**Keep**, **HolmesGPT**, **K8sGPT**)
sobre Kubernetes, com o objetivo de produzir uma recomendação de adoção fundamentada
em evidência, demonstrável ao time técnico e defensável como ADR.

- Validação: cluster Kind local (WSL2)
- Alvo de implementação: Amazon EKS, via Helm
- Público: time técnico + cliente do setor financeiro

---

## 2. Gates eliminatórios — checklist obrigatório antes de qualquer proposta

Antes de propor ou gerar qualquer artefato (YAML, chart, script), valide mentalmente:

- [ ] **Helm-deployável** — sub-chart namespaced; sem recursos fora do namespace sem aviso explícito
- [ ] **100% local** — sem egress em runtime; imagens e pesos pré-baixados; Ollama configurado para não puxar da internet em execução
- [ ] **CPU-only** — nunca presumir GPU; nenhuma flag CUDA, nenhuma nodeSelector de GPU
- [ ] **Custo zero** — sem SaaS, sem API paga, sem tier pago

Qualquer violação deve ser sinalizada com:
> ⚠️ **GATE VIOLADO — [nome do gate]:** [descrição do problema e alternativa]

---

## 3. Tier A vs Tier B

| Tier | Tipo de recurso | Aprovação necessária |
|---|---|---|
| **A** | Namespaced: `Deployment`, `Service`, `ConfigMap`, `Secret`, `PVC`, `ServiceAccount`, `Role`, `RoleBinding` | GMUD padrão (pipeline executa após aprovação) |
| **B** | Cluster-scoped: `ClusterRole`, `ClusterRoleBinding`, `CRD`, `PersistentVolume`, `StorageClass` | Aprovação explícita do cliente + GMUD |

**Regra:** sempre comece pelo modo Tier A (namespaced). Se uma ferramenta exigir Tier B,
sinalize antes de propor qualquer deploy:

> 🔒 **Tier B detectado:** este chart requer `[recurso cluster-scoped]`. É necessário
> aprovação do cliente antes de prosseguir. Proposta: empacotar como bundle no umbrella
> chart para aprovação única.

---

## 4. Contexto de produção (EKS)

- **Namespace:** o time de sustentação opera exclusivamente dentro do namespace isolado do projeto
- **Deploy em prod:** sempre via pipeline; requer GMUD aprovada previamente
- **Comando base:** `helm install <release> <repo>/<chart> --version <x.y.z> --namespace <ns> --values <values-file>`
- **Versão sempre pinada:** nunca `latest` em imagens nem versão sem `--version` no Helm
- **StorageClass:** usar `<EKS_STORAGECLASS_NAME>` como placeholder nos values de prod
  (confirmar nome real com o time de infra antes do deploy em EKS)

### Fluxo de alertas em produção

```
Prometheus (coleta métricas)
    ↓
Grafana Alerting (avalia regras — regras criadas diretamente no Grafana)
    ↓
Contact Points / webhooks configurados no Grafana
    ↓
Keep (hub de alertas) → Teams (canal oficial, webhook configurado)
```

- **Alertmanager não é utilizado** neste cliente
- As regras de alerta vivem no Grafana (futuramente migradas para IaC/Terraform)
- No lab: reproduzir via `values.yaml` do kube-prometheus-stack (`grafana.alerting`)
- A URL do webhook do Teams é uma variável gerenciada centralmente (ver §7)

---

## 5. Ordem de construção (respeitar sempre)

```
1. Cluster Kind
2. kube-prometheus-stack  (pré-requisito: sem isso não há métricas nem alertas)
3. Ollama                 (dependência compartilhada de LLM — Fase 0 inclui matriz de modelos)
4. Workload-vítima        (gerador de falhas controláveis)
5. Candidatos AIOps       (K8sGPT → HolmesGPT → Keep, isolados primeiro)
```

Nunca pular ou inverter camadas. Nunca instalar um candidato AIOps sem as camadas 1–4 prontas.

---

## 6. Estrutura de diretórios do repositório

```
aiops-lab/
├── charts/                     # charts Helm locais (você é o autor)
│   ├── k8sgpt-config/          # CR K8sGPT — wrapper para o CRD do operator
│   │   ├── Chart.yaml
│   │   └── templates/
│   └── workload-vitima/        # Deployment de teste para injeção de falhas
│       ├── Chart.yaml
│       └── templates/
├── values/                     # overrides de charts upstream (um arquivo por release)
│   ├── kube-prometheus-stack.yaml
│   ├── ollama.yaml
│   ├── keep-lab.yaml
│   ├── k8sgpt.yaml
│   └── holmesgpt.yaml
├── config/                     # configurações de runtime (não são templates Helm)
│   └── keep/
│       └── workflows/
│           └── ollama-grafana-alert-enrichment.yaml
├── env/                        # valores por ambiente (local.yaml / prod.yaml)
├── helmfile.yaml               # orquestra todos os releases
├── scenarios/                  # scripts de injeção de falha por cenário
├── scripts/                    # automações operacionais (bootstrap, port-forward, etc.)
├── results/                    # evidências do bake-off (ADR, scoring, demos)
├── README.md
└── CLAUDE.md
```

**Regra:** cada componente usa o chart **oficial upstream** (`helm repo add` + `helm install`).
Nunca modificar templates do chart — apenas sobrescrever via `values/`.

---

## 7. Gestão de valores compartilhados (helmfile.yaml)

Valores que são consumidos por múltiplos charts (endpoint do Ollama, namespace, URL do Teams,
StorageClass) são definidos **uma única vez** no `helmfile.yaml` e injetados em cada release.

Princípio: alterar em um lugar → reflete em todos os charts dependentes.

Exemplo de estrutura do `helmfile.yaml`:
```yaml
# Valores globais compartilhados entre todos os releases
environments:
  local:
    values:
      - env/local.yaml    # namespace, storageClass: standard, ollamaEndpoint, etc.
  prod:
    values:
      - env/prod.yaml     # namespace, storageClass: <EKS_STORAGECLASS_NAME>, etc.

releases:
  - name: kube-prometheus-stack
    ...
  - name: ollama
    ...
  - name: keep
    ...
```

Antes de hardcodar qualquer valor em `values.yaml`, perguntar: "isso é compartilhado por
mais de um chart?" Se sim, vai para o `helmfile.yaml`.

---

## 8. Convenções obrigatórias

### Helm
- Versão sempre pinada (`--version x.y.z`)
- Apenas chart oficial + `values.yaml` customizado; nunca fork de chart
- `--dry-run` antes de qualquer install/upgrade; só executa com OK explícito do usuário
- Nunca hardcode: StorageClass, tipo de Service, namespace, endpoints — tudo parametrizado

### Kubernetes
- `runAsNonRoot: true` sempre que o chart permitir
- `resources.requests` e `resources.limits` definidos em todo workload
- `readinessProbe` obrigatória em serviços com tráfego
- Imagens sem tag `latest`; digest ou tag semântica
- RBAC com least privilege; escopar ao namespace

### Ferramentas AIOps
- **Read-only first**: iniciar todas as ferramentas em modo leitura antes de habilitar ações
- Testar modo Tier A (namespaced) antes de considerar qualquer Operator (Tier B)

### Git
- Conventional Commits em todas as mensagens
- Nunca commitar valores sensíveis (URLs de webhook, secrets)

### Paridade local × produção
Sempre sinalizar divergências:
> ⚠️ **Kind vs EKS:** [descrição do que funciona localmente mas pode divergir em produção]

---

## 9. Fontes autorizadas

Usar **exclusivamente** fontes oficiais:

| Ferramenta | Repositório | Helm chart |
|---|---|---|
| Keep | github.com/keephq/keep | keephq/keep |
| HolmesGPT | github.com/robusta-dev/holmesgpt | robusta-dev/holmesgpt |
| K8sGPT | github.com/k8sgpt-ai/k8sgpt | k8sgpt-ai/k8sgpt |
| Ollama | github.com/ollama/ollama | ollama/ollama |
| kube-prometheus-stack | github.com/prometheus-community/helm-charts | prometheus-community/kube-prometheus-stack |

Toda decisão de configuração deve ser rastreável à documentação oficial da ferramenta.
Nunca adaptar de tutoriais não-oficiais sem validar contra a doc oficial.

---

## 10. Candidatos de modelo LLM (Fase 0 — matriz)

Lista inicial para benchmark CPU-only. Todos open-source, zero custo, sem egress em runtime.

| Modelo | Tamanho | RAM estimada (q4) | Perfil |
|---|---|---|---|
| `gemma2:2b` | 2B | ~1.6 GB | Mínimo viável; baseline de qualidade |
| `phi3:mini` | 3.8B | ~2.3 GB | Otimizado para raciocínio; forte candidato |
| `phi3.5:3.8b` | 3.8B | ~2.2 GB | Evolução do phi3:mini (tag correta no Ollama; `phi3.5:mini` não existe) |
| `llama3.2:3b` | 3B | ~2.0 GB | Meta; boa relação qualidade/tamanho |
| `qwen2.5:3b` | 3B | ~1.9 GB | Alibaba; bom em instruções técnicas |
| `mistral:7b-instruct-q4_K_M` | 7B (q4) | ~4.4 GB | Teto de qualidade CPU-viável; latência maior (tag correta no Ollama; `mistral:7b-q4_K_M` não existe) |

**Critérios de corte:** modelos acima de 7B ou que exijam >8 GB de RAM são descartados
(inviável em inferência CPU-only com footprint aceitável).

A Fase 0 mede, para cada modelo: latência por consulta · qualidade do RCA · RAM em uso · CPU peak.
Resultado legítimo possível: "nenhum modelo atinge qualidade mínima sob os gates".

---

## 11. Catálogo de cenários de falha

Aplicados à workload-vítima (Deployment trivial), não ao Camunda.

| # | Cenário | Como provocar | Sintoma esperado |
|---|---|---|---|
| 1 | CrashLoopBackOff | Processo sai com código de erro | Restarts crescentes |
| 2 | OOMKilled | Limite de memória baixo + carga | OOMKill + restart |
| 3 | ImagePullBackOff | Tag de imagem inexistente | Pod não inicia |
| 4 | Readiness failing | Readiness probe quebrada | Pod `Running` mas não `Ready` |

Scripts de injeção ficam em `scenarios/`. Cada script é idempotente e tem um comando
de reversão documentado.

---

## 12. Escopo — dentro e fora

### Dentro
- Avaliação das três ferramentas sob os quatro gates
- Inferência local (Ollama), CPU-only
- Deploy via Helm, namespaced (Tier A) como caminho-base
- Cenários genéricos de falha de Kubernetes (§11)
- Matriz de modelos LLM CPU-viáveis (Fase 0)

### Fora (por ora)
- Camunda — entra depois, como camada aditiva de alert rules
- Correlação por IA paga do Keep
- GPU
- Operators como caminho-base (Tier B)
- Ações automatizadas de escrita pelo HolmesGPT na fase inicial (read-only first)
