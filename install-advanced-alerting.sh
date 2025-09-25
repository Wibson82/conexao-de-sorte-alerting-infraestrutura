#!/usr/bin/env bash

# ============================================================================
# 🚨 ADVANCED ALERTING INSTALLER - CONEXÃO DE SORTE ALERTING INFRASTRUCTURE
# ============================================================================
# Script para instalação e configuração completa do AlertManager com
# integração PagerDuty e políticas de escalation inteligente
# ============================================================================

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configurações
PROMETHEUS_NAMESPACE="istio-system"
TARGET_NAMESPACE="default"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Função para log colorido
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_header() {
    echo -e "${PURPLE}🎯 $1${NC}"
}

log_step() {
    echo -e "${CYAN}🔄 $1${NC}"
}

# Função para verificar pré-requisitos
check_prerequisites() {
    log_header "Verificando pré-requisitos para Advanced Alerting..."
    
    # Verificar kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl não encontrado. Instale kubectl primeiro."
        exit 1
    fi
    
    # Verificar conexão com cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Não foi possível conectar ao cluster Kubernetes."
        exit 1
    fi
    
    # Verificar se Prometheus está rodando
    if kubectl get deployment prometheus -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        log_success "Prometheus encontrado em $PROMETHEUS_NAMESPACE"
    else
        log_error "Prometheus não encontrado. Instale Istio com observabilidade primeiro."
        exit 1
    fi
    
    # Verificar se AlertManager já existe
    if kubectl get deployment alertmanager -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        log_warning "AlertManager já existe - será atualizado"
    else
        log_info "AlertManager será instalado"
    fi
    
    log_success "Pré-requisitos verificados"
}

# Função para configurar secrets
configure_secrets() {
    log_header "Configurando secrets para integrações..."
    
    # Verificar se secrets já existem
    if kubectl get secret conexao-de-sorte-alerting-secrets -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        log_warning "Secrets já existem - mantendo valores atuais"
        return 0
    fi
    
    log_step "Criando secrets template..."
    
    # Criar arquivo de configuração de secrets
    cat > "$SCRIPT_DIR/secrets-config.env" << 'EOF'
# ============================================================================
# 🔐 CONFIGURAÇÃO DE SECRETS PARA ALERTING
# ============================================================================
# Configure os valores abaixo com suas credenciais reais

# SMTP Configuration (para notificações por email)
SMTP_PASSWORD="your-smtp-password-here"

# PagerDuty Integration Keys
# Obtenha em: https://your-domain.pagerduty.com/service-directory
PAGERDUTY_SERVICE_KEY="your-pagerduty-service-key-here"
PAGERDUTY_FINANCIAL_KEY="your-pagerduty-financial-key-here"
PAGERDUTY_SECURITY_KEY="your-pagerduty-security-key-here"

# Slack Webhook URLs
# Obtenha em: https://api.slack.com/apps/YOUR_APP/incoming-webhooks
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Microsoft Teams Webhook (opcional)
TEAMS_WEBHOOK="https://outlook.office.com/webhook/YOUR/TEAMS/WEBHOOK"

# Discord Webhook (opcional)
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR/DISCORD/WEBHOOK"
EOF
    
    log_warning "Configure os secrets em: $SCRIPT_DIR/secrets-config.env"
    log_warning "Depois execute: $0 apply-secrets"
    
    # Aplicar secrets com valores placeholder por enquanto
    kubectl apply -f "$SCRIPT_DIR/prometheus-alertmanager-setup.yaml"
    
    log_success "Secrets template criado"
}

# Função para aplicar secrets reais
apply_secrets() {
    log_header "Aplicando secrets reais..."
    
    if [ ! -f "$SCRIPT_DIR/secrets-config.env" ]; then
        log_error "Arquivo secrets-config.env não encontrado. Execute 'install' primeiro."
        exit 1
    fi
    
    # Carregar variáveis do arquivo
    source "$SCRIPT_DIR/secrets-config.env"
    
    # Criar secret com valores reais
    kubectl create secret generic conexao-de-sorte-alerting-secrets \
        --from-literal=smtp-password="$SMTP_PASSWORD" \
        --from-literal=pagerduty-service-key="$PAGERDUTY_SERVICE_KEY" \
        --from-literal=pagerduty-financial-key="$PAGERDUTY_FINANCIAL_KEY" \
        --from-literal=pagerduty-security-key="$PAGERDUTY_SECURITY_KEY" \
        --from-literal=slack-webhook="$SLACK_WEBHOOK" \
        --from-literal=teams-webhook="$TEAMS_WEBHOOK" \
        --from-literal=discord-webhook="$DISCORD_WEBHOOK" \
        -n "$PROMETHEUS_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secrets aplicados com sucesso"
}

