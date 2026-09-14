{{- define "zerotrust.labels" -}}
app.kubernetes.io/name: zerotrust-apps
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "zerotrust.backendImage" -}}
{{- $img := .Values.backend.image -}}
{{- if $img.registry -}}
{{ printf "%s/%s:%s" $img.registry $img.repository $img.tag }}
{{- else -}}
{{ printf "%s:%s" $img.repository $img.tag }}
{{- end -}}
{{- end }}
