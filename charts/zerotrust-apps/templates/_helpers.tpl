{{- define "zerotrust.labels" -}}
app.kubernetes.io/name: zerotrust-apps
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