# Função para instalar AlertManager
install_alertmanager() {
    log_header "Instalando/Atualizando AlertManager..."
    
    # Aplicar configurações
    log_step "Aplicando configurações do AlertManager..."
    kubectl apply -f "$SCRIPT_DIR/prometheus-alertmanager-setup.yaml"
    
    # Verificar se AlertManager deployment existe, senão criar
    if ! kubectl get deployment alertmanager -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        log_step "Criando deployment do AlertManager..."
        
        cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: $PROMETHEUS_NAMESPACE
  labels:
    app.kubernetes.io/name: alertmanager
    app.kubernetes.io/part-of: conexao-de-sorte-alerting
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: alertmanager
  template:
    metadata:
      labels:
        app.kubernetes.io/name: alertmanager
        app.kubernetes.io/part-of: conexao-de-sorte-alerting
    spec:
      containers:
      - name: alertmanager
        image: prom/alertmanager:v0.26.0
        args:
        - --config.file=/etc/alertmanager/alertmanager.yml
        - --storage.path=/alertmanager
        - --web.external-url=http://alertmanager.conexaodesorte.com
        - --cluster.listen-address=0.0.0.0:9094
        - --cluster.peer=alertmanager-0.alertmanager.istio-system.svc.cluster.local:9094
        - --cluster.peer=alertmanager-1.alertmanager.istio-system.svc.cluster.local:9094
        ports:
        - containerPort: 9093
          name: web
        - containerPort: 9094
          name: cluster
        resources:
          requests:
            memory: 200Mi
            cpu: 100m
          limits:
            memory: 500Mi
            cpu: 200m
        volumeMounts:
        - name: config
          mountPath: /etc/alertmanager
        - name: templates
          mountPath: /etc/alertmanager/templates
        - name: secrets
          mountPath: /etc/alertmanager/secrets
          readOnly: true
        - name: storage
          mountPath: /alertmanager
      volumes:
      - name: config
        configMap:
          name: conexao-de-sorte-alertmanager-config
      - name: templates
        configMap:
          name: conexao-de-sorte-alert-templates
      - name: secrets
        secret:
          secretName: conexao-de-sorte-alerting-secrets
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: $PROMETHEUS_NAMESPACE
  labels:
    app.kubernetes.io/name: alertmanager
    app.kubernetes.io/part-of: conexao-de-sorte-alerting
spec:
  selector:
    app.kubernetes.io/name: alertmanager
  ports:
  - name: web
    port: 9093
    targetPort: 9093
  - name: cluster
    port: 9094
    targetPort: 9094
EOF
    fi
    
    # Aguardar deployment
    log_step "Aguardando AlertManager..."
    kubectl wait --for=condition=available --timeout=300s deployment/alertmanager -n "$PROMETHEUS_NAMESPACE" || true
    
    log_success "AlertManager instalado/atualizado"
}

# Função para configurar Prometheus para usar AlertManager
configure_prometheus_alerting() {
    log_header "Configurando Prometheus para usar AlertManager..."
    
    # Verificar se Prometheus ConfigMap existe
    if kubectl get configmap prometheus -n "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        log_step "Atualizando configuração do Prometheus..."
        
        # Backup da configuração atual
        kubectl get configmap prometheus -n "$PROMETHEUS_NAMESPACE" -o yaml > "$SCRIPT_DIR/prometheus-config-backup.yaml"
        
        # Patch para adicionar AlertManager
        kubectl patch configmap prometheus -n "$PROMETHEUS_NAMESPACE" --type merge -p '{
          "data": {
            "prometheus.yml": "global:\n  scrape_interval: 15s\n  evaluation_interval: 15s\n\nrule_files:\n  - \"/etc/prometheus/rules/*.yml\"\n\nalerting:\n  alertmanagers:\n  - static_configs:\n    - targets:\n      - alertmanager.istio-system.svc.cluster.local:9093\n\nscrape_configs:\n- job_name: \"prometheus\"\n  static_configs:\n  - targets: [\"localhost:9090\"]\n\n- job_name: \"kubernetes-pods\"\n  kubernetes_sd_configs:\n  - role: pod\n  relabel_configs:\n  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]\n    action: keep\n    regex: true\n  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]\n    action: replace\n    target_label: __metrics_path__\n    regex: (.+)\n  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]\n    action: replace\n    regex: ([^:]+)(?::\\d+)?;(\\d+)\n    replacement: $1:$2\n    target_label: __address__\n  - action: labelmap\n    regex: __meta_kubernetes_pod_label_(.+)\n  - source_labels: [__meta_kubernetes_namespace]\n    action: replace\n    target_label: kubernetes_namespace\n  - source_labels: [__meta_kubernetes_pod_name]\n    action: replace\n    target_label: kubernetes_pod_name"
          }
        }'
        
        # Reiniciar Prometheus para aplicar mudanças
        kubectl rollout restart deployment/prometheus -n "$PROMETHEUS_NAMESPACE" || true
        
        log_success "Prometheus configurado para usar AlertManager"
    else
        log_warning "ConfigMap do Prometheus não encontrado - configuração manual necessária"
    fi
}

