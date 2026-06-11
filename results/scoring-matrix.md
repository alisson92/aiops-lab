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

**Nota sobre qualidade do modelo e os scores acima:**
Os RCAs registrados foram gerados com `gemma2:2b` (modelo baseline mínimo — 2B parâmetros, ~1.6 GB RAM). Os scores de qualidade (ex: "Qualidade do RCA: 3/5") refletem esse modelo. A Fase 0 identificou `mistral:7b-instruct-q4_K_M` como modelo de maior qualidade (4/5), e `phi3.5:3.8b` com melhor relação latência/qualidade. Em produção, com o modelo adequado:
- Espera-se maior consistência de formato JSON (gemma2:2b vaza markdown e blocos inválidos)
- RCAs mais profundos e específicos ao contexto do alerta
- As limitações de qualidade documentadas acima são do modelo, **não da plataforma Keep**

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

### Classificação final dos modelos

**Tier 1 — Eliminados por razões intrínsecas ao modelo**

| Modelo | Gate violado | Motivo | Os controles de infra mudam isso? |
|---|---|---|:---:|
| `phi3:mini` | Latência | 176s de inferência — acima do gate de 120s | ❌ Latência é do modelo, não do cold start |
| `llama3.2:3b` | Qualidade | Diagnosticou OOMKilled como scheduling (erro de raciocínio) | ❌ `format:json` melhora estrutura, não raciocínio |

**Tier 2 — Viáveis no lab (validados com controles de infra aplicados)**

| Modelo | RAM | Latência | Qualidade RCA | Adotado no workflow |
|---|---|---|:---:|:---:|
| `gemma2:2b` | 1.6 GiB | ~14s | 3/5 | — |
| `phi3.5:3.8b` | 2.2 GiB | ~36s | 3/5 | ✅ modelo atual |
| `qwen2.5:3b` | 1.9 GiB | ~85s | 3/5 | — |

**Tier 3 — Viável em produção, requer validação em EKS**

| Modelo | RAM necessária | Latência | Qualidade RCA | Bloqueio atual |
|---|---|---|:---:|---|
| `mistral:7b-instruct-q4_K_M` | 4.5 GiB livres | ~84s | **4/5** | Hardware local (VM 8 GiB). Em node EKS ≥ 12 GiB é viável. Candidato preferencial para produção. |

> **Nota:** a separação Tier 2 / Tier 3 é deliberada. `mistral:7b` não foi eliminado por qualidade — foi bloqueado por uma restrição de hardware que não existe em produção. Eliminar definitivamente um modelo por um constraint temporário de lab seria um erro metodológico. A validação em EKS é o próximo passo antes de definir o modelo de produção.

---

## Fase 2 — Keep + K8sGPT em conjunto: complementaridade

> Ambas as ferramentas ativas simultaneamente sobre os 4 cenários.
> Pergunta central: o par soma valor real ou apenas duplica esforço?

### Comparativo de velocidade e qualidade por cenário

| Cenário | K8sGPT (tempo) | K8sGPT (qualidade do finding) | Keep (tempo) | Keep (ai_rca qualidade) |
|---|---|---|---|---|
| CrashLoopBackOff | **~24s** (Result CR) | "last termination reason is Error" — genérico, sem causa raiz | ~33s (alerta + ai_rca) | "CrashLoopBackOff — pod unable to complete execution" — genérico, sem causa raiz |
| OOMKilled | **~49s** | "Pod forcefully terminated due to OOM Killer" + kubectl top + ajuste de limits — correto | ~4m26s¹ | "container terminated by OOM Killer" + kubectl top + ajuste — correto |
| ImagePullBackOff | **~29s** | **`nginx:this-tag-does-not-exist-99999` não encontrado** — tag exata incluída, melhor contexto | ~4m22s¹ | "pod stuck waiting for docker image" — genérico, sem a tag exata |
| Readiness Failing | **~49s** | "readiness probe failed, 404 — service unreachable" — **diagnóstico errado** (atribuiu a network issue) | ~4m16s (Grafana `for: 2m`) | "readiness probe is failing" + kubectl describe — parcial mas não errado |

> ¹ Tempos do Keep incluem: coleta Prometheus (~1m), avaliação Grafana (for: 0–1m), agrupamento de notificações, webhook, workflow LLM (~10–20s). K8sGPT não depende de nenhuma dessas etapas — polling direto da API k8s.

### Análise de complementaridade

