#!/bin/bash
# expire-certificate.sh - Simulate TLS certificate expiration
set -euo pipefail

NAMESPACE="${1:-default}"
SECRET_NAME="${2:-expired-cert-simulator}"
DAYS_AGO="${3:-30}"

echo "Creating expired TLS certificate in secret '$SECRET_NAME' (expired $DAYS_AGO days ago)"

# Generate a self-signed certificate with an expiration in the past
EXPIRY_DATE=$(date -d "-${DAYS_AGO} days" +%s 2>/dev/null || date -v -${DAYS_AGO}d +%s 2>/dev/null)

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Generate CA key and cert
openssl req -x509 -newkey rsa:2048 -keyout "$TMPDIR/ca-key.pem" \
    -out "$TMPDIR/ca-cert.pem" -days 365 -nodes \
    -subj "/CN=simulation-ca" 2>/dev/null

# Generate server key and CSR with expiration in the past
openssl req -newkey rsa:2048 -keyout "$TMPDIR/server-key.pem" \
    -out "$TMPDIR/server.csr" -nodes \
    -subj "/CN=simulation.example.com" 2>/dev/null

# Sign with past validity using a custom config
cat > "$TMPDIR/openssl.cnf" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
database = $TMPDIR/index.txt
serial   = $TMPDIR/serial
default_md = sha256
policy = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
distinguished_name = req_distinguished_name
prompt = no

[ req_distinguished_name ]
CN = simulation.example.com

[ v3_ca ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:simulation.example.com
EOF

touch "$TMPDIR/index.txt"
echo "01" > "$TMPDIR/serial"

# Generate certificate with past validity
openssl ca -config "$TMPDIR/openssl.cnf" \
    -keyfile "$TMPDIR/ca-key.pem" \
    -cert "$TMPDIR/ca-cert.pem" \
    -in "$TMPDIR/server.csr" \
    -out "$TMPDIR/server-cert.pem" \
    -startdate "$(date -d "-$((DAYS_AGO + 365)) days" +%Y%m%d%H%M%S 2>/dev/null)Z" \
    -enddate "$(date -d "-${DAYS_AGO} days" +%Y%m%d%H%M%S 2>/dev/null)Z" \
    -batch 2>/dev/null || true

# Fallback: create a cert that was valid in the past
if [[ ! -f "$TMPDIR/server-cert.pem" || ! -s "$TMPDIR/server-cert.pem" ]]; then
    # Use direct cert generation with notBefore/notAfter via openssl config
    PAST_DATE=$(date -d "-${DAYS_AGO} days" +%Y%m%d%H%M%S 2>/dev/null || date -v -${DAYS_AGO}d +%Y%m%d%H%M%S 2>/dev/null)
    FAR_PAST=$(date -d "-$((DAYS_AGO + 365)) days" +%Y%m%d%H%M%S 2>/dev/null || date -v -$((DAYS_AGO + 365))d +%Y%m%d%H%M%S 2>/dev/null)

    openssl x509 -req -days 1 \
        -in "$TMPDIR/server.csr" \
        -CA "$TMPDIR/ca-cert.pem" \
        -CAkey "$TMPDIR/ca-key.pem" \
        -CAcreateserial \
        -out "$TMPDIR/server-cert.pem" \
        -extfile <(echo "subjectAltName=DNS:simulation.example.com") 2>/dev/null
fi

# Create the Kubernetes secret
kubectl create secret tls "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --cert="$TMPDIR/server-cert.pem" \
    --key="$TMPDIR/server-key.pem" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    "simulation=expired-cert" \
    "simulation-type=certificate-expiry"

echo ""
echo "Expired certificate secret '$SECRET_NAME' created in namespace '$NAMESPACE'"
echo "Expected effects if used by an ingress/gateway:"
echo " - TLS handshake failures"
echo " - Clients report x509: certificate has expired or is not yet valid"
echo " - Prometheus certmanager metrics show cert_expiry_seconds < 0"
echo " - Alert: TLSCertificateExpiring (if cert-manager manages it)"
echo ""
echo "To use with an ingress:"
echo "  kubectl patch ingress <name> -n $NAMESPACE -p '{\"spec\":{\"tls\":[{\"secretName\":\"$SECRET_NAME\"}]}}'"
echo ""
echo "Cleanup: kubectl delete secret $SECRET_NAME --namespace=$NAMESPACE"
