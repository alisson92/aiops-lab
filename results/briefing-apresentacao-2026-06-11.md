# Briefing — AIOps Bake-off: Recomendação de Plataforma
**Data:** 2026-06-11  
**Audiência:** Time técnico  
**Duração estimada:** 20–30 min  
**Artefatos de referência:** `ADR-001-aiops-platform.md` · `scoring-matrix.md`

---

## 1. Contexto e Objetivo

O time de sustentação opera workloads no Amazon EKS e recebe alertas via Grafana → Teams. O problema central: **o volume de alertas cresce, mas o diagnóstico ainda é manual** — um SRE precisa abrir terminal, rodar `kubectl describe`, `kubectl logs` e interpretar o resultado antes de agir.

**Objetivo do bake-off:** avaliar três ferramentas AIOps open-source capazes de enriquecer alertas com diagnóstico automático por LLM, sem custo de API, sem GPU, deployáveis no namespace do projeto.

---

## 2. Metodologia

### Gates eliminatórios (pass/fail — reprovação = descarte imediato)

| Gate | Critério |
|---|---|
| Helm-deployável | Chart oficial; sem recursos fora do namespace sem aviso |
| 100% local | Sem egress em runtime; modelos LLM pré-baixados |
| CPU-only | Sem GPU; sem nodeSelector de hardware especial |
| Custo zero | Sem SaaS, sem API paga |

### Pontuação ponderada (1–5 por critério, só quem passou nos gates)

Critérios agrupados em dois blocos: **Eficácia técnica** (qualidade do RCA, cobertura, latência, redução de ruído, falsos positivos) e **Aptidão operacional** (esforço de setup, Tier de deploy, footprint, segurança, maturidade, ajuste ao stack).

### Ambiente de validação

- **Lab local:** cluster Kind (WSL2) — 4 vCPUs / 8 GB RAM (minha máquina) e VM Vagrant Hyper-V
- **Alvo de produção:** Amazon EKS
- **4 cenários de falha injetados:** CrashLoopBackOff · OOMKilled · ImagePullBackOff · Readiness Failing
- **LLM:** Ollama local (CPU-only) — sem chamada externa

---

## 3. Candidatos avaliados

### 3.1 HolmesGPT — Eliminado nos gates

**Motivo:** modelo agentic com tool-calling. Nenhum modelo CPU-only via Ollama suporta tool-calling adequadamente. Mesmo quando tecnicamente suportado, cada investigação exige 3–6 rodadas de inferência → **10–20 min por incidente em CPU**. Inviável operacionalmente.

> Projetado para GPT-4/Claude em nuvem. O gate CPU-only elimina estruturalmente essa ferramenta.

---

### 3.2 K8sGPT — Viável com restrição

**Mecanismo:** polling da API Kubernetes a cada ciclo; coleta dados brutos do pod; envia ao LLM em uma chamada.

| Ponto | Detalhe |
|---|---|
| ✅ Velocidade de detecção | **24–49s** — mais rápido de todos (polling direto da API k8s) |
| ✅ Contexto rico | Acessa API k8s diretamente — inclui tag de imagem, exit code, reason |
| ✅ Footprint mínimo | ~256 Mi RAM, 1 pod |
| ✅ Projeto maduro | CNCF Sandbox |
| ⚠️ **Tier B** | Requer `ClusterRole` + CRD → **aprovação explícita do cliente obrigatória** |
| ❌ Sem integração Grafana→Teams | Opera como camada paralela desconectada |
| ❌ Cenário Readiness | Diagnosticou 404 como "network issue" — falso diagnóstico |

**Score: 3.1 / 5**

---

### 3.3 Keep — Recomendado

**Mecanismo:** hub de alertas com webhook receiver; ao receber do Grafana, dispara workflow YAML que chama Ollama; enriquece o alerta com `ai_rca`; roteia para Teams.

| Ponto | Detalhe |
|---|---|
| ✅ **Tier A puro** | 100% namespaced — deploy via GMUD padrão, sem aprovação adicional |
| ✅ Encaixe exato no stack | Grafana → Keep (webhook) → Teams — é o elo que falta, não uma camada nova |
| ✅ Sem falso diagnóstico | LLM nunca produziu causa raiz factualmente errada nos 4 cenários |
| ✅ Gestão de ciclo de vida | Fingerprint, dedup, histórico, status resolved/firing |
| ✅ Auditável | Trilha completa de workflow runs, logs, alertas enriquecidos |
| ⚠️ Setup mais complexo | 4 componentes Helm + contact point + workflow + provider Ollama |
| ⚠️ Footprint maior | ~2 GiB RAM (4 pods: backend, frontend, websocket, MySQL) |
| ⚠️ Projeto mais jovem | Alguns bugs de edge case encontrados em campo |

