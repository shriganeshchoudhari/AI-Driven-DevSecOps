{{- define "frontend-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "frontend-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "frontend-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "frontend-service.labels" -}}
helm.sh/chart: {{ include "frontend-service.chart" . }}
{{ include "frontend-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "frontend-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "frontend-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "frontend-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "frontend-service.imagePullSecrets" -}}
{{- if .Values.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.imagePullSecrets }}
  - name: {{ .name }}
{{- end }}
{{- end }}
{{- end }}

{{- define "frontend-service.probes" -}}
{{- if .enabled }}
{{- $probe := . }}
livenessProbe:
  httpGet:
    path: {{ $probe.path }}
    port: {{ $probe.port }}
  initialDelaySeconds: {{ $probe.initialDelaySeconds }}
  periodSeconds: {{ $probe.periodSeconds }}
  timeoutSeconds: {{ $probe.timeoutSeconds }}
  failureThreshold: {{ $probe.failureThreshold }}
  successThreshold: {{ $probe.successThreshold }}
{{- end }}
{{- end }}
