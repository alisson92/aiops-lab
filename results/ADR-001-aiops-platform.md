# ADR-001 — Adoção de plataforma AIOps para operações Kubernetes

**Status:** Proposto  
**Data:** 2026-06-09 (atualizado 2026-06-11)  
**Autores:** Time de SRE  
**Contexto:** Bake-off técnico — cluster Kind local (validação) / Amazon EKS (alvo de produção)

---

## 1. Contexto e problema

O time de sustentação opera workloads Kubernetes no Amazon EKS e recebe alertas via Grafana Alerting → Microsoft Teams. O volume de alertas cresce, o tempo médio de diagnóstico é alto e as investigações dependem de contexto manual (`kubectl describe`, `kubectl logs`).

**Objetivo:** adotar uma ferramenta AIOps open-source que:
- Reduza o tempo até o diagnóstico útil (MTTD)
- Enriqueça alertas com contexto e sugestões de ação antes de chegar no Teams
- Opere 100% local (sem egress, sem SaaS, sem custo de API)
- Seja deployável via Helm no namespace do projeto (Tier A) sem exigir aprovação adicional além da GMUD padrão

---

## 2. Gates eliminatórios (pass/fail)

Qualquer reprovação exclui a ferramenta da recomendação.

| Gate | Critério |
|---|---|
| **Helm-deployável** | Chart oficial upstream; sem recursos fora do namespace sem aviso |
| **100% local** | Sem egress em runtime; modelos pré-carregados; Ollama offline |
| **CPU-only** | Sem GPU; sem nodeSelector de hardware especial |
| **Custo zero** | Sem SaaS, sem API paga, sem tier pago |

---

## 3. Opções avaliadas

### 3.1 K8sGPT (k8sgpt-ai/k8sgpt · operator v0.2.27 / app v0.4.33)

**Mecanismo:** polling da API Kubernetes a cada ciclo; coleta dados brutos do recurso com problema; envia ao LLM em uma chamada; persiste o resultado em CRs do tipo `Result`.

**Resultado dos gates:**

| Gate | Resultado |
|---|---|
| Helm-deployável | ✅ |
| 100% local | ✅ |
| CPU-only | ✅ |
| Custo zero | ✅ |
| **Tier** | ⚠️ **Tier B** — requer `ClusterRole` + CRD (`k8sgpts.core.k8sgpt.ai`, `results.core.k8sgpt.ai`) |

**Evidências de desempenho (modelo gemma2:2b, 4 cenários):**

| Cenário | Detecção | Causa correta? | Contexto k8s |
|---|---|:---:|---|
| CrashLoopBackOff | **~24s** | ⚠️ Parcial | "last termination reason is Error" — sem exit code |
| OOMKilled | **~49s** | ✅ | Termination reason + kubectl top + ajuste de limits |
| ImagePullBackOff | **~29s** | ✅ | **Tag exata** `nginx:this-tag-does-not-exist-99999` incluída |
| Readiness Failing | **~49s** | ❌ | Detectou 404 mas atribuiu a "network issue" (falso diagnóstico) |

**Pontuação ponderada Fase 1:** **3.1 / 5**

**Pontos fortes:** velocidade de detecção (24–49s, mais rápido que qualquer alternativa), contexto k8s rico (acesso direto à API), footprint mínimo (~256 Mi RAM), projeto CNCF Sandbox maduro.

**Limitações:** Tier B obriga aprovação explícita do cliente antes do deploy; não tem integração com o fluxo Grafana→Teams (opera como camada paralela desconectada); sem gestão de ciclo de vida de alertas; cenário Readiness produziu diagnóstico factualmente errado.

---

### 3.2 HolmesGPT (robusta-dev/holmesgpt · chart 0.31.1)

**Mecanismo:** agente LLM com tool-calling — investiga incidentes chamando kubectl iterativamente até chegar na causa raiz.

**Resultado dos gates:**

| Gate | Resultado |
|---|---|
| Helm-deployável | ✅ |
| 100% local | ✅ |
| CPU-only | ✅ (hardware) |
| Custo zero | ✅ |
| **Viabilidade operacional** | ❌ **Eliminado** |

