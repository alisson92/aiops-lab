# CLAUDE.md — aiops-lab

> Instruções operacionais para o Claude Code neste repositório.
> Fonte de verdade do projeto: `README.md`. Este arquivo é o complemento operacional.

---

## 1. O que é este projeto

Lab de validação do **Keep** como plataforma central de alertas AIOps, integrado com:
- **kube-prometheus-stack** — coleta de métricas e disparo de alertas
- **Ollama** — inferência LLM local (CPU-only, offline) para enriquecimento com RCA

Objetivo: demonstrar o fluxo `Grafana Alerting → Keep → Ollama → alerta enriquecido com RCA`
funcionando em Kubernetes local (Kind/WSL2), replicável em EKS.

- Validação: cluster Kind local (WSL2)
- Alvo de implementação: Amazon EKS, via Helm
- Público: time técnico + cliente do setor financeiro

---

## 2. Gates eliminatórios — checklist obrigatório antes de qualquer proposta

Antes de propor ou gerar qualquer artefato (YAML, values, script), valide mentalmente:

- [ ] **Helm-deployável** — apenas charts oficiais upstream; sem charts customizados
- [ ] **100% local** — sem egress em runtime; modelos Ollama pré-carregados
- [ ] **CPU-only** — nunca presumir GPU; nenhuma flag CUDA
- [ ] **Custo zero** — sem SaaS, sem API paga

Qualquer violação deve ser sinalizada com:
> ⚠️ **GATE VIOLADO — [nome do gate]:** [descrição e alternativa]

---

## 3. Tier A vs Tier B

| Tier | Tipo de recurso | Aprovação necessária |
|---|---|---|
| **A** | Namespaced: `Deployment`, `Service`, `ConfigMap`, `Secret`, `PVC`, `ServiceAccount`, `Role`, `RoleBinding` | GMUD padrão |
| **B** | Cluster-scoped: `ClusterRole`, `ClusterRoleBinding`, `CRD`, `PersistentVolume`, `StorageClass` | Aprovação explícita do cliente + GMUD |

Regra: sempre começar pelo Tier A. Se algo exigir Tier B, sinalizar antes de propor.

---

## 4. Contexto de produção (EKS)

- **Namespace:** `aiops-lab` (local e prod)
- **Deploy em prod:** sempre via pipeline; requer GMUD aprovada
- **Versão sempre pinada:** nunca `latest` em imagens nem versão sem `--version` no Helm
- **StorageClass:** usar `<EKS_STORAGECLASS_NAME>` como placeholder nos values de prod

### Fluxo de alertas

```
Prometheus (coleta métricas)
    ↓
Grafana Alerting (avalia regras)
    ↓
Keep (hub de alertas) → workflow de enriquecimento → Ollama (RCA)
    ↓
Teams (canal oficial, webhook configurado)
```

- **Alertmanager não é utilizado** neste cliente
- As regras de alerta vivem no Grafana

---

## 5. Ordem de construção (respeitar sempre)

```
1. Cluster Kind                  (kind-config.yaml)
2. kube-prometheus-stack         (pré-requisito: métricas e alertas)
3. Ollama                        (inferência LLM — modelos pré-carregados)
4. Keep                          (plataforma de alertas)
5. kubectl apply -f manifests/   (RBAC do Keep + workload-vítima)
6. bash scripts/keep-bootstrap.sh (providers Ollama/K8s + workflow)
```

---

## 6. Estrutura de diretórios

