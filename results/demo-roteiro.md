# Roteiro de Demonstração ao Vivo — AIOps Bake-off

**Duração estimada:** 20–30 minutos  
**Audiência:** Time técnico + cliente (setor financeiro)  
**Ambiente:** Cluster Kind local (WSL2) — espelha a arquitetura EKS de produção  
**Pré-requisito:** todas as seções do § "Checklist pré-demo" concluídas

---

## Narrativa

> "Hoje vamos mostrar como Keep transforma alertas ruidosos em diagnósticos acionáveis,
> e como K8sGPT age como radar de detecção precoce antes mesmo do Grafana disparar."

A demo segue o ciclo real de um incidente:  
**falha injetada → alerta gerado → enriquecimento por IA → diagnóstico disponível para o SRE**

---

## Checklist pré-demo (executar 10 min antes)

```bash
# 1. Verificar cluster e pods
kubectl get nodes
kubectl get pods -n aiops-lab

# 2. Subir todos os port-forwards de uma vez
make pf
# Saída esperada: URLs de Keep frontend (:3001), Keep API (:8081), Grafana (:3000), Prometheus (:9091)

# 3. Confirmar modelo ativo no workflow (deve ser phi3.5:3.8b)
grep "model:" config/keep/workflows/ollama-grafana-alert-enrichment.yaml

# 4. Confirmar que o Ollama já tem o modelo carregado (KEEP_ALIVE=-1 garante isso)
curl -s http://localhost:11436/api/tags | python3 -c "
import json,sys; models=json.load(sys.stdin)['models']
print([m['name'] for m in models])"

# 5. Verificar Ollama provider no Keep
curl -s http://localhost:8081/providers \
  -H "X-API-KEY: keepappkey" | python3 -c "
import json,sys; providers=json.load(sys.stdin)
print([(p['type'],p.get('installed')) for p in providers if p['type']=='ollama'])"

# 6. Verificar K8sGPT
kubectl get k8sgpt k8sgpt-lab -n aiops-lab -o jsonpath='{.status.conditions[0]}' | python3 -m json.tool

# 7. Garantir workload-vítima saudável (sem falhas ativas)
kubectl get pods -n aiops-lab -l app=workload-vitima

# 8. Abrir abas no browser antes de começar
#    - Keep dashboard:   http://localhost:3001
#    - Grafana:          http://localhost:3000  (admin/admin)
#    - Grafana Alerting: http://localhost:3000/alerting/list
```

---

## Ato 1 — Apresentação do ambiente (3–4 min)

### 1.1 Mostrar o stack no terminal

```bash
kubectl get pods -n aiops-lab -o wide
```

**Fala:** "Este é o namespace `aiops-lab`. Temos o Prometheus coletando métricas,
o Grafana avaliando regras de alerta, o Ollama rodando o modelo `phi3.5:3.8b` em CPU puro
— sem GPU, sem chamada de API externa — e o Keep como hub central de alertas."

### 1.2 Mostrar o fluxo no quadro

```
Prometheus → Grafana Alerting → Keep (webhook) → Ollama LLM → ai_rca no alerta → Teams
```

**Fala:** "Esse é o fluxo de produção do cliente. Keep é o elo que falta no meio.
Não é uma camada nova — é o conector entre o alerting que já existe e o SRE de plantão."

### 1.3 Mostrar o Keep vazio (sem alertas ativos)

Abrir http://localhost:3001 → aba "Alerts" → mostrar 0 alertas ativos.

---

## Ato 2 — Cenário 1: OOMKilled (8–10 min)

> **Por que OOMKill?** É o cenário mais impactante para o cliente: pod morto sem log claro,
> diagnóstico exige correlação de métricas de memória — exatamente o que o LLM resolve.

### 2.1 Injetar a falha

```bash
bash scenarios/02-oomkilled.sh
```

**Fala:** "Vou simular um vazamento de memória na workload-vítima.
O container vai ultrapassar o `memory limit` e o Kubernetes vai matá-lo com OOMKilled."

### 2.2 Observar no K8sGPT (terminal — 24–49s)

```bash
# Aguardar ~30–60s e verificar findings
watch -n 5 "kubectl get results -n aiops-lab -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.details}\n{end}' 2>/dev/null || kubectl get k8sgpt k8sgpt-lab -n aiops-lab -o jsonpath='{.status}'"
```

**Fala:** "O K8sGPT já detectou — em menos de um minuto. Ele acessou diretamente a API
do Kubernetes e identificou `OOMKilled` com sugestão de ajustar `resources.limits`."

Mostrar o finding no terminal:
```bash
kubectl get results -n aiops-lab -o yaml | head -60
```

### 2.3 Observar no Grafana (~1–2 min)

Abrir http://localhost:3000/alerting/list → aguardar regra `OOMKilled` entrar em estado `Firing`.

**Fala:** "Enquanto isso o Grafana percebeu o padrão: o pod reiniciou com `reason=OOMKilled`.
Agora ele vai disparar o webhook para o Keep."

