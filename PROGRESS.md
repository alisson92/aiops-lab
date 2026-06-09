# Progresso do Bake-off — aiops-lab

> Fonte de verdade do andamento do projeto. Atualizar a cada etapa concluída.
> Última atualização: 2026-06-09

---

## Estado atual: Bake-off concluído · ADR redigida · Roteiro de demo criado · Lab reprodutível validado em WSL2 e Debian

---

## Infraestrutura base (Camadas 1–4) ✅

| Camada | Componente | Versão | Status |
|---|---|---|---|
| 1 | Cluster Kind `aiops-lab` | kind v0.30.0 / k8s v1.34.0 | ✅ Running |
| 2 | kube-prometheus-stack | chart 86.1.0 / app v0.91.0 | ✅ Running |
| 3 | Ollama (limit 7 GiB) | chart 1.57.0 / app 0.24.0 | ✅ Running |
| 4 | workload-vítima | nginx-unprivileged:1.27 | ✅ Running |
| 5 | Keep | chart keephq/keep v0.1.96 | ✅ Running |
| — | Alert rules Grafana (4 cenários) | — | ✅ Provisionadas via values.yaml |
| — | Contact point Keep + notification policy | — | ✅ Provisionados via values.yaml |

**Modelos no PVC do Ollama:** gemma2:2b · phi3:mini · phi3.5:3.8b · llama3.2:3b · qwen2.5:3b · mistral:7b-instruct-q4_K_M

**K8sGPT:** operator v0.2.27 / app v0.4.33 · escalado a 1 réplica · CR `k8sgpt-lab` ativo

---

## Fase 0 — Benchmark de modelos LLM ✅ CONCLUÍDA

Cenário fixo: OOMKilled | Ferramenta de referência: K8sGPT v0.4.33

| Modelo | Latência | RAM pico | RCA (1–5) | Veredicto |
|---|---|---|:---:|---|
| `gemma2:2b` | ~60s | ~4.9 GB | 3 | ✅ Avança |
| `phi3:mini` | 176s | ~4.9 GB | 2 | ❌ Eliminado — latência > 120s |
| `phi3.5:3.8b` | 36s | ~5.1 GB | 3 | ✅ Avança |
| `llama3.2:3b` | 17s | ~5.1 GB | 2 | ❌ Eliminado — confundiu OOMKilled com scheduling |
| `qwen2.5:3b` | 85s | ~3.1 GB | 3 | ✅ Avança |
| `mistral:7b-instruct-q4_K_M` | 84s | ~6.5 GB | 4 | ✅ Avança |

**Modelos aprovados para Fase 1:** `gemma2:2b` · `phi3.5:3.8b` · `qwen2.5:3b` · `mistral:7b-instruct-q4_K_M`

---

## Fase 1 — K8sGPT (isolado) ✅ CONCLUÍDA

**Versão:** k8sgpt-operator chart 0.2.27 / k8sgpt v0.4.33 | **Modelo:** gemma2:2b | **Score ponderado: 3.1 / 5**

| Cenário | Causa correta? | Latência | Destaque |
|---|:---:|---|---|
| 1 — CrashLoopBackOff | ⚠️ Parcial | ~24s | "last termination reason is Error" — sem exit code |
| 2 — OOMKilled | ✅ | ~49s | Causa correta; kubectl top sugerido |
| 3 — ImagePullBackOff | ✅ | ~29s | **Tag exata incluída no diagnóstico** — melhor resultado |
| 4 — Readiness failing | ❌ | ~49s | Detectou 404; atribuiu a "network issue" (falso diagnóstico) |

**Lições aprendidas:**
- K8sGPT v0.3.26 incompatível com operator v0.2.27 (gRPC mismatch) — usar v0.4.33
- `spec.version` obrigatório no CR — sem ele, operator oscila em loop de ReplicaSets

---

## Fase 1 — HolmesGPT (isolado) ❌ ELIMINADO

**Chart:** robusta/holmes v0.31.1 | **Motivo da eliminação:** inviável estruturalmente em CPU-only

Tool-calling incompatível com todos os modelos testados via Ollama:
- gemma2:2b, phi3.5:3.8b, mistral:7b → erro "does not support tools"
- qwen2.5:3b → entra em loop (resposta vazia)
- llama3.2:3b → ignora tools, gera texto genérico

Mesmo com modelo compatível: 3–6 rodadas de inferência por investigação × 2–3 min/rodada em CPU = **10–20 min por incidente**. Inviável operacionalmente.

HolmesGPT foi projetado para LLMs hospedados (GPT-4, Claude) — o gate CPU-only elimina a ferramenta estruturalmente.

---

## Fase 1 — Keep (isolado) ✅ CONCLUÍDA

