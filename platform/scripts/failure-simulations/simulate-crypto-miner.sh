#!/bin/bash
# simulate-crypto-miner.sh - Trigger Falco alerts by simulating crypto-mining activity
set -euo pipefail

NAMESPACE="${1:-default}"
POD_NAME="${2:-cryptominer-simulator}"
POOL_DOMAIN="${3:-pool.supportxmr.com}"
POOL_PORT="${4:-3333}"

echo "Creating crypto miner simulation pod '$POD_NAME' in namespace '$NAMESPACE'"
echo "Simulated mining pool: $POOL_DOMAIN:$POOL_PORT"
echo ""
echo "WARNING: This will trigger Falco and runtime security monitoring alerts."
echo "Run in a dedicated test namespace, not production."
echo ""

kubectl run "$POD_NAME" \
    --image=alpine:latest \
    --namespace="$NAMESPACE" \
    --labels="app=cryptominer-simulator,security-test=true,simulation-type=crypto-miner" \
    --restart=Never \
    -- /bin/sh -c "
echo 'Starting crypto mining simulation...'

# Simulate network connection to a known mining pool (Stratum protocol)
echo 'Connecting to stratum pool...'
nc -w 2 $POOL_DOMAIN $POOL_PORT 2>/dev/null || true

# Rename a harmless process to 'xmrig' to trigger process-name based detection
echo 'Simulating xmrig execution...'
cp /bin/sleep /tmp/xmrig
/tmp/xmrig 10 &
XMRIG_PID=\$!

# Simulate high CPU load associated with mining activity
echo 'Simulating high CPU workload...'
for i in 1 2; do
    dd if=/dev/urandom of=/dev/null bs=1M count=100 &
done
sleep 5

kill \$XMRIG_PID 2>/dev/null || true
echo 'Crypto miner simulation complete. This pod will now exit.'
echo 'Check Falco logs for: Cryptominer detected'
"

echo ""
echo "Waiting for pod to start..."
sleep 5

kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=20 2>/dev/null || true

echo ""
echo "Crypto miner simulation complete. Expected security alerts:"
echo " - Falco: 'Crypto miner detected' (rule: Detect Cryptocurrency Mining Activity)"
echo " - Falco: 'Miner domain resolved' (rule: Miner Pool Network Connection)"
echo " - Prometheus: 'High CPU utilization alert' (if runtime CPU is sustained)"
echo ""
echo "Verify alerts:"
echo "  kubectl logs -n security -l app=falco --tail=50 | grep -i 'miner\|xmrig'"
echo ""
echo "Cleanup: kubectl delete pod $POD_NAME --namespace=$NAMESPACE --force --grace-period=0"