**Motivo da eliminação:** o modelo agentic de tool-calling é incompatível com os modelos LLM disponíveis em CPU-only via Ollama:

| Modelo | Suporte a tools | Comportamento |
|---|:---:|---|
| gemma2:2b, phi3.5:3.8b, mistral:7b | ❌ | Erro: "does not support tools" |
| qwen2.5:3b | ⚠️ | Loop infinito (chama mesmo tool 3×) → resposta vazia |
| llama3.2:3b | ⚠️ | Ignora tools; gera texto genérico |

Mesmo se um modelo fosse compatível, cada investigação requer 3–6 rodadas de inferência. Em CPU com modelos ≤7B cada rodada leva 2–3 min → **10–20 min por incidente**. Inviável operacionalmente.

HolmesGPT foi projetado para LLMs hospedados em nuvem (GPT-4, Claude) onde cada chamada leva segundos. **O gate CPU-only elimina estruturalmente essa categoria de ferramenta.**

**Pontuação ponderada:** **N/A — eliminado nos gates**

---

### 3.3 Keep (keephq/keep · chart 0.1.96)

**Mecanismo:** hub de alertas com webhook receiver; ao receber alertas do Grafana, dispara workflows YAML que chamam o Ollama via provider nativo; enriquece o alerta com `ai_rca` e roteia para Teams.

**Resultado dos gates:**

| Gate | Resultado |
|---|---|
| Helm-deployável | ✅ |
| 100% local | ✅ |
| CPU-only | ✅ |
| Custo zero | ✅ |
| **Tier** | ✅ **Tier A** — 100% namespaced (Deployment, Service, PVC, ServiceAccount) |

**Evidências de desempenho (modelo gemma2:2b — baseline; ver seção 3.4 para comparativo completo):**

| Cenário | Detecção (Grafana→Keep) | ai_rca gerado? | Causa correta? |
|---|---|:---:|:---:|
| CrashLoopBackOff | ~33s (Grafana `for: 1m`) | ✅ | ⚠️ Parcial — sem contexto k8s |
| OOMKilled | ~4m26s¹ | ✅ | ✅ |
| ImagePullBackOff | ~4m22s¹ | ✅ | ✅ |
| Readiness Failing | ~4m16s (Grafana `for: 2m`) | ✅ | ⚠️ Parcial — sem path da probe |

> ¹ Inclui scrape Prometheus (~1m) + avaliação Grafana + agrupamento + webhook + LLM (~10–20s).

**Pontuação ponderada Fase 1:** **3.5 / 5**

**Pontos fortes:** único candidato 100% Tier A; integração nativa com Grafana→Teams (fluxo exato do cliente); fingerprinting e dedup nativos; trilha de auditoria completa (workflow runs, alert history); ai_rca nunca produziu diagnóstico factualmente errado (mais conservador que K8sGPT).

**Limitações:** setup mais complexo (4 componentes + contact point + workflow + Ollama provider); footprint maior (~2 GiB RAM); projeto mais jovem com alguns bugs de edge case encontrados (provider perde estado em restarts, contact point precisa ser provisionado via arquivo para sobreviver a upgrades); contexto do LLM limitado ao payload Grafana (sem acesso direto à API k8s).

---

---

## 3.4 Seleção do modelo LLM para o Keep

O Keep delega a inferência ao Ollama. A escolha do modelo afeta diretamente a qualidade do `ai_rca`, a latência do enriquecimento e a estabilidade sob carga contínua.

### Configuração base obrigatória (independente do modelo)

Dois problemas de infraestrutura foram identificados durante os testes e corrigidos antes de qualquer comparação entre modelos — sem esses controles, falhas de infraestrutura seriam erroneamente atribuídas à qualidade do modelo:

| Problema | Sintoma | Solução |
|---|---|---|
| **Cold start** | Ollama descarrega modelos após 5min de inatividade → primeiro alerta falha com 500 | `OLLAMA_KEEP_ALIVE=-1` + `run: [<modelo>]` no chart |
| **Formato inconsistente** | Modelos embrulham JSON em markdown, duplicam output, adicionam texto extra | `structured_output_format: json` no provider Ollama do Keep |