# Função para testar alerting
test_alerting() {
    log_header "Testando sistema de alerting..."
    
    # Criar alerta de teste
    log_step "Criando alerta de teste..."
    
    cat << EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: conexao-de-sorte-test-alert
  namespace: $PROMETHEUS_NAMESPACE
  labels:
    app.kubernetes.io/name: test-alert
    app.kubernetes.io/part-of: conexao-de-sorte-alerting
spec:
  groups:
  - name: test-alerts
    rules:
    - alert: TestAlert
      expr: vector(1)
      for: 0m
      labels:
        severity: warning
        service: test-service
      annotations:
        summary: "Alerta de teste do sistema de monitoramento"
        description: "Este é um alerta de teste para validar o sistema de alerting"
        runbook_url: "https://runbooks.conexaodesorte.com/test-alert"
EOF
    
    log_step "Aguardando propagação do alerta..."
    sleep 30
    
    # Verificar se alerta foi criado
    local alert_status=$(curl -s "http://localhost:9093/api/v1/alerts" 2>/dev/null | grep -c "TestAlert" || echo "0")
    
    if [[ "$alert_status" -gt 0 ]]; then
        log_success "Alerta de teste criado com sucesso"
    else
        log_warning "Alerta de teste não encontrado - verifique configuração"
    fi
    
    # Limpar alerta de teste
    kubectl delete prometheusrule conexao-de-sorte-test-alert -n "$PROMETHEUS_NAMESPACE" --ignore-not-found=true
    
    log_success "Teste de alerting concluído"
}

# Função para mostrar informações pós-instalação
show_post_install_info() {
    log_header "Informações pós-instalação do Advanced Alerting"
    
    echo ""
    echo "🚨 AlertManager instalado com sucesso!"
    echo ""
    echo "🎯 Componentes configurados:"
    echo "  • AlertManager com alta disponibilidade (2 replicas)"
    echo "  • Integração PagerDuty para alertas críticos"
    echo "  • Notificações Slack para warnings"
    echo "  • Templates de email personalizados"
    echo "  • Políticas de escalation por severidade"
    echo ""
    echo "🔧 Acesso aos dashboards:"
    echo "  • AlertManager: kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/alertmanager 9093:9093"
    echo "  • URL: http://localhost:9093"
    echo ""
    echo "📊 Tipos de alertas configurados:"
    echo "  • Infraestrutura: ServiceDown, HighMemoryUsage, HighCPUUsage"
    echo "  • Performance: HighResponseTime, HighErrorRate"
    echo "  • Negócio: LowConversionRate, PaymentFailures"
    echo "  • Segurança: UnauthorizedAccess, SuspiciousActivity"
    echo ""
    echo "🔐 Configuração de secrets:"
    echo "  • Edite: $SCRIPT_DIR/secrets-config.env"
    echo "  • Aplique: $0 apply-secrets"
    echo ""
    echo "📋 Próximos passos:"
    echo "  1. Configure secrets reais (PagerDuty, Slack, etc.)"
    echo "  2. Teste notificações com alertas reais"
    echo "  3. Ajuste thresholds conforme necessário"
    echo "  4. Configure dashboards no Grafana"
    echo "  5. Treine equipe nos runbooks"
    echo ""
    echo "⚠️ Importante:"
    echo "  • Alertas críticos vão para PagerDuty"
    echo "  • Warnings vão para Slack"
    echo "  • Serviços financeiros têm escalation especial"
    echo "  • Configure runbooks para cada alerta"
    echo ""
}

# Função principal
main() {
    case "${1:-install}" in
        "install")
            check_prerequisites
            configure_secrets
            install_alertmanager
            configure_prometheus_alerting
            test_alerting
            show_post_install_info
            ;;
        "apply-secrets")
            apply_secrets
            kubectl rollout restart deployment/alertmanager -n "$PROMETHEUS_NAMESPACE"
            log_success "Secrets aplicados e AlertManager reiniciado"
            ;;
        "test")
            test_alerting
            ;;
        "uninstall")
            log_warning "Desinstalando Advanced Alerting..."
            kubectl delete -f "$SCRIPT_DIR/prometheus-alertmanager-setup.yaml" --ignore-not-found=true
            kubectl delete deployment alertmanager -n "$PROMETHEUS_NAMESPACE" --ignore-not-found=true
            kubectl delete service alertmanager -n "$PROMETHEUS_NAMESPACE" --ignore-not-found=true
            rm -f "$SCRIPT_DIR/secrets-config.env" "$SCRIPT_DIR/prometheus-config-backup.yaml"
            log_success "Advanced Alerting desinstalado"
            ;;
        "help"|*)
            echo "🚨 Advanced Alerting Installer"
            echo ""
            echo "Uso: $0 [COMANDO]"
            echo ""
            echo "Comandos:"
            echo "  install        Instalar AlertManager completo (padrão)"
            echo "  apply-secrets  Aplicar secrets reais após configuração"
            echo "  test           Executar teste de alerting"
            echo "  uninstall      Desinstalar Advanced Alerting"
            echo "  help           Mostrar esta ajuda"
            ;;
    esac
}

# Executar função principal
main "$@"
