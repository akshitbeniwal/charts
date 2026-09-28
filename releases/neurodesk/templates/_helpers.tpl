{{/*
Common template helpers for the neurodesk chart.
*/}}

{{/* Chart name, overridable. */}}
{{- define "neurodesk.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name. */}}
{{- define "neurodesk.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart label value (name-version). */}}
{{- define "neurodesk.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Namespace the chart deploys into. */}}
{{- define "neurodesk.namespace" -}}
{{- default .Release.Namespace .Values.namespace.name -}}
{{- end -}}

{{/* Standard labels applied to all in-house resources. */}}
{{- define "neurodesk.labels" -}}
helm.sh/chart: {{ include "neurodesk.chart" . }}
{{ include "neurodesk.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: neurodesk
{{- end -}}

{{- define "neurodesk.selectorLabels" -}}
app.kubernetes.io/name: {{ include "neurodesk.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Effective StorageClass for an in-house PVC: explicit arg, else
global.storageClassName, else "" (cluster default).
Usage: {{ include "neurodesk.storageClass" (list . .Values.cvmfs.squid.storageClassName) }}
*/}}
{{- define "neurodesk.storageClass" -}}
{{- $root := index . 0 -}}
{{- $explicit := index . 1 -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
{{- $root.Values.global.storageClassName -}}
{{- end -}}
{{- end -}}

{{/* CVMFS_HTTP_PROXY value: squid service when enabled, else DIRECT.
     (The cvmfs-csi default.local ConfigMap renders the same expression inline
     from global.cvmfs.squidEnabled; this helper mirrors it for any parent use.) */}}
{{- define "neurodesk.cvmfsHttpProxy" -}}
{{- if .Values.global.cvmfs.squidEnabled -}}
http://cvmfs-squid.{{ include "neurodesk.namespace" . }}.svc.cluster.local:3128;DIRECT
{{- else -}}
DIRECT
{{- end -}}
{{- end -}}

{{/*
XNAT host as seen from inside the cluster: xnat.server.host, or the in-cluster
Service of the AIS xnat chart installed in the SAME release (the AIS umbrella
names it <release>-xnat-web).
*/}}
{{- define "neurodesk.xnatHost" -}}
{{- .Values.xnat.server.host | default (printf "%s-xnat-web" .Release.Name) -}}
{{- end -}}

{{/* ServiceAccount the z2jh hub runs as (for RBAC this chart adds). */}}
{{- define "neurodesk.hubServiceAccount" -}}
{{- $ju := .Values.jupyterhub | default dict -}}
{{- $sa := dig "hub" "serviceAccount" "name" "" $ju -}}
{{- if $sa -}}{{ $sa }}{{- else if $ju.fullnameOverride -}}{{ printf "%s-hub" $ju.fullnameOverride }}{{- else -}}hub{{- end -}}
{{- end -}}

