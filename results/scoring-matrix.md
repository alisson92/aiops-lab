# Matriz de Pontuação — AIOps Bake-off

> Preencher após a Fase 1 (isolado). Pontuação: 1–5 por critério × peso.
> Gates são pass/fail: reprovado em qualquer gate = não entra na pontuação.

---

## Gates eliminatórios

| Gate | Keep | K8sGPT | HolmesGPT |
|---|:---:|:---:|:---:|
| Helm-deployável (chart oficial) | ✅ | ✅ | ✅ |
| 100% local (sem egress em runtime) | ✅ | ✅ | ✅ |
| CPU-only (sem GPU) | ✅ | ✅ | ⚠️ Passa¹ |
| Custo zero (sem SaaS / API paga) | ✅ | ✅ | ✅ |
| **Resultado** | **✅ Avança** | **✅ Avança** | **❌ Inviável operacionalmente** |

> ¹ HolmesGPT não exige GPU, mas seu modelo agentico de tool-calling requer múltiplas rodadas de inferência (~3–6 por cenário). Em CPU com modelos ≤7B, cada rodada leva 2–3 min → 10–20 min por investigação. Inviável operacionalmente mesmo que tecnicamente dentro do gate de hardware.
> ² Keep (cenário 1): RCA marcado como "parcial" porque o prompt do workflow recebe apenas os campos do payload Grafana (name, description, severity) — sem dados de `kubectl describe pod`. O LLM não tem acesso direto à causa raiz real (exit code, OOM, etc.). Em produção, o workflow pode ser estendido com um step `kubectl` via provider para enriquecer o contexto antes do LLM.
> ³ Keep (cenário 4): Mesma limitação do cenário 1 — probe path incorreto (/healthz-broken) não é visível no payload Grafana; LLM só sabe que "a probe está falhando" e sugere `kubectl describe`. Correto mas superficial.

---

## Pontuação (só quem passou nos gates)

> Escala: 1–5 por critério. Peso: Alto = 3 · Médio-alto = 2 · Médio = 2.
> Total ponderado = média ponderada (1–5). Fórmula: Σ(score × peso) / Σ(pesos) — pesos somam 27.

| Bloco | Critério | Peso | Keep | K8sGPT | HolmesGPT |
|---|---|:---:|:---:|:---:|:---:|
| **Eficácia técnica** | Qualidade do RCA | Alto | 3 | 3 | N/A |
| | Cobertura (% cenários úteis) | Médio | 4 | 3 | N/A |
| | Tempo até diagnóstico útil | Médio | 3 | 4 | N/A |
| | Redução de ruído (dedup/correlação) | Médio | 4 | 3 | N/A |
| | Falso-positivo / alucinação | **Alto** | 4 | 3 | N/A |
| **Aptidão operacional** | Esforço de setup e day-2 | **Alto** | 2 | 3 | N/A |
| | Autonomia de deploy (Tier A vs B) | **Alto** | 5 | 2 | N/A |
| | Footprint (requests/limits) | Médio-alto | 2 | 4 | N/A |
| | Segurança e auditabilidade | **Alto** | 4 | 4 | N/A |
| | Maturidade / risco de roadmap | Médio | 2 | 4 | N/A |
| | Ajuste ao stack atual | Médio | 5 | 2 | N/A |
| **Total ponderado** | | | **3.5 / 5** | **3.1 / 5** | **Eliminado** |

### Justificativas por critério

**Qualidade do RCA (Keep 3 · K8sGPT 3)**
Keep: 2 cenários corretos (OOMKill, ImagePull), 2 parciais (CrashLoop, Readiness) — limitado ao payload Grafana sem acesso direto ao k8s.
K8sGPT: 2 corretos (OOMKill, ImagePull), 1 parcial (CrashLoop), 1 errado (Readiness: atribuiu 404 a "network issue" em vez de path da probe). Ambos empata em 3.

**Cobertura (Keep 4 · K8sGPT 3)**
Keep recebeu e processou os 4 cenários; todos geraram ai_rca. K8sGPT detectou 3/4 com diagnóstico útil; cenário 4 errou a causa raiz.

**Tempo até diagnóstico (Keep 3 · K8sGPT 4)**
Keep depende do `for:` do Grafana (~1-2 min) + LLM (~10-20s) = ~2-2.5 min total. K8sGPT tem polling próprio e entrega mais rápido (~1-2 min sem depender de alertas).

**Redução de ruído (Keep 4 · K8sGPT 3)**
Keep tem fingerprinting nativo: mesmo alerta que dispara múltiplas vezes é agrupado; workflow só roda uma vez por fingerprint único. K8sGPT lista issues sem deduplicação explícita entre ciclos.

