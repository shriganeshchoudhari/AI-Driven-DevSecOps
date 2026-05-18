#!/bin/bash
# create-traffic-spike.sh - Generate high load on a target service
# Triggers: HPA scaling, latency increase, potential rate limiting
set -euo pipefail

SERVICE_URL="${1:-http://frontend-service.frontend-service:8080}"
DURATION="${2:-120}"
RATE="${3:-200}"

echo "=== Traffic Spike Generator ==="
echo "Target: $SERVICE_URL"
echo "Duration: ${DURATION}s"
echo "Target Rate: ${RATE} RPS"
echo ""

check_tool() {
    if command -v hey &>/dev/null; then
        echo "Using 'hey' for load generation"
        hey -z "${DURATION}s" -q "$RATE" -c 50 \
            -H "Content-Type: application/json" \
            "$SERVICE_URL/api/v1/users/1"
    elif command -v wrk &>/dev/null; then
        echo "Using 'wrk' for load generation"
        wrk -t4 -c100 -d"${DURATION}s" \
            -H "Content-Type: application/json" \
            "$SERVICE_URL/api/v1/users/1"
    elif command -v ab &>/dev/null; then
        echo "Using 'ab' for load generation"
        ab -n $((RATE * DURATION)) -c 50 \
            "$SERVICE_URL/api/v1/users/1"
    else
        echo "No load testing tool found. Installing 'hey'..."
        if command -v apk &>/dev/null; then
            apk add hey
        elif command -v apt-get &>/dev/null; then
            echo "Please install: apt-get install -y hey"
            exit 1
        else
            echo "Please install hey, wrk, or ab"
            exit 1
        fi
        $0 "$SERVICE_URL" "$DURATION" "$RATE"
    fi
}

check_tool

echo ""
echo "=== Traffic spike complete ==="
echo ""
echo "Check Grafana dashboards for:"
echo "  1. Request rate spike (RPS graph)"
echo "  2. P50/P95/P99 latency changes"
echo "  3. Error rate (4xx/5xx responses)"
echo "  4. HPA scaling events"
echo "  5. Pod autoscaling behavior"
echo "  6. Resource utilization changes"