**Chart:** keephq/keep v0.1.96 | **Modelo:** gemma2:2b | **Score ponderado: 3.5 / 5**

**Pipeline validado:** Prometheus → Grafana Alerting → Keep (webhook) → workflow Ollama → ai_rca persistido no alerta

| Cenário | Causa correta? | Latência (total) | ai_rca gerado? |
|---|:---:|---|:---:|
| 1 — CrashLoopBackOff | ⚠️ Parcial | ~33s | ✅ |
| 2 — OOMKilled | ✅ | ~4m26s | ✅ |
| 3 — ImagePullBackOff | ✅ | ~4m22s | ✅ |
| 4 — Readiness Failing | ⚠️ Parcial | ~4m16s | ✅ |

**Componentes configurados:**
- Helm release `keep` REVISION 2, namespace `aiops-lab`
- Grafana contact point `Keep` (webhook Bearer, provisionado via `contactpoints.yaml`)
- Notification policy → receiver `Keep` (provisionado via `policies.yaml`)
- Ollama provider `ollama-local` (id dinâmico, host interno do cluster)
- Workflow `ollama-grafana-alert-enrichment` — trigger: `type: alert, source: grafana`

**Bugs encontrados e contornados:**
- Provider Ollama perde estado em restarts do backend → reinstalar via API após cada reinício
- Contact point criado via API é apagado no upgrade do Grafana → movido para provisioning em `values.yaml`
- Query PromQL da regra Readiness nunca disparava: (a) `AND` sem `on()` fazia vector matching falhar; (b) `== 0` é falsy para o Grafana → corrigido para `1 - metric`

---

## Fase 2 — Keep + K8sGPT em conjunto ✅ CONCLUÍDA

**Papéis complementares identificados — sem sobreposição:**

| Dimensão | K8sGPT | Keep |
|---|---|---|
| Velocidade de detecção | ✅ **24–49s** (vencedor) | ⚠️ 33s–4m+ |
| Contexto k8s no RCA | ✅ API direta (tag, reason, exit code) | ⚠️ Só payload Grafana |
| Gestão de alertas | ❌ Só CR | ✅ Dedup, fingerprint, histórico |
| Notificação Teams | ❌ | ✅ Contact point nativo |
| Tier de deploy | ❌ Tier B | ✅ Tier A |

**Lacuna:** K8sGPT não tem como enviar findings ao Keep nativamente (sink: Slack/Mattermost/CloudEvents; Keep sem receiver CloudEvents). Integração plena exigiria adapter externo.

---

## Fase 3 — Tríade integrada ⏭️ PULADA

HolmesGPT foi eliminado na Fase 1. Tríade inviável. Registrada como N/A no ADR.

---

## Fase 4 — Recomendação + ADR ✅ CONCLUÍDA

**Decisão:** Keep como plataforma AIOps central + K8sGPT complementar (condicional a aprovação Tier B)

**ADR:** `results/ADR-001-aiops-platform.md`
**Scoring completo:** `results/scoring-matrix.md`

---

## Reprodutibilidade ✅ CONCLUÍDA

Fluxo `make check → make setup → make pf` validado em dois ambientes:
- WSL2 (Ubuntu/Debian sobre Windows)
- VM Debian nativa (4 vCPUs, 11 GB RAM, 16 GB disco)

Ferramentas verificadas automaticamente: docker, kind, kubectl, helm, helmfile, make, python3, curl, pkill, git, k9s.
Requisitos mínimos documentados com base em medição real do cluster.

---

## Decisões técnicas registradas

| Decisão | Motivo |
|---|---|
| Ollama limit: 7 GiB (era 5 GiB) | Go runtime retém ~3.5 GB base pós-unload; mistral:7b exige ~6.5 GB total |
| K8sGPT v0.4.33 (não v0.3.26) | Compatibilidade gRPC com operator v0.2.27 |
| `nginx-unprivileged` na workload-vítima | nginx padrão roda como root — incompatível com `runAsNonRoot: true` |
| Tags LLM corrigidas vs CLAUDE.md original | `phi3.5:mini` → `phi3.5:3.8b`; `mistral:7b-q4_K_M` → `mistral:7b-instruct-q4_K_M` |
| Cenário 02 sem `polinux/stress` | Binário ausente na imagem; substituído por loop de shell puro |
| Keep backend memory: 512Mi → 1Gi | OOMKill do próprio backend durante processamento de workflows |
| Contact point movido para provisioning (values.yaml) | Configuração via API é apagada em upgrades do Grafana |
| Query Readiness: `1 - metric` em vez de `metric == 0` | Grafana Unified Alerting trata valor 0 como falsy — regra nunca disparava |
| Cluster `camunda-platform-local` parado (docker stop) | Dois clusters Kind simultâneos consomem ~4 GiB extras — causava OOM durante inferência |