**Falso-positivo / alucinação (Keep 4 · K8sGPT 3)**
Keep: LLM não inventou causas — saídas genéricas quando sem contexto, mas não contraditórias. K8sGPT: cenário 4 produziu diagnóstico factualmente errado ("network issue"), que poderia levar SRE ao caminho errado.

**Esforço de setup e day-2 (Keep 2 · K8sGPT 3)**
Keep requer: 4 componentes Helm, contact point Grafana (bug: precisou mover para provisioning), Ollama provider (perdido em restart — bug), workflow YAML, notification policy. Mais movendo partes que qualquer outra ferramenta testada.
K8sGPT: 1 chart + 1 CR (K8sGPTAnalyze). Tive um problema de versão gRPC no início mas day-2 é simples.

**Autonomia de deploy / Tier A vs B (Keep 5 · K8sGPT 2)**
Keep: 100% Tier A — Deployment, Service, PVC, ServiceAccount, todos namespaced. Sem CRD, sem ClusterRole.
K8sGPT: Operator requer CRD + ClusterRole (Tier B) — exige aprovação explícita do cliente antes do deploy.

**Footprint (Keep 2 · K8sGPT 4)**
Keep: 4 deployments totalizando ~2 GiB de RAM em limits (backend 1Gi + MySQL 512Mi + frontend 512Mi + websocket 128Mi).
K8sGPT: 1 pod leve (~256Mi RAM). Footprint muito menor.

**Segurança e auditabilidade (Keep 4 · K8sGPT 4)**
Keep: trilha completa de workflow runs com logs, alertas enriquecidos auditáveis via API/UI. Sem acesso ao k8s API (não precisa de RBAC).
K8sGPT: acesso read-only ao k8s API via RBAC mínimo; output estruturado no CR status. Ambos pontuam igual.

**Maturidade (Keep 2 · K8sGPT 4)**
K8sGPT: projeto CNCF Sandbox, bem estabelecido, documentação sólida.
Keep: projeto mais jovem, bugs encontrados em campo (estado inconsistente do provider, provisioning de contact points), comunidade menor.

**Ajuste ao stack atual (Keep 5 · K8sGPT 2)**
Keep se encaixa diretamente no fluxo já existente: Prometheus → Grafana Alerting → Keep (webhook) → Teams. É exatamente o elo que falta no stack do cliente.
K8sGPT opera como ferramenta paralela de diagnóstico, sem integração com o fluxo de alertas Grafana→Teams. Seria uma camada adicional desconectada.

---

## Evidências por cenário

### Cenário 1 — CrashLoopBackOff
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | Alerta recebido via Grafana webhook + ai_rca gerado pelo LLM (gemma2:2b): root_cause + immediate_action + prevention | ⚠️ Parcial² | ~2 min (Prometheus→Grafana→Keep) + ~14s LLM | Fluxo end-to-end funcional; contexto do alerta limitado (prompt recebe apenas name/description/severity do alerta Grafana, sem kubectl describe); RCA genérico quando sem contexto real do pod |
| K8sGPT | `the last termination reason is Error container=app pod=workload-vitima-796ccdcb97-wn9nf` + sugestões genéricas (checar logs, imagem, rede) | ⚠️ Parcial | ~2–3 min pós-injeção | Detectou a falha; LLM não identificou `exit 1` como causa raiz; sugestões superficiais |
| HolmesGPT | N/A — inviável | ❌ | N/A | Tool calling incompatível: gemma2:2b, phi3.5:3.8b, mistral:7b não suportam tools no Ollama; qwen2.5:3b entra em loop (resposta vazia); llama3.2:3b ignora tools. Cada rodada de inferência leva 2–3 min em CPU. |

### Cenário 2 — OOMKilled
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | OOMKilled detectado via Grafana webhook; ai_rca gerado automaticamente (trigger: alert): "container terminated due to OOM Killer" + `kubectl top pods` + ajuste de limits | ✅ Sim | ~2 min (Prometheus→Grafana→Keep) + ~10s LLM | Trigger automático funcionou end-to-end; LLM identificou OOMKilled corretamente a partir do nome do alerta; ação imediata pertinente |
| K8sGPT | `the last termination reason is OOMKilled container=app` + sugestão de aumentar limits.memory, revisar código para memory leaks | ✅ Sim | ~1 min pós-injeção | Causa corretamente nomeada (OOMKilled); soluções pertinentes; não identifica loop de shell como causa específica, mas isso é esperado |
| HolmesGPT | N/A — inviável | ❌ | N/A | Mesma limitação estrutural do cenário 1. |

