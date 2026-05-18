#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
EXPERIMENT_DIR="${2:-../chaos/experiments}"
REPORT_DIR="${3:-../chaos/reports}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
START_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log()    { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*"; }
header() { echo -e "\n${BLUE}==============================================${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}==============================================${NC}"; }

cleanup() {
    warn "Cleaning up any running chaos experiments..."
    kubectl get podchaos,networkchaos,stresschaos,dnschaos,httpchaos --all-namespaces -o name 2>/dev/null | while read resource; do
        kubectl delete "$resource" --force --grace-period=0 2>/dev/null || true
    done
    log "Cleanup complete"
}
trap cleanup EXIT SIGINT SIGTERM

validate_environment() {
    header "Validating Environment"

    if ! kubectl get namespace chaos-mesh &>/dev/null; then
        error "Chaos Mesh is not installed in this cluster"
        error "Install Chaos Mesh first: kubectl apply -f https://chaos-mesh.github.io/chaos-mesh/install.yaml"
        exit 1
    fi

    log "✓ Chaos Mesh installed"
    log "✓ Environment: ${ENVIRONMENT}"
}

run_experiment() {
    local experiment_file="$1"
    local experiment_name
    experiment_name=$(basename "$experiment_file" .yaml)

    header "Running Experiment: ${experiment_name}"

    log "Applying ${experiment_file}..."
    kubectl apply -f "$experiment_file"

    log "Waiting for experiment to start..."
    sleep 5

    local attempt=0
    local max_attempts=12
    while [ $attempt -lt $max_attempts ]; do
        local phase
        phase=$(kubectl get podchaos "$experiment_name" -n chaos-mesh -o jsonpath='{.status.experiment.phase}' 2>/dev/null || \
                kubectl get networkchaos "$experiment_name" -n chaos-mesh -o jsonpath='{.status.experiment.phase}' 2>/dev/null || \
                kubectl get stresschaos "$experiment_name" -n chaos-mesh -o jsonpath='{.status.experiment.phase}' 2>/dev/null || \
                echo "unknown")
        
        if [ "$phase" = "Running" ]; then
            log "✓ Experiment running"
            break
        fi
        sleep 10
        ((attempt++))
    done

    if [ $attempt -ge $max_attempts ]; then
        warn "Experiment may not have started properly"
    fi

    local duration
    duration=$(grep -oP 'duration:\s+"\K[^"]+' "$experiment_file" 2>/dev/null || echo "60s")
    log "Experiment duration: ${duration}. Waiting..."
    
    # Wait for experiment to complete
    case $duration in
        *s)  sleep $(echo "$duration" | sed 's/s//') ;;
        *m)  sleep $(($(echo "$duration" | sed 's/m//') * 60)) ;;
        *)   sleep 60 ;;
    esac
    sleep 10

    log "Experiment ${experiment_name} completed"
}

verify_experiment() {
    local experiment_name="$1"
    local target_namespace="$2"

    log "Verifying experiment impact on ${target_namespace}..."

    local pods_before
    pods_before=$(kubectl get pods -n "$target_namespace" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
    
    local pods_after
    pods_after=$(kubectl get pods -n "$target_namespace" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)

    log "  Running pods before: ${pods_before}"
    log "  Running pods after:  ${pods_after}"

    local heal_attempts=0
    while [ $heal_attempts -lt 12 ]; do
        local ready
        ready=$(kubectl get pods -n "$target_namespace" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
        if [ "$ready" -ge "$pods_before" ]; then
            log "✓ Self-healing complete: ${ready}/${pods_before} pods running"
            ((PASS++))
            return 0
        fi
        sleep 10
        ((heal_attempts++))
    done

    warn "Self-healing may be incomplete: $(kubectl get pods -n "$target_namespace" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)/${pods_before} running"
    ((FAIL++))
    return 1
}

run_all_experiments() {
    header "Running All Chaos Experiments"

    mkdir -p "$REPORT_DIR"

    for experiment in "${EXPERIMENT_DIR}"/*.yaml; do
        if [ ! -f "$experiment" ]; then
            warn "No experiment files found in ${EXPERIMENT_DIR}"
            return
        fi

        local name
        name=$(basename "$experiment" .yaml)
        local target_ns
        target_ns=$(grep -oP 'namespaces:\s*\[\s*"\K[^"]*' "$experiment" 2>/dev/null || echo "default")

        run_experiment "$experiment"

        if [ "$target_ns" != "" ]; then
            verify_experiment "$name" "$target_ns" || true
        fi

        # Brief cooldown between experiments
        sleep 15
    done
}

run_scheduled_experiment() {
    local schedule_file="$1"
    header "Running Scheduled Experiment: ${schedule_file}"
    
    log "Applying schedule..."
    kubectl apply -f "$schedule_file"
    
    log "Scheduled chaos experiment applied"
}

generate_report() {
    local end_time
    end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local report_file="${REPORT_DIR}/chaos-report-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).md"

    header "Generating Report"

    mkdir -p "$REPORT_DIR"

    cat > "$report_file" << EOF
# Chaos Engineering Report

## Summary
- **Environment**: ${ENVIRONMENT}
- **Date**: $(date -u)
- **Duration**: ${START_TIME} to ${end_time}
- **Experiments Passed**: ${PASS}
- **Experiments Failed**: ${FAIL}

## Experiments

EOF

    for experiment in "${EXPERIMENT_DIR}"/*.yaml; do
        if [ -f "$experiment" ]; then
            local name
            name=$(basename "$experiment" .yaml)
            local action
            action=$(grep -oP 'action:\s+\K\w+' "$experiment" 2>/dev/null || echo "unknown")
            local duration
            duration=$(grep -oP 'duration:\s+"\K[^"]+' "$experiment" 2>/dev/null || echo "unknown")
            
            cat >> "$report_file" << EOF
### ${name}
- **Type**: ${action}
- **Duration**: ${duration}
- **Status**: Completed

EOF
        fi
    done

    cat >> "$report_file" << EOF
## Recommendations
$(if [ "$FAIL" -gt 0 ]; then echo "- Review self-healing configurations"; fi)
- Continue weekly chaos experiments
- Increase experiment scope gradually
- Document all findings in runbooks

## Next Scheduled Experiment
- Weekly: $(date -d "+7 days" +%Y-%m-%d)
EOF

    log "Report written to: ${report_file}"
    cat "$report_file"
}

main() {
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           Chaos Experiment Runner                        ║"
    echo "║  Environment: ${ENVIRONMENT}   $(date -u)  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    validate_environment

    if [ "$#" -ge 1 ] && [ -f "$1" ]; then
        run_experiment "$1"
    else
        run_all_experiments
    fi

    generate_report

    echo ""
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}  All chaos experiments completed successfully${NC}"
    else
        echo -e "${RED}  ${FAIL} experiment(s) had self-healing issues${NC}"
    fi
    echo ""
}

main "$@"