```
aiops-lab/
├── helmfile.yaml          # orquestra os 3 releases
├── env/
│   ├── local.yaml         # namespace, storageClass, etc.
│   └── prod.yaml
├── values/                # overrides dos charts upstream (um arquivo por release)
│   ├── kube-prometheus-stack.yaml
│   ├── ollama.yaml
│   └── keep.yaml
├── manifests/             # recursos Kubernetes aplicados via kubectl (não Helm)
│   ├── keep-rbac.yaml     # Role + RoleBinding para o backend do Keep (Tier A)
│   └── workload-vitima.yaml  # Deployment nginx para injeção de falhas
├── workflows/             # YAMLs de workflow importados no Keep via bootstrap
│   └── grafana-rca.yaml   # Grafana → Keep → Ollama (enriquecimento com RCA)
├── scenarios/             # scripts de injeção de falha (idempotentes, com --revert)
│   ├── 01-crashloopbackoff.sh
│   ├── 02-oomkilled.sh
│   ├── 03-imagepullbackoff.sh
│   └── 04-readiness-failing.sh
└── scripts/
    ├── keep-bootstrap.sh  # registra providers e importa workflow no Keep
    ├── port-forward.sh    # sobe port-forwards para acesso local
    ├── wait-ready.sh      # aguarda pods ficarem Ready
    └── check-updates.sh   # verifica novas versões dos charts
```

**Regra:** nenhum chart customizado. Toda customização via `values/`. Os `manifests/` são
recursos simples que não justificam um chart (RBAC + workload de teste).

---

## 7. Gestão de valores compartilhados

Valores consumidos por múltiplos componentes (namespace, ollamaEndpoint, storageClass)
são definidos **uma única vez** em `env/local.yaml` e injetados via `helmfile.yaml`.

---

## 8. Convenções obrigatórias

### Helm
- Versão sempre pinada (`version: x.y.z` no helmfile)
- Apenas chart oficial + `values/` customizado; nunca fork de chart
- `helmfile diff` antes de qualquer sync em prod

### Kubernetes
- `runAsNonRoot: true` sempre que o chart permitir
- `resources.requests` e `resources.limits` definidos em todo workload
- `readinessProbe` obrigatória em serviços com tráfego
- Imagens sem tag `latest`
- RBAC com least privilege, escopo ao namespace

### Git
- Conventional Commits em todas as mensagens
- Nunca commitar valores sensíveis (webhook URLs, secrets)

### Paridade local × produção
Sempre sinalizar divergências:
> ⚠️ **Kind vs EKS:** [o que funciona localmente mas pode divergir em prod]

---

## 9. Fontes autorizadas

| Ferramenta | Repositório | Helm chart |
|---|---|---|
| Keep | github.com/keephq/keep | keephq/keep |
| Ollama | github.com/ollama/ollama | ollama-helm/ollama |
| kube-prometheus-stack | github.com/prometheus-community/helm-charts | prometheus-community/kube-prometheus-stack |

Toda decisão de configuração deve ser rastreável à documentação oficial.

---

## 10. Modelos LLM disponíveis no Ollama (CPU-only)

O workflow usa `gemma2:2b` por padrão — menor footprint, já carregado.

| Modelo | RAM (q4) | Status |
|---|---|---|
| `gemma2:2b` | ~1.6 GB | padrão — usar este |
| `phi3.5:3.8b` | ~2.2 GB | disponível, mas troca de modelo gera latência |
| `llama3.2:3b` | ~2.0 GB | disponível |
| `mistral:7b-instruct-q4_K_M` | ~4.4 GB | disponível, lento |

**Regra:** manter consistência — usar o mesmo modelo em todos os componentes para evitar
troca de modelo no Ollama (que descarrega/carrega e causa latência ou 500 sob carga).

---

## 11. Cenários de falha (workload-vítima)

| # | Cenário | Script |
|---|---|---|
| 1 | CrashLoopBackOff | `scenarios/01-crashloopbackoff.sh` |
| 2 | OOMKilled | `scenarios/02-oomkilled.sh` |
| 3 | ImagePullBackOff | `scenarios/03-imagepullbackoff.sh` |
| 4 | Readiness failing | `scenarios/04-readiness-failing.sh` |

Cada script é idempotente e aceita `--revert` para desfazer a falha.