| Dimensão | K8sGPT | Keep | Complementam? |
|---|---|---|---|
| **Velocidade de detecção** | ✅ 24–49s (vencedor claro) | ⚠️ 33s–4m26s (depende do Grafana) | Sim — K8sGPT avisa antes em todos os cenários |
| **Contexto k8s no diagnóstico** | ✅ Acessa API diretamente — inclui tag de imagem, reason do container | ⚠️ Só recebe payload Grafana (name/severity/description) | Sim — K8sGPT tem contexto mais rico |
| **Qualidade do RCA** | ⚠️ Cenário 4 errou a causa raiz (network vs probe path) | ⚠️ Genérico mas nunca factualmente errado | Sim — Keep como "segundo voto" evita false-root-cause |
| **Gestão do ciclo de vida do alerta** | ❌ Não tem — só cria CR, não rastreia resolução | ✅ Fingerprint, dedup, histórico, status resolved/firing | Sim — Keep é o hub que K8sGPT não tem |
| **Integração com Teams** | ❌ Não tem | ✅ Contact point nativo | Sim — Keep é o único canal de notificação |
| **Footprint combinado** | ~256Mi | ~2 GiB | Trade-off — custo de RAM vale pela funcionalidade |
| **Tier de deploy** | Tier B (ClusterRole + CRD) | Tier A (namespaced) | Tensão — K8sGPT requer aprovação adicional |

### Conclusão da Fase 2

**O par se complementa, com papéis distintos e não sobrepostos:**

- **K8sGPT = radar precoce**: detecta em 24–49s via polling da API k8s com contexto rico (reason, tag de imagem, exit code). Não tem alerting, não tem integração com Teams, não rastreia resolução.
- **Keep = plataforma de resposta**: recebe de qualquer fonte (Grafana, webhook), gerencia ciclo de vida dos alertas, enriquece com LLM, notifica o Teams. Latência maior porque depende do pipeline Grafana.

**Lacuna crítica na integração**: K8sGPT não tem como enviar findings diretamente para o Keep na versão v0.4.33/operator v0.2.27 (sink suporta apenas Slack, Mattermost, CloudEvents; Keep não tem receiver CloudEvents nativo). O dado do K8sGPT fica isolado no CR `Result` — visível apenas via kubectl, não no dashboard do Keep nem no Teams.

**Recomendação para produção**: usar Keep como hub central e K8sGPT como fonte adicional de diagnóstico complementar ao Grafana. A integração ideal exigiria um adapter CloudEvents→Keep (ex: pequeno job que consome os Results CRs do K8sGPT e os publica no Keep via `/alerts/event/prometheus`), o que está fora do escopo deste bake-off.

---

## Validação em VM Hyper-V — 2026-06-10

> Execução dos 4 cenários de falha na VM Vagrant (Hyper-V, `generic/debian12`, 4 vCPUs / 8 GB RAM).
> Objetivo: confirmar reprodutibilidade do fluxo end-to-end fora do WSL2 e registrar outputs reais do ai_rca.
> Modelo utilizado: `gemma2:2b` (baseline). Ver nota de qualidade na seção "Fase 1 — Keep".

### Resultado consolidado

| Cenário | Alerta disparou no Grafana | Apareceu no Keep | ai_rca presente | Qualidade ai_rca | Alerta resolveu após reversão |
|---|:---:|:---:|:---:|:---:|:---:|
| 1 — CrashLoopBackOff | ✅ | ✅ | ✅ | 2/5 | ✅ |
| 2 — OOMKilled | ✅ | ✅ | ✅ | 3/5 | ✅ |
| 3 — ImagePullBackOff | ✅ | ✅ | ✅ | 2/5 | ✅ |
| 4 — Readiness Failing | ✅ | ✅ | ✅ | 2/5 | ✅ |

**Conclusão de reprodutibilidade:** fluxo end-to-end validado. `make setup && make pf` + scripts de cenário funcionam do zero em VM limpa.

### Outputs brutos do ai_rca (gemma2:2b)

**Cenário 1 — CrashLoopBackOff**
- Formato: JSON válido ✅
- `root_cause`: "pod is experiencing a CrashLoopBackOff condition, indicating it might be stuck in an infinite loop" — sintoma correto, causa real (`exit 1`) não identificada
- `immediate_action`: `kubectl logs <pod-name>` — correto mas genérico (sem o nome real do pod)
- `prevention`: "Implement resource monitoring and proactive health checks" — genérica

**Cenário 2 — OOMKilled**
- Formato: markdown livre (não JSON) ❌
- `root_cause`: container running out of memory, forcefully shut down — correto ✅
- `immediate_action`: investigar recursos do container, checar logs — adequado
- `prevention`: limitar memory allocation, evitar contention — prático ✅
- Melhor output entre os 4 cenários — modelo correlacionou OOMKilled com limites de memória