### Cenário 3 — ImagePullBackOff
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | ImagePullBackOff detectado via Grafana webhook; ai_rca: "failing to pull image because of invalid image name, tag or registry credentials" + inspeção da configuração da imagem | ✅ Sim | ~2 min (Prometheus→Grafana→Keep) + ~19s LLM | Trigger automático; causa raiz corretamente identificada; ação imediata pertinente (verificar nome/tag/registry) |
| K8sGPT | `rpc error: failed to pull "nginx:this-tag-does-not-exist-99999": not found` + sugestão de verificar tag e typo | ✅ Sim | ~1 min pós-injeção | Erro completo incluído; causa exata nomeada; soluções pertinentes (verificar tag, registry); melhor resposta entre os cenários |
| HolmesGPT | N/A — inviável | ❌ | N/A | Mesma limitação estrutural do cenário 1. |

### Cenário 4 — Readiness failing
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | Readiness Failing detectado via Grafana webhook; ai_rca: "readiness probe is failing for more than 2 minutes" + `kubectl describe pod workload-vitima -n aiops-lab` + revisar configuração da probe | ⚠️ Parcial³ | ~2 min (Grafana for:2m + webhook) + ~20s LLM | Trigger automático funcionou; causa correta (probe falhando); sem diagnóstico específico do path/código HTTP (não acessa k8s diretamente) |
| K8sGPT | `Readiness probe failed: HTTP probe failed with statuscode: 404` + diagnóstico de problema de rede/service | ❌ Não | ~1–2 min pós-injeção | Detectou o 404 corretamente; LLM errou a causa raiz (atribuiu a "network issue" em vez de path da probe incorreto) |
| HolmesGPT | N/A — inviável | ❌ | N/A | Mesma limitação estrutural do cenário 1. |

---

## Fase 1 — Keep: conclusão e achados técnicos

> **Veredicto: viável. Recomendado como hub de alertas com AI enrichment para o stack do cliente.**

**Pontos fortes:**
- Único candidato 100% Tier A — deploy sem aprovação adicional além da GMUD padrão
- Integração nativa com o fluxo Grafana→Webhook→Teams que o cliente já usa
- AI enrichment funcional com 1 chamada LLM por alerta (~10-20s em CPU com gemma2:2b)
- Fingerprinting e deduplicação de alertas out-of-the-box
- Trilha de auditoria completa (workflow runs, logs, alertas enriquecidos)

**Limitações observadas:**
- Setup mais complexo que os demais: 4 componentes Helm + configuração de contact point + workflow + provider Ollama
- Provider Ollama perde estado em restarts do backend (bug de persistência na versão 0.1.96) — mitigado movendo contact point para provisioning via values.yaml
- LLM recebe apenas o payload do alerta Grafana (name/description/severity) — sem acesso direto ao k8s API. RCA é mais genérico em cenários onde o contexto do pod seria determinante
- Projeto mais jovem (maturidade 2/5): bugs de edge case encontrados em campo

**Recomendação para produção:**
Estender o workflow com um step de provider `kubernetes` antes do LLM — coletar `kubectl describe pod` e injetar no prompt. Isso eliminaria a limitação de contexto e elevaria a qualidade do RCA para todos os cenários.

---

## Fase 1 — K8sGPT: conclusão e achados técnicos

> **Veredicto: viável como ferramenta de diagnóstico standalone, com restrição de Tier B.**

**Pontos fortes:**
- Diagnóstico direto via k8s API: coleta dados reais do pod antes de chamar o LLM — contexto mais rico
- Footprint mínimo (1 pod, ~256Mi RAM)
- Projeto maduro (CNCF Sandbox), documentação sólida
- Setup simples em day-2: 1 CR controla tudo

**Limitações observadas:**
- Requer CRD + ClusterRole (Tier B) → aprovação explícita do cliente obrigatória antes do deploy
- Não integra com o fluxo Grafana→Teams; opera como camada paralela e desconectada
- Cenário 4 (Readiness): alucinação parcial — detectou o 404 mas atribuiu a "network issue" em vez de path da probe. Risco de falso diagnóstico para SRE
- Modelo polling independente: não reage a alertas em tempo real, roda em ciclos

**Decisões técnicas relevantes:**
- K8sGPT v0.3.26 é incompatível com operator v0.2.27 (gRPC mismatch) — usar v0.4.33
- `spec.version` no K8sGPTAnalyze CR é obrigatório (sem ele, operator oscila em loop de update)

---

## Fase 1 — HolmesGPT: conclusão e achados técnicos

> **Veredicto: inviável no ambiente CPU-only deste lab.**

### Achados de compatibilidade de tool calling (Ollama)