### Classificação dos modelos por viabilidade

**Tier 1 — Eliminados por razões intrínsecas (não mudam com hardware superior)**

| Modelo | Gate violado | Motivo | Impacto dos controles de infra |
|---|---|---|---|
| `phi3:mini` | Latência | 176s de inferência — ultrapassa gate de 120s | Nenhum — latência é do modelo, não do cold start |
| `llama3.2:3b` | Qualidade | Atribuiu OOMKilled a problema de scheduling (erro de raciocínio) | Nenhum — `format:json` melhora estrutura, não raciocínio |

**Tier 2 — Viáveis no lab (validados com os controles de infra · dados de `results/model-comparison-run2.json`)**

| Modelo | RAM | Latência | Qualidade RCA | JSON consistente | Observação |
|---|---|---|:---:|:---:|---|
| `gemma2:2b` | 1.6 GiB | ~14s | 3/5 | ✅ | Mais conciso; responde em inglês; conservador (não inventa contexto) |
| `phi3.5:3.8b` | 2.2 GiB | ~36s | 3/5 | ✅ | Mais verboso; responde em português; usa camelCase nos campos (`rootCause`) — requer normalização |
| `qwen2.5:3b` | 1.9 GiB | ~85s | 3/5 | ✅ | Responde em português; apresentou alucinação leve (inventou nomes de pods não presentes no payload) |

**Tier 3 — Viável em produção, requer validação em EKS**

| Modelo | RAM necessária | Latência | Qualidade RCA | Restrição atual |
|---|---|---|:---:|---|
| `mistral:7b-instruct-q4_K_M` | 4.5 GiB livres | ~84s | **4/5** | Bloqueado por RAM no lab (VM 8 GiB com múltiplos serviços). Em node EKS ≥ 12 GiB é viável com folga. |

> **Importante:** a eliminação do `mistral:7b` no lab é uma limitação de hardware local, não do modelo. Em produção com node `t3.xlarge` (16 GiB) ou equivalente, é o modelo de maior qualidade testado e deve ser o candidato preferencial. **Validação em EKS é recomendada antes de definir o modelo de produção.**

### Modelo adotado no lab: `phi3.5:3.8b`

Melhor relação latência (36s) × qualidade (3/5) × estabilidade para o hardware disponível localmente. Configuração final persistida em `charts/keep/workflows/ollama-grafana-alert-enrichment.yaml` e `charts/ollama/values.yaml`.

---

## 4. Fase 2 — K8sGPT + Keep em conjunto

Os dois foram executados simultaneamente sobre os 4 cenários. **Os papéis são complementares e não sobrepostos:**

| Papel | K8sGPT | Keep |
|---|---|---|
| Radar precoce (MTTD) | ✅ 24–49s | ❌ 33s–4m+ |
| Contexto k8s rico | ✅ API direta | ❌ Payload Grafana |
| Gestão de alertas | ❌ Só CR | ✅ Fingerprint, dedup, histórico |
| Notificação Teams | ❌ | ✅ Contact point nativo |
| Tier de deploy | ❌ Tier B | ✅ Tier A |

**Lacuna de integração:** K8sGPT não tem como enviar findings ao Keep nativamente (sink suporta Slack, Mattermost, CloudEvents; Keep não tem receiver CloudEvents). Os dados ficam isolados no CR `Result`. Uma integração plena exigiria um adapter (fora do escopo deste bake-off).

---

## 5. Decisão

### Recomendação principal: **Keep** como plataforma AIOps central

**Justificativa:**
1. **Tier A puro** — deploy sem aprovação adicional, dentro do escopo da GMUD padrão do time de sustentação
2. **Encaixe exato no stack existente** — o fluxo Prometheus → Grafana → Keep (webhook) → Teams é o fluxo que o cliente já usa; Keep é o elo que falta, não uma camada nova
3. **Sem falsos diagnósticos** — o LLM do Keep nunca produziu causa raiz factualmente errada nos 4 cenários (K8sGPT errou no cenário Readiness)
4. **Gestão de ciclo de vida** — dedup, fingerprinting, histórico e auditoria que K8sGPT não oferece
5. **Extensível** — o workflow YAML pode ser enriquecido com um step de provider `kubernetes` para passar `kubectl describe` ao LLM, eliminando a limitação de contexto