**Cenário 3 — ImagePullBackOff**
- Formato: bloco `toolz` inválido + markdown ❌ (formato híbrido não parseável)
- `root_cause`: "pod failed to download the image due to an issue with the registry details" — correto ✅
- `immediate_action`: verificar image name/tag + `kubectl describe pod` — correto ✅
- `prevention`: garantir informações corretas de imagem — adequada
- Conteúdo útil apesar do formato ruim

**Cenário 4 — Readiness Failing**
- Formato: JSON válido ✅ + seção explicativa em markdown adicional
- `root_cause`: "Readiness Probe is failing due to an unknown reason" — correto na superfície; path `/this-path-will-never-exist` não identificado (sem acesso à API k8s)
- `immediate_action`: `kubectl logs` + diagnose root cause — correto mas genérico
- `prevention`: "Ensure Readiness Probe configuration accurately reflects health checks" — genérica

### Análise de formato (gemma2:2b)

| Cenário | JSON limpo | Markdown extra | Formato inválido |
|---|:---:|:---:|:---:|
| CrashLoopBackOff | ✅ | ❌ | ❌ |
| OOMKilled | ❌ | ✅ | ❌ |
| ImagePullBackOff | ❌ | ✅ | ✅ (`toolz`) |
| Readiness Failing | ✅ | ✅ | ❌ |

**Inconsistência de formato é a principal limitação operacional do gemma2:2b.** Em 3 de 4 cenários o output não é JSON puro — quebraria um parser downstream sem tratamento de erro. Modelos maiores da matriz (phi3.5:3.8b, mistral:7b) têm maior aderência a instruções de formato e devem produzir JSON consistente.

> ⚠️ Os scores de qualidade acima refletem o modelo baseline. Com o modelo recomendado pela Fase 0 (`mistral:7b-instruct-q4_K_M`, 4/5 de qualidade), espera-se: JSON consistente, RCAs mais específicos ao contexto, e ações imediatas com variáveis reais (nome do pod, namespace) — elevando a nota de "Qualidade do RCA" do Keep de 3 para potencialmente 4/5.

---

## Investigação de qualidade do ai_rca — modelo e formato (2026-06-10)

> Investigação adicional após validação na VM. Objetivo: identificar modelo e configuração
> ideais para o workflow Keep em ambiente CPU-only com cluster em uso contínuo.

### Problemas identificados e resolvidos

| Problema | Sintoma | Causa raiz | Solução |
|---|---|---|---|
| **Cold start** | Primeiro alerta após inatividade falha com Ollama 500 | Ollama descarrega modelos após 5min de inatividade (padrão) | `OLLAMA_KEEP_ALIVE=-1` + `run: [phi3.5:3.8b]` no values |
| **Formato inconsistente** | ai_rca embrulhado em markdown, código duplicado, texto extra | Modelos instruct ignoram parcialmente instruções de formato no prompt | `structured_output_format: json` na chamada ao provider Ollama |
| **mistral:7b instável** | Ollama 500 em todos os cenários com mistral | Requer 4.5 GiB de RAM *livres*; cluster com 7+ dias de uptime tinha apenas 3.9 GiB free (buffer/cache não contado) | Descartado para uso contínuo; phi3.5:3.8b adotado |

### Modelo escolhido para o workflow: `phi3.5:3.8b`

| Critério | gemma2:2b | mistral:7b | phi3.5:3.8b |
|---|:---:|:---:|:---:|
| RAM necessária | 1.6 GiB | 4.5 GiB free | 2.2 GiB |
| Latência | ~14s | ~84s | ~36s |
| Qualidade RCA | 3/5 | 3/5* | 3/5 |
| Formato JSON consistente | ❌ | ❌* | ✅ (com `format:json`) |
| Estável em cluster com carga | ✅ | ❌ | ✅ |

> *mistral:7b não chegou a ser validado com formato correto — falhou por memória antes disso.

### Configuração final do workflow (commit `4c64e67`)

```yaml
model: phi3.5:3.8b
structured_output_format: "json"   # JSON puro — elimina markdown e texto extra
```

```yaml
# values/ollama.yaml
extraEnv:
  - name: OLLAMA_KEEP_ALIVE
    value: "-1"              # modelo nunca descarregado — elimina cold start
models:
  run:
    - phi3.5:3.8b            # pré-carregado na inicialização do pod
```

### Resultado final validado

`ai_rca` com `phi3.5:3.8b` + `format:json` + `KEEP_ALIVE=-1`:
```json
{
  "root_cause": "...",
  "immediate_action": "...",
  "prevention": "..."
}
```
JSON limpo, três campos estruturados, sem markdown, sem duplicação. Workflow estável sob uso contínuo.

---

## Comparativo completo de modelos — Keep workflow (2026-06-11)