| Modelo | Suporta tools? | Comportamento observado |
|---|:---:|---|
| `gemma2:2b` | ❌ | Erro imediato: "does not support tools" |
| `phi3.5:3.8b` | ❌ | Erro imediato: "does not support tools" |
| `mistral:7b-instruct-q4_K_M` | ❌ | Erro imediato: "does not support tools" |
| `qwen2.5:3b` | ⚠️ | Suporta tecnicamente; entra em loop (chama mesmo tool 3x) → resposta vazia |
| `llama3.2:3b` | ⚠️ | Não retorna erro mas ignora tools → gera texto genérico de kubectl |

### Por que o HolmesGPT é lento em CPU

HolmesGPT funciona como agente: para cada investigação, o LLM decide qual tool chamar, aguarda o resultado, e decide a próxima ação. Isso gera **3–6 rodadas de inferência por cenário**. Em CPU com modelos ≤7B, cada rodada leva 2–3 min → **10–20 min por investigação**.

K8sGPT, por contraste, faz **1 chamada ao LLM** por issue (coleta os dados primeiro via API do k8s, passa tudo de uma vez).

### Conclusão para o ADR

HolmesGPT é uma ferramenta projetada para LLMs hospedados em nuvem (GPT-4, Claude 3.x), onde cada chamada leva segundos. O gate CPU-only elimina essa categoria de modelo, tornando a ferramenta impraticável independentemente da qualidade do diagnóstico em condições ideais.

---

## Fase 0 — Matriz de modelos LLM

> Cenário fixo: OOMKilled (Cenário 2). Ferramenta: K8sGPT v0.4.33 + Ollama. Gate latência: < 120s.
> RAM base do Ollama (idle): ~19 MB. Limite configurado: 7 GiB (aumentado de 5 GiB para acomodar mistral).

| Modelo | RAM pico (observada) | Latência (cenário OOMKilled) | Qualidade RCA (1–5) | Gate latência | Viável? |
|---|---|---|:---:|:---:|:---:|
| `gemma2:2b` | ~4.900 MB | ~60s | 3 | ✅ | ✅ **Avança** |
| `phi3:mini` | ~4.987 MB | 176s | 2 | ❌ >120s | ❌ Eliminado |
| `phi3.5:3.8b` | ~5.107 MB | 36s | 3 | ✅ | ✅ **Avança** |
| `llama3.2:3b` | ~5.105 MB | 17s | 2 | ✅ | ⚠️ Condicional¹ |
| `qwen2.5:3b` | ~3.081 MB | 85s | 3 | ✅ | ✅ **Avança** |
| `mistral:7b-instruct-q4_K_M` | ~6.550 MB | 84s | 4 | ✅ | ✅ **Avança** |

> ¹ `llama3.2:3b`: latência mais rápida (17s), mas RCA errou a causa raiz — atribuiu OOMKilled a "node affinity/scheduling". Aprovado no gate de latência mas reprovado em qualidade mínima (nota 2). Eliminado por qualidade.

### Detalhes dos diagnósticos

| Modelo | Erro detectado | Causa raiz correta? | Soluções propostas |
|---|---|:---:|---|
| `gemma2:2b` | `OOMKilled container=app` | ✅ | Aumentar limits, monitorar uso, autoscaler |
| `phi3:mini` | `OOMKilled container=app` | ✅ | Genérico: "monitor memory" — pouco acionável |
| `phi3.5:3.8b` | `OOMKilled container=app` | ✅ | `kubectl top`, aumentar requests, autoscaler |
| `llama3.2:3b` | `OOMKilled container=app` | ❌ | Confundiu com node affinity / scheduling issue |
| `qwen2.5:3b` | `OOMKilled container=app` | ✅ | Aumentar limits, otimizar código, mais recursos no node |
| `mistral:7b-instruct-q4_K_M` | `OOMKilled exitCode=137 container=app` | ✅ | `kubectl describe pod`, editar YAML limits, apply, monitorar |

### Modelos que avançam para Fase 1

| Modelo | Motivo |
|---|---|
| `gemma2:2b` | Baseline viável, menor RAM, boa qualidade |
| `phi3.5:3.8b` | Latência excelente (36s), qualidade equivalente ao baseline |
| `qwen2.5:3b` | Menor RAM pico (3 GB), latência aceitável |
| `mistral:7b-instruct-q4_K_M` | Melhor qualidade RCA (4/5), mais detalhado — exige 7 GiB Ollama |

### Modelos eliminados

| Modelo | Gate violado | Motivo |
|---|---|---|
| `phi3:mini` | Latência | 176s > 120s; RAM quase no limite de 5 GiB anterior |
| `llama3.2:3b` | Qualidade | Nota 2/5; diagnosticou OOMKilled como problema de scheduling |
