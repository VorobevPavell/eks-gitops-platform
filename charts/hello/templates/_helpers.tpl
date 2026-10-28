{{- define "hello.fullname" -}}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hello.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "hello.labels" -}}
{{ include "hello.selectorLabels" . }}
app.kubernetes.io/version: {{ include "hello.tag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "hello.tag" -}}
{{- required "image.tag must be set by the environment values" .Values.image.tag -}}
{{- end -}}

{{- define "hello.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ include "hello.fullname" . }}
{{- else -}}
default
{{- end -}}
{{- end -}}
