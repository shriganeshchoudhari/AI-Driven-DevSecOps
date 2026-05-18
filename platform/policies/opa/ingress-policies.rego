# =============================================================================
# OPA / Conftest Policies for Kubernetes Ingress Resources
# =============================================================================

package main

import future.keywords.if
import future.keywords.in
import future.keywords.contains

# =============================================================================
# METADATA
# =============================================================================

# METADATA
# title: Allowed Ingress Annotations
# description: Only allow specific, approved annotations on Ingress resources
# severity: MEDIUM
# category: Ingress Security

# METADATA
# title: Required TLS Configuration
# description: All ingresses must have TLS configured with valid certificates
# severity: HIGH
# category: Ingress Security

# METADATA
# title: Blocked Hostnames
# description: Block ingress hostnames that match disallowed patterns
# severity: CRITICAL
# category: Ingress Security

# METADATA
# title: Required Security Headers
# description: Ingress must have security-related response headers configured
# severity: HIGH
# category: Ingress Security

# METADATA
# title: Rate Limiting Validation
# description: Ingress should have rate limiting annotations configured
# severity: LOW
# category: Ingress Security

# =============================================================================
# DENY RULES
# =============================================================================

# -----------------------------------------------------------------------------
# Policy 1: Allowed Ingress Annotations
# Only allow specific annotation prefixes on Ingress resources
# -----------------------------------------------------------------------------

# METADATA
# description: >
#   Restrict ingress annotations to an approved allowlist.
#   This prevents configuration drift and blocks potentially dangerous
#   annotations that could weaken security controls.
deny[msg] {
    input.kind == "Ingress"
    annotation := input.metadata.annotations[key]
    not startswith(key, "kubernetes.io/ingress.")
    not startswith(key, "nginx.ingress.kubernetes.io/")
    not startswith(key, "alb.ingress.kubernetes.io/")
    not startswith(key, "cert-manager.io/")
    not startswith(key, "external-dns.alpha.kubernetes.io/")
    not startswith(key, "cyber-secure/")
    not startswith(key, "prometheus.io/")
    not key == "meta.helm.sh/release-name"
    not key == "meta.helm.sh/release-namespace"

    msg := sprintf("Ingress %s has disallowed annotation: %s. Only approved annotation prefixes are allowed.", [input.metadata.name, key])
}

# -----------------------------------------------------------------------------
# Policy 2: Required TLS Configuration
# All ingresses must have TLS configured with host matching
# -----------------------------------------------------------------------------

# METADATA
# description: >
#   Every Ingress must have a TLS section that covers all exposed hosts.
#   This enforces HTTPS-only traffic and prevents unencrypted HTTP access.
deny[msg] {
    input.kind == "Ingress"
    input.spec.tls == []
    host := input.spec.rules[_].host
    not is_internal_host(host)

    msg := sprintf("Ingress %s in namespace %s does not have TLS configured. All external-facing ingresses require TLS.", [input.metadata.name, input.metadata.namespace])
}

deny[msg] {
    input.kind == "Ingress"
    tls_entry := input.spec.tls[_]
    rule := input.spec.rules[_]
    host := rule.host
    not is_internal_host(host)
    not any_tls_host_matches(tls_entry, host)

    msg := sprintf("Ingress %s has host %s that is not covered by any TLS entry.", [input.metadata.name, host])
}

deny[msg] {
    input.kind == "Ingress"
    tls_entry := input.spec.tls[_]
    not tls_entry.secretName
    host := tls_entry.hosts[_]

    msg := sprintf("Ingress %s TLS entry for host %s does not specify a secretName. A valid TLS secret must be referenced.", [input.metadata.name, host])
}

# -----------------------------------------------------------------------------
# Policy 3: Blocked Hostnames
# Block hostnames that match disallowed patterns
# -----------------------------------------------------------------------------

# METADATA
# description: >
#   Block ingress hostnames that use disallowed patterns such as
#   internal domains, IP addresses, or domains that should not be
#   exposed through the ingress controller.
deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    startswith(host, "internal.")
    not host == "internal.example.com"

    msg := sprintf("Ingress %s uses blocked hostname pattern 'internal.': %s", [input.metadata.name, host])
}

deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    regex.match(`^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$`, host)

    msg := sprintf("Ingress %s uses an IP address as hostname: %s. Hostnames must be valid DNS names.", [input.metadata.name, host])
}

deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    endswith(host, ".local")
    not endswith(host, ".svc.cluster.local")

    msg := sprintf("Ingress %s uses blocked hostname with .local suffix: %s", [input.metadata.name, host])
}

deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    contains(host, "localhost")

    msg := sprintf("Ingress %s uses localhost as hostname: %s. This is not allowed in production.", [input.metadata.name, host])
}

deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    not regex.match(`^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$`, host)

    msg := sprintf("Ingress %s has invalid hostname format: %s", [input.metadata.name, host])
}

# -----------------------------------------------------------------------------
# Policy 4: Required Security Headers
# Ingress must have security headers configured via annotations
# -----------------------------------------------------------------------------