### 2.4 Observar no Keep (ai_rca em ~4–5 min total)

Abrir http://localhost:3001 → aba "Alerts" → clicar no alerta quando aparecer.

**Fala:** "O Keep recebeu o alerta. O workflow disparou uma chamada ao Ollama.
Aqui está o campo `ai_rca` — diagnóstico gerado localmente, em CPU, sem sair da rede."

Mostrar o campo `ai_rca` no detalhe do alerta:
```bash
# Confirmar via API também
curl -s http://localhost:8081/alerts \
  -H "X-API-KEY: keepappkey" | \
  jq '.[] | select(.name | test("OOM|oom"; "i")) | {name, ai_rca: .enriched_fields}'
```

### 2.5 Reverter

```bash
bash scenarios/02-oomkilled.sh --revert
```

**Ponto de discussão:**
- K8sGPT: 24–49s, contexto k8s rico, Tier B (CRD + ClusterRole)
- Keep: 4–5 min, gestão de ciclo de vida, Tier A (100% namespaced, sem aprovação adicional)

---

## Ato 3 — Cenário 2: CrashLoopBackOff (5–7 min)

> **Opcional se o tempo estiver curto.** Use como segundo cenário para mostrar cobertura.

### 3.1 Injetar

```bash
bash scenarios/01-crashloopbackoff.sh
```

### 3.2 Observar K8sGPT

```bash
watch -n 5 "kubectl get results -n aiops-lab -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.details}\n{end}' 2>/dev/null"
```

### 3.3 Observar Keep

Abrir dashboard → aguardar alerta `CrashLoopBackOff` + campo `ai_rca`.

**Fala comparativa:** "Neste cenário K8sGPT identificou `last termination reason is Error`
mas sem o exit code. O Keep chegou com mais contexto textual do Grafana mas também sem
o código de saída — limitação do payload de alerta. Os dois se complementam: K8sGPT
tem o contexto da API; Keep tem a gestão do incidente."

### 3.4 Reverter

```bash
bash scenarios/01-crashloopbackoff.sh --revert
```

---

## Ato 4 — Comparativo lado a lado (3–4 min)

Apresentar a tabela na tela (copiar de `results/scoring-matrix.md`):

| Dimensão | K8sGPT | Keep |
|---|---|---|
| Velocidade de detecção | **24–49s** | 33s–4m+ |
| Contexto k8s | API direta (tag, reason, exit code) | Payload Grafana |
| Gestão de alertas | Só CR | Dedup, fingerprint, histórico |
| Notificação Teams | Não | Sim (contact point nativo) |
| Tier de deploy | **Tier B** (aprovação cliente) | **Tier A** (GMUD padrão) |
| Score ponderado | 3.1 / 5 | **3.5 / 5** |

**Fala:** "Não é uma disputa — é complementaridade. Keep é o elo que fecha o fluxo
existente. K8sGPT é o radar que detecta antes do Grafana disparar.
A recomendação é: Keep como plataforma central agora, K8sGPT como ferramenta complementar
condicionada à aprovação Tier B pelo cliente."

---

## Ato 5 — ADR e próximos passos (2–3 min)

Abrir `results/ADR-001-aiops-platform.md` no editor ou mostrar o PDF.

**Próximos passos concretos:**
1. Confirmar nome da `StorageClass` em produção → substituir placeholder nos values
2. Definir URL do webhook do Teams para o contact point do Keep
3. Validar cota do namespace no EKS (~2 GiB RAM adicionais para o Keep)
4. Decidir com o cliente: aprovar Tier B para K8sGPT ou usar CLI on-demand?

---

## Comandos de emergência (se algo travar durante a demo)

```bash
# Resetar workload-vítima para saudável
kubectl rollout undo deployment/workload-vitima -n aiops-lab
kubectl set image deployment/workload-vitima workload-vitima=nginxinc/nginx-unprivileged:1.27 -n aiops-lab

# Forçar K8sGPT a re-analisar
kubectl annotate k8sgpt k8sgpt-lab -n aiops-lab force-reconcile=$(date +%s) --overwrite

# Reiniciar backend Keep (se travar)
kubectl rollout restart deployment/keep-backend -n aiops-lab

# Listar alertas ativos no Keep
curl -s http://localhost:8081/alerts -H "X-API-KEY: keepappkey" | jq '[.[] | {name, status, ai_rca: .enriched_fields}]'

# Ver execuções de workflow
curl -s http://localhost:8081/workflows/60cbcfc1-2605-426b-9512-d5d4d338aebe/runs \
  -H "X-API-KEY: keepappkey" | jq '[.[] | {id, status, execution_time}]' | head -30
```

---

## Pós-demo — checklist de limpeza

```bash
# Garantir que não há falhas ativas
kubectl get pods -n aiops-lab -l app=workload-vitima

# Matar port-forwards
pkill -f "kubectl port-forward"
```