### Recomendação complementar: **K8sGPT** como ferramenta de diagnóstico on-demand

**Condição:** sujeito a aprovação do cliente para os recursos Tier B (CRD + ClusterRole).

**Papel:** radar de detecção precoce (24–49s) com contexto k8s rico — útil para SRE durante plantão, não como caminho principal de alerting.

**Se a aprovação Tier B não for viável:** K8sGPT pode ser executado manualmente via CLI (`kubectl exec` no pod ou `k8sgpt analyze` local) sem necessidade de operator, com menor atrito.

### HolmesGPT: **não recomendado** neste contexto

Estruturalmente inviável em ambiente CPU-only com modelos open-source disponíveis via Ollama. Reconsiderar apenas se o cliente aprovar LLM hospedado em nuvem (GPT-4 ou Claude) — cenário que viola o gate de custo zero.

---

## 6. Consequências e próximos passos

### Imediatos (antes do deploy em EKS)
- [ ] Confirmar nome da `StorageClass` em produção com o time de infra (placeholder `<EKS_STORAGECLASS_NAME>` nos values)
- [ ] Definir URL do webhook do Teams para o contact point do Keep
- [ ] Validar que o namespace do projeto tem cota de recursos suficiente (~2 GiB RAM extra para o Keep)
- [ ] Revisar o workflow `ollama-grafana-alert-enrichment` com um step adicional de provider `kubernetes` para enriquecer o contexto do LLM com dados reais do pod

### Médio prazo
- [ ] Avaliar aprovação Tier B para K8sGPT junto ao cliente (valor: detecção 24–49s antes do Grafana disparar)
- [ ] **Validar `mistral:7b-instruct-q4_K_M` em node EKS ≥ 12 GiB** — modelo de maior qualidade testado (4/5); bloqueado apenas por hardware local; candidato preferencial para produção se validado
- [ ] Migrar regras de alerta Grafana para IaC/Terraform (atualmente criadas via provisioning no chart)
- [ ] Adicionar adapter CloudEvents→Keep se K8sGPT for aprovado (integração de findings no dashboard do Keep)

### Riscos residuais
| Risco | Probabilidade | Mitigação |
|---|:---:|---|
| Provider Ollama perde estado em restart do Keep backend | Média | Já mitigado via Secret no k8s — confirmar na versão de produção |
| Latência LLM (10–20s) causa timeout no workflow | Baixa | Keep tem retry configurável; phi3.5:3.8b responde em ~36s em CPU |
| Cold start Ollama em restart de pod | Média | `OLLAMA_KEEP_ALIVE=-1` + modelo na lista `run:` — eliminado em lab, confirmar em EKS |
| mistral:7b instável em node com pouca RAM livre | Média | Dimensionar node com ≥ 12 GiB RAM; validar antes de adotar em produção |
| HolmesGPT readequado para nuvem no futuro | Alta | Manter avaliação periódica; se cliente aprovar LLM pago, retomar |

---

## 7. Referências

| Artefato | Localização |
|---|---|
| Evidências por cenário e scoring | `results/scoring-matrix.md` |
| Comparativo completo de modelos (dados brutos) | `results/model-comparison-run2.json` |
| Briefing para apresentação ao time | `results/briefing-apresentacao-2026-06-11.md` |
| Values do Keep (lab) | `charts/keep/values-lab.yaml` |
| Values do Ollama | `charts/ollama/values.yaml` |
| Values do K8sGPT | `charts/k8sgpt/values.yaml` |
| Workflow de AI enrichment | `charts/keep/workflows/ollama-grafana-alert-enrichment.yaml` |
| Scripts de injeção de falha | `scenarios/01-crashloopbackoff.sh` · `02-oomkilled.sh` · `03-imagepullbackoff.sh` · `04-readiness-failing.sh` |
| Script de comparação de modelos | `scripts/run-model-comparison.sh` |
