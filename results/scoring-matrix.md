# Matriz de Pontuação — AIOps Bake-off

> Preencher após a Fase 1 (isolado). Pontuação: 1–5 por critério × peso.
> Gates são pass/fail: reprovado em qualquer gate = não entra na pontuação.

---

## Gates eliminatórios

| Gate | Keep | K8sGPT | HolmesGPT |
|---|:---:|:---:|:---:|
| Helm-deployável (chart oficial) | - | - | - |
| 100% local (sem egress em runtime) | - | - | - |
| CPU-only (sem GPU) | - | - | - |
| Custo zero (sem SaaS / API paga) | - | - | - |
| **Resultado** | **-** | **-** | **-** |

---

## Pontuação (só quem passou nos gates)

| Bloco | Critério | Peso | Keep | K8sGPT | HolmesGPT |
|---|---|:---:|:---:|:---:|:---:|
| **Eficácia técnica** | Qualidade do RCA | Alto | - | - | - |
| | Cobertura (% cenários úteis) | Médio | - | - | - |
| | Tempo até diagnóstico útil | Médio | - | - | - |
| | Redução de ruído (dedup/correlação) | Médio | - | - | - |
| | Falso-positivo / alucinação | **Alto** | - | - | - |
| **Aptidão operacional** | Esforço de setup e day-2 | **Alto** | - | - | - |
| | Autonomia de deploy (Tier A vs B) | **Alto** | - | - | - |
| | Footprint (requests/limits) | Médio-alto | - | - | - |
| | Segurança e auditabilidade | **Alto** | - | - | - |
| | Maturidade / risco de roadmap | Médio | - | - | - |
| | Ajuste ao stack atual | Médio | - | - | - |
| **Total ponderado** | | | **-** | **-** | **-** |

---

## Evidências por cenário

### Cenário 1 — CrashLoopBackOff
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | - | - | - | - |
| K8sGPT | `the last termination reason is Error container=app pod=workload-vitima-796ccdcb97-wn9nf` + sugestões genéricas (checar logs, imagem, rede) | ⚠️ Parcial | ~2–3 min pós-injeção | Detectou a falha; LLM não identificou `exit 1` como causa raiz; sugestões superficiais |
| HolmesGPT | - | - | - | - |

### Cenário 2 — OOMKilled
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | - | - | - | - |
| K8sGPT | `the last termination reason is OOMKilled container=app` + sugestão de aumentar limits.memory, revisar código para memory leaks | ✅ Sim | ~1 min pós-injeção | Causa corretamente nomeada (OOMKilled); soluções pertinentes; não identifica loop de shell como causa específica, mas isso é esperado |
| HolmesGPT | - | - | - | - |

### Cenário 3 — ImagePullBackOff
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | - | - | - | - |
| K8sGPT | `rpc error: failed to pull "nginx:this-tag-does-not-exist-99999": not found` + sugestão de verificar tag e typo | ✅ Sim | ~1 min pós-injeção | Erro completo incluído; causa exata nomeada; soluções pertinentes (verificar tag, registry); melhor resposta entre os cenários |
| HolmesGPT | - | - | - | - |

### Cenário 4 — Readiness failing
| Ferramenta | Diagnóstico produzido | Causa identificada corretamente? | Latência | Notas |
|---|---|:---:|---|---|
| Keep | - | - | - | - |
| K8sGPT | `Readiness probe failed: HTTP probe failed with statuscode: 404` + diagnóstico de problema de rede/service | ❌ Não | ~1–2 min pós-injeção | Detectou o 404 corretamente; LLM errou a causa raiz (atribuiu a "network issue" em vez de path da probe incorreto) |
| HolmesGPT | - | - | - | - |

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