> 3 modelos Tier 2 × 4 cenários de falha. Dados brutos em `results/model-comparison-run2.json`.
> Controles aplicados: `OLLAMA_KEEP_ALIVE=-1` · `structured_output_format: json`.
> Metodologia: script automatizado `scripts/run-model-comparison.sh` — injeção → espera → captura → reversão.

### Resultado por modelo e cenário

| Modelo | CrashLoopBackOff | OOMKilled | ImagePullBackOff | Readiness |
|---|:---:|:---:|:---:|:---:|
| `gemma2:2b` | ✅ | ✅ | ✅ | ✅ |
| `phi3.5:3.8b` | ✅ | ✅ | ✅ | ✅ |
| `qwen2.5:3b` | ✅ | ✅ | ✅ | ✅ |

Todos os 12 campos `ai_rca` preenchidos como objetos JSON válidos.

### Amostras dos root_cause por modelo

**gemma2:2b**
| Cenário | root_cause (resumido) | Correto? |
|---|---|:---:|
| CrashLoopBackOff | "The Pod has entered a CrashLoopBackOff state." | ⚠️ Parcial — sintoma, não causa raiz |
| OOMKilled | "The container may be using more memory than its allocated limit." | ✅ |
| ImagePullBackOff | "The pod is failing to download the image." | ✅ |
| Readiness | "readiness probe has been failing for more than 2 minutes." | ⚠️ Parcial — sem path |

**phi3.5:3.8b** *(nota: usa camelCase nos campos: `rootCause`, `immediateAction`, `prevention`)*
| Cenário | rootCause (resumido) | Correto? |
|---|---|:---:|
| CrashLoopBackOff | "O pod está apresentando o estado CrashLoopBackOff, indicando que ele se reiniciou várias vezes." | ⚠️ Parcial |
| OOMKilled | "O container alcançou seu alvo máximo de uso total da memória, levando ao OOMKilled." | ✅ |
| ImagePullBackOff | "O namespace aiops-lab não possui uma imagem válida ou as credenciais do registry para acessá-la." | ✅ |
| Readiness | "O pod tem estado em um status Running, mas sua leitura está falhando há mais de 2 minutos." | ⚠️ Parcial |

**qwen2.5:3b**
| Cenário | root_cause (resumido) | Correto? |
|---|---|:---:|
| CrashLoopBackOff | "Um pod chamado 'my-pod' no namespace 'aiops-lab' entrou em estado de CrashLoopBackOff." | ⚠️ Parcial — inventa nome de pod |
| OOMKilled | "Um container em execução no namespace aiops-lab foi encerrado por OOMKilled." | ✅ |
| ImagePullBackOff | "O pod está falhando ao tentar baixar a imagem docker://\<nome_imagem\>:\<tag\>" | ✅ |
| Readiness | "O pod 'nginx-service' no namespace 'aiops-lab' não está passando o teste de disponibilidade." | ⚠️ Parcial — inventa nome de pod |

### Observações por modelo

| Modelo | Idioma de resposta | Consistência de campos | Inventou nomes de pods? | Avaliação |
|---|---|---|:---:|---|
| `gemma2:2b` | Inglês | `root_cause` · `immediate_action` · `prevention` | ❌ | Conciso, correto no essencial, superficial |
| `phi3.5:3.8b` | Português | `rootCause` · `immediateAction` · `prevention` (**camelCase** — requer normalização) | ❌ | Mais verboso, ações imediatas mais elaboradas |
| `qwen2.5:3b` | Português | `root_cause` · `immediate_action` · `prevention` | ✅ (placeholder de nomes) | Cometeu alucinação leve: inventou nomes de pods (`my-pod`, `nginx-service`) não presentes no payload |

### Conclusão do comparativo

- **Nenhum modelo atingiu 4/5 de qualidade** nos 4 cenários — todos ficam em 3/5 com o payload Grafana como único contexto.
- **qwen2.5:3b** apresentou alucinação leve (nomes de pods inventados), o que o desqualifica como modelo principal para ambiente de produção.
- **phi3.5:3.8b** tem a limitação do camelCase nos campos (requereria normalização em parser downstream), mas a qualidade é equivalente ao gemma2:2b.
- **gemma2:2b** é o mais conservador e consistente estruturalmente. Adequado como baseline.
- **`mistral:7b` (Tier 3)** permanece como candidato preferencial para EKS — único que atingiu 4/5. A validação em node ≥ 12 GiB é o próximo passo antes de definir o modelo de produção.

> **Raiz comum da limitação de qualidade (todos os modelos):** o LLM recebe apenas `name`, `description` e `severity` do payload Grafana. Sem `kubectl describe pod`, exit code, ou razão de término do container, o diagnóstico é necessariamente genérico. Extensão do workflow com step de provider `kubernetes` elevaria a qualidade independentemente do modelo.