# METADATA
# description: >
#   All ingresses must have security-related response headers configured
#   through nginx ingress annotations. This enforces HSTS, XSS protection,
#   content-type sniffing protection, and frame-options headers.
deny[msg] {
    input.kind == "Ingress"
    input.metadata.annotations
    not input.metadata.annotations["nginx.ingress.kubernetes.io/ssl-redirect"]
    not input.metadata.annotations["nginx.ingress.kubernetes.io/force-ssl-redirect"]

    msg := sprintf("Ingress %s must enable SSL redirect via annotation. Set 'nginx.ingress.kubernetes.io/ssl-redirect: \"true\"'.", [input.metadata.name])
}

deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    not is_internal_host(host)
    a := input.metadata.annotations
    not a["nginx.ingress.kubernetes.io/configuration-snippet"]
    not a["nginx.ingress.kubernetes.io/server-snippet"]

    msg := sprintf("Ingress %s must have security headers configured via 'nginx.ingress.kubernetes.io/configuration-snippet' annotation.", [input.metadata.name])
}

deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    not is_internal_host(host)
    snippet := input.metadata.annotations["nginx.ingress.kubernetes.io/configuration-snippet"]
    not contains(snippet, "Strict-Transport-Security")
    not contains(snippet, "HSTS")

    msg := sprintf("Ingress %s must include HSTS (Strict-Transport-Security) header in the configuration snippet.", [input.metadata.name])
}

deny[msg] {
    input.kind == "Ingress"
    snippet := input.metadata.annotations["nginx.ingress.kubernetes.io/configuration-snippet"]
    contains(snippet, "more_set_headers")
    contains(snippet, "Server:")
    not contains(snippet, "Server: none")

    msg := sprintf("Ingress %s: Server header should be set to 'none' or removed to avoid information disclosure.", [input.metadata.name])
}

# -----------------------------------------------------------------------------
# Policy 5: Rate Limiting Validation
# Production ingresses should have rate limiting configured
# -----------------------------------------------------------------------------

# METADATA
# description: >
#   Production ingresses should have rate limiting annotations to prevent
#   abuse and DoS attacks. This is a warning-level policy that recommends
#   rate limiting configuration but does not block deployment.
deny[msg] {
    input.kind == "Ingress"
    input.metadata.namespace != "kube-system"
    not input.metadata.annotations["nginx.ingress.kubernetes.io/limit-rps"]
    not input.metadata.annotations["nginx.ingress.kubernetes.io/limit-rpm"]
    not input.metadata.annotations["nginx.ingress.kubernetes.io/limit-connections"]

    msg := sprintf("Ingress %s should have rate limiting configured. Consider adding 'nginx.ingress.kubernetes.io/limit-rps' annotation.", [input.metadata.name])
}

# -----------------------------------------------------------------------------
# Policy 6: Block Wildcard Hostnames
# =============================================================================

# METADATA
# description: >
#   Block ingress resources that use wildcard hostnames (*.example.com)
#   as they can lead to subdomain takeover and unintended traffic routing.
#   Specific hostnames must be used for each ingress.
deny[msg] {
    input.kind == "Ingress"
    host := input.spec.rules[_].host
    startswith(host, "*.")

    msg := sprintf("Ingress %s uses wildcard hostname: %s. Specific hostnames must be used.", [input.metadata.name, host])
}

# -----------------------------------------------------------------------------
# Policy 7: Require Backend Service to Use HTTPS Port
# =============================================================================

# METADATA
# description: >
#   Backend services referenced by ingress should use HTTPS (port 443)
#   internally or have proper justification for HTTP. This enforces
#   end-to-end encryption.
deny[msg] {
    input.kind == "Ingress"
    rule := input.spec.rules[_]
    path := rule.http.paths[_]
    path.backend.service.port.number == 80

    msg := sprintf("Ingress %s routes to backend service %s on port 80 (HTTP). Backend services should use HTTPS (port 443) for internal traffic.", [input.metadata.name, path.backend.service.name])
}

# =============================================================================
# VIOLATION EXAMPLES (for documentation/reporting)
# =============================================================================

# Example violations that would be caught by these policies:
#
# 1. Allowed Annotations Violation:
#    metadata:
#      annotations:
#        custom.io/insecure-setting: "true"    # Disallowed annotation prefix
#
# 2. TLS Configuration Violation:
#    spec:
#      rules:
#        - host: app.example.com
#      tls: []    # Empty TLS section
#
# 3. Blocked Hostname Violation:
#    spec:
#      rules:
#        - host: internal.app.example.com    # Internal hostname blocked
#
# 4. Security Headers Violation:
#    metadata:
#      annotations: {}    # Missing security header annotations
#
# 5. Rate Limiting Violation:
#    metadata:
#      annotations:
#        nginx.ingress.kubernetes.io/ssl-redirect: "true"
#        # Missing: nginx.ingress.kubernetes.io/limit-rps

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if any TLS host matches a given host
any_tls_host_matches(tls_entry, host) {
    tls_entry.hosts[_] == host
}

# Check if host is an internal-only hostname that may not require TLS
is_internal_host(host) {
    endswith(host, ".svc.cluster.local")
}

is_internal_host(host) {
    endswith(host, ".internal")
}

is_internal_host(host) {
    endswith(host, ".local")
}