**Score: 3.5 / 5**

---

## 4. Resultado do bake-off

```
K8sGPT    ████████████░░  3.1 / 5   Viável com restrição (Tier B)
Keep      ██████████████░  3.5 / 5   ✅ Recomendado (Tier A)
HolmesGPT ──────────────   N/A       Eliminado (CPU-only inviável)
```

### Papéis complementares (Fase 2)

K8sGPT e Keep **não se substituem — se complementam**:

| Papel | K8sGPT | Keep |
|---|:---:|:---:|
| Radar de detecção precoce (24–49s) | ✅ | ❌ |
| Contexto k8s rico (tag, exit code) | ✅ | ❌ |
| Integração Grafana → Teams | ❌ | ✅ |
| Gestão de ciclo de vida de alertas | ❌ | ✅ |
| Deploy sem aprovação adicional (Tier A) | ❌ | ✅ |

**Lacuna:** K8sGPT não tem como enviar findings diretamente ao Keep (não há receiver nativo). Uma integração plena exigiria um adapter, o que está fora do escopo desta fase.

---

## 5. Seleção do modelo LLM

Esta seção é importante porque **a qualidade do ai_rca depende do modelo escolhido**, mas dois problemas de infraestrutura precisavam ser resolvidos antes de qualquer comparação justa.

### Controles obrigatórios (aplicados antes dos testes comparativos)

| Problema | Sintoma sem o controle | Solução aplicada |
|---|---|---|
| Cold start | Ollama descarrega modelo após 5min → primeiro alerta falha com 500 | `OLLAMA_KEEP_ALIVE=-1` |
| Formato inconsistente | Modelos embrulham JSON em markdown, duplicam output | `structured_output_format: json` no provider Keep |

> ⚠️ Sem esses controles, falhas de infraestrutura seriam atribuídas erroneamente ao modelo. Toda comparação anterior a esses controles é metodologicamente comprometida.

### Classificação dos 6 modelos testados

**Tier 1 — Eliminados por razões intrínsecas (não mudam com hardware superior)**

| Modelo | Motivo |
|---|---|
| `phi3:mini` | Latência de inferência: 176s — acima do gate de 120s |
| `llama3.2:3b` | Qualidade: diagnosticou OOMKilled como scheduling — erro de raciocínio |

**Tier 2 — Viáveis no lab (validados com os controles de infra)**

| Modelo | RAM | Latência | Qualidade RCA | JSON limpo |
|---|---|---|:---:|:---:|
| `gemma2:2b` | 1.6 GiB | ~14s | 3/5 | ✅ |
| `phi3.5:3.8b` | 2.2 GiB | ~36s | 3/5 | ✅ |
| `qwen2.5:3b` | 1.9 GiB | ~85s | 3/5 | ✅ |

**Tier 3 — Viável em produção, requer validação em EKS**

| Modelo | RAM necessária | Latência | Qualidade RCA | Situação |
|---|---|---|:---:|---|
| `mistral:7b-instruct-q4_K_M` | 4.5 GiB livres | ~84s | **4/5** | Bloqueado por RAM no lab (VM 8 GiB). Em node EKS ≥ 12 GiB é viável. **Candidato preferencial para produção.** |

> **Nota metodológica:** `mistral:7b` não foi eliminado — foi bloqueado por uma limitação de hardware local que não existe em produção. Eliminar definitivamente por esse motivo seria um erro metodológico.

### Amostras de ai_rca por modelo (com controles aplicados)

**gemma2:2b — OOMKilled**
```json
{
  "root_cause": "Um container no namespace aiops-lab foi encerrado por OOMKilled, indicando limite de memória não respeitado.",
  "immediate_action": "kubectl describe pod <pod-name> -n aiops-lab",
  "prevention": "Revisar e ajustar os limites de memória do container conforme o consumo real."
}
```
*Observação: responde frequentemente em português (modelo multilíngue sem restrição de idioma no prompt).*

**phi3.5:3.8b — CrashLoopBackOff**
```json
{
  "root_cause": "The alert is indicating that a pod in the aiops-lab namespace has entered CrashLoopBackOff, suggesting it might be stuck on an infinite loop.",
  "immediate_action": "kubectl logs <pod_name> -f",
  "prevention": "Implement health checks and resource limits to prevent container restart loops."
}
```

