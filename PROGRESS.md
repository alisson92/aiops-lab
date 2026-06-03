# Progresso do Bake-off — aiops-lab

> Fonte de verdade do andamento do projeto. Atualizar a cada etapa concluída.
> Última atualização: 2026-06-03

---

## Estado atual: Fase 0 concluída → Fase 1 HolmesGPT em seguida

---

## Infraestrutura base (Camadas 1–4) ✅

| Camada | Componente | Versão | Status |
|---|---|---|---|
| 1 | Cluster Kind `aiops-lab` | kind v0.30.0 / k8s v1.34.0 | ✅ Running |
| 2 | kube-prometheus-stack | chart 86.1.0 / app v0.91.0 | ✅ Running |
| 3 | Ollama (limit 7 GiB) | chart 1.57.0 / app 0.24.0 | ✅ Running |
| 4 | workload-vítima | nginx-unprivileged:1.27 | ✅ Running |
| — | Alert rules Grafana (4 cenários) | — | ✅ Provisionadas |

**Modelos no PVC do Ollama:** gemma2:2b · phi3:mini · phi3.5:3.8b · llama3.2:3b · qwen2.5:3b · mistral:7b-instruct-q4_K_M

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

**Modelos que avançam para Fase 1:** `gemma2:2b` · `phi3.5:3.8b` · `qwen2.5:3b` · `mistral:7b-instruct-q4_K_M`

---

## Fase 1 — K8sGPT (isolado) ✅ CONCLUÍDA

**Versão:** k8sgpt-operator chart 0.2.27 / k8sgpt v0.4.33 | **Modelo:** gemma2:2b

| Cenário | Detectado? | Causa correta? | Latência | Score LLM |
|---|:---:|:---:|---|---|
| 1 — CrashLoopBackOff | ✅ | ⚠️ Parcial | ~2–3 min | Genérico; não identificou `exit 1` |
| 2 — OOMKilled | ✅ | ✅ | ~1 min | Bom; sugeriu aumentar limits |
| 3 — ImagePullBackOff | ✅ | ✅ | ~1 min | Melhor resultado; erro exato incluído |
| 4 — Readiness failing | ✅ | ❌ | ~1–2 min | Detectou 404; atribuiu a "network issue" |

> Resultados detalhados: `results/scoring-matrix.md`

**Lições aprendidas:**
- K8sGPT v0.3.26 incompatível com operator v0.2.27 (gRPC `ServerAnalyzerService` só existe no v0.4.x)
- `spec.version` obrigatório no CR — sem ele, operator oscila entre tags e cria cycling infinito de ReplicaSets

---

## Fase 1 — HolmesGPT (isolado) ⏳ PRÓXIMO

- Chart: `robusta/holmes` v0.31.1
- Abordagem: read-only first, Ollama como LLM provider
- Executar os 4 cenários de falha com os 4 modelos aprovados na Fase 0

---

## Fase 1 — Keep (isolado) 🕐 Aguardando

- Chart: `keephq/keep` v0.1.96
- Configurar contact point Grafana → webhook Keep
- Avaliar ingestão, dedup, correlação e roteamento de alertas

---

## Fases seguintes

| Fase | Descrição | Status |
|---|---|---|
| Fase 2 | Combinações: Keep+K8sGPT, Keep+HolmesGPT | 🕐 |
| Fase 3 | Tríade integrada (Keep+K8sGPT+HolmesGPT) | 🕐 |
| Fase 4 | Pontuação final, recomendação, ADR, demo | 🕐 |

---

## Decisões técnicas registradas

| Decisão | Motivo |
|---|---|
| Ollama limit: 7 GiB (era 5 GiB) | Go runtime retém ~3.5 GB base pós-unload; mistral:7b exige ~6.5 GB total |
| K8sGPT v0.4.33 (não v0.3.26) | Compatibilidade gRPC com operator v0.2.27 |
| `nginx-unprivileged` na workload-vítima | nginx padrão roda como root — incompatível com `runAsNonRoot: true` |
| Tags LLM corrigidas vs CLAUDE.md original | `phi3.5:mini` → `phi3.5:3.8b`; `mistral:7b-q4_K_M` → `mistral:7b-instruct-q4_K_M` |
| Cenário 02 sem `polinux/stress` | Binário ausente na imagem; substituído por loop de shell puro |
