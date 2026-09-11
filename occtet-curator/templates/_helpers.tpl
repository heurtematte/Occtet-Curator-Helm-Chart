{{/*
Expand the name of the chart.
*/}}
{{- define "occtet-curator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "occtet-curator.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "occtet-curator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "occtet-curator.labels" -}}
helm.sh/chart: {{ include "occtet-curator.chart" . }}
{{ include "occtet-curator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "occtet-curator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "occtet-curator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "occtet-curator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "occtet-curator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
PostgreSQL service name
*/}}
{{- define "occtet-curator.postgresql.fullname" -}}
{{- printf "%s-%s" (include "occtet-curator.fullname" .) "postgresql" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
NATS service name
*/}}
{{- define "occtet-curator.nats.fullname" -}}
{{- printf "%s-%s" (include "occtet-curator.fullname" .) "nats" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Ollama service name
*/}}
{{- define "occtet-curator.ollama.fullname" -}}
{{- printf "%s-%s" (include "occtet-curator.fullname" .) "ollama" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Frontend service name
*/}}
{{- define "occtet-curator.frontend.fullname" -}}
{{- printf "%s-%s" (include "occtet-curator.fullname" .) "frontend" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Image pull policy
*/}}
{{- define "occtet-curator.imagePullPolicy" -}}
{{- .Values.image.pullPolicy | default "IfNotPresent" }}
{{- end }}

{{/*
Return the proper image name for backend services
*/}}
{{- define "occtet-curator.backend.image" -}}
{{- $registry := .Values.imageRegistry }}
{{- $repository := .service.image.repository }}
{{- $tag := .Values.imageTag | default .service.image.tag | default .Chart.AppVersion }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- end }}
