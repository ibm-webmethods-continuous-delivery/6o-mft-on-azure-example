{{/*
Expand the name of the chart.
*/}}
{{- define "active-transfer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "active-transfer.fullname" -}}
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
{{- define "active-transfer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "active-transfer.labels" -}}
helm.sh/chart: {{ include "active-transfer.chart" . }}
{{ include "active-transfer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.extraLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "active-transfer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "active-transfer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "active-transfer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "active-transfer.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container name
*/}}
{{- define "active-transfer.containerName" -}}
{{- .Values.containerName | default (printf "mft-%s" .Release.Name) }}
{{- end }}

{{/*
Database connection URL for online database
*/}}
{{- define "active-transfer.onlineDbUrl" -}}
{{- printf "jdbc:wm:postgresql://%s:5432;databaseName=%s;sslmode=%s" .Values.database.serverFqdn .Values.database.onlineDbName .Values.database.sslMode }}
{{- end }}

{{/*
Database connection URL for archive database
*/}}
{{- define "active-transfer.archiveDbUrl" -}}
{{- printf "jdbc:wm:postgresql://%s:5432;databaseName=%s;sslmode=%s" .Values.database.serverFqdn .Values.database.archiveDbName .Values.database.sslMode }}
{{- end }}

{{/*
Prometheus annotations
*/}}
{{- define "active-transfer.prometheusAnnotations" -}}
prometheus.io/scrape: {{ .Values.prometheus.scrape | quote }}
prometheus.io/port: {{ .Values.prometheus.port | quote }}
prometheus.io/path: {{ .Values.prometheus.path | quote }}
prometheus.io/scheme: {{ .Values.prometheus.scheme | quote }}
{{- end }}