**qwen2.5:3b — OOMKilled**
```json
{
  "rootCause": "Um container foi encerrado por OOMKilled, indicando que ultrapassou o limite de memória estabelecido.",
  "immediateAction": "kubectl describe pod <pod-name> para identificar a causa e verificar os recursos alocados.",
  "prevention": "Configurar limites de memória adequados e monitorar o consumo com kubectl top pods."
}
```
*Observação: usa camelCase nos campos (rootCause, immediateAction) — requer normalização no parser downstream.*

---

## 6. Achados operacionais relevantes

### O que funciona no lab e precisa de atenção em EKS

| Achado | Impacto | Ação necessária |
|---|---|---|
| `OLLAMA_KEEP_ALIVE=-1` resolve cold start | Crítico — sem isso, primeiro alerta após inatividade falha | Confirmar que a env var persiste no deployment EKS |
| `format:json` garante saída estruturada | Alto — sem ele, qualquer modelo adiciona markdown | Já no workflow; manter em qualquer troca de modelo |
| Provider Ollama perde estado em restart do Keep backend | Médio | Já mitigado via Secret k8s; confirmar em produção |
| Contato point Grafana precisa ser provisionado via arquivo | Médio | Já feito via `contactpoints.yaml`; documentado |
| Port-forward não sobrevive a restart de pod | Baixo (lab only) | Em EKS, usar Service + Ingress ou LoadBalancer |

### Limitação conhecida do Keep (contexto do LLM)

O workflow recebe apenas o payload do alerta Grafana (`name`, `description`, `severity`). O LLM não acessa a API k8s diretamente — por isso o RCA é genérico em cenários onde o contexto do pod seria determinante (ex: CrashLoop com `exit 1` específico, Readiness com path incorreto).

**Solução para produção:** adicionar um step `kubernetes` provider antes do LLM para coletar `kubectl describe pod` e injetar no prompt. Isso eliminaria a limitação e elevaria a qualidade do RCA.

---

## 7. Recomendação

### Principal: Keep como plataforma AIOps central

Deploy imediato via GMUD padrão (Tier A). Encaixe direto no fluxo Grafana→Teams existente.

**Modelo LLM para go-live:** `phi3.5:3.8b` (validado no lab) com validação de `mistral:7b` em EKS antes de definir o modelo de produção.

### Complementar: K8sGPT como radar de detecção precoce

Condicionado à aprovação do cliente para recursos Tier B (CRD + ClusterRole). Valor: detecção 24–49s antes do Grafana disparar, com contexto k8s mais rico.

### HolmesGPT: não recomendado neste contexto

Reconsiderar somente se o cliente aprovar LLM hospedado em nuvem — o que viola o gate de custo zero.

---

## 8. Próximos passos

| Prioridade | Ação | Dependência |
|---|---|---|
| 🔴 Alta | Confirmar `StorageClass` em produção com time de infra | EKS |
| 🔴 Alta | Definir URL do webhook Teams para o contact point | Cliente |
| 🔴 Alta | Validar `mistral:7b` em node EKS ≥ 12 GiB | EKS |
| 🟡 Média | Estender workflow com step `kubectl describe` antes do LLM | Lab → EKS |
| 🟡 Média | Avaliar aprovação Tier B para K8sGPT junto ao cliente | Cliente |
| 🟢 Baixa | Migrar regras de alerta Grafana para IaC/Terraform | Backlog |
| 🟢 Baixa | Adapter CloudEvents→Keep se K8sGPT for aprovado | Backlog |

---

## 9. Perguntas antecipadas

**"Por que não usar o mistral:7b, que teve a melhor qualidade?"**
> Foi o modelo de maior qualidade testado (4/5). Não foi eliminado — foi bloqueado por limitação de hardware local (VM 8 GiB). Em produção com node ≥ 12 GiB é o candidato preferencial. Validação em EKS está no roadmap imediato.

**"O Keep não é muito jovem para produção?"**
> É o candidato mais jovem testado (maturidade 2/5). Os bugs encontrados foram todos resolvidos ou mitigados. O risco é gerenciável com: versão pinada, configuração via provisioning (não via UI), e monitoramento do estado do provider Ollama pós-restart.

**"O K8sGPT não seria suficiente sozinho?"**
> Não. K8sGPT não tem integração com Grafana ou Teams, não gerencia ciclo de vida de alertas e requer aprovação Tier B. Seria uma camada paralela desconectada do fluxo de resposta. O valor dele é como **complemento** ao Keep, não como substituto.

**"O score 3.5 do Keep é bom?"**
> Dado o contexto — CPU-only, sem egress, Tier A puro, integração nativa com o stack existente — sim. O limitador de score é a qualidade do RCA com contexto restrito (payload Grafana sem acesso à API k8s), que é resolvível com uma extensão do workflow já identificada.
