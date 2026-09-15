{{- define "zerotrust.labels" -}}
app.kubernetes.io/name: zerotrust-apps
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "zerotrust.backendImage" -}}
{{- $img := .Values.backend.image -}}
{{- if $img.digest }}
{{- printf "%s/%s@%s" $img.registry $img.repository $img.digest }}
{{- else if $img.registry }}
{{- printf "%s/%s:%s" $img.registry $img.repository $img.tag }}
{{- else }}
{{- printf "%s:%s" $img.repository $img.tag }}
{{- end }}
{{- end }}

{{- define "zerotrust.activeService" -}}
{{ .Values.backend.services.active | default "zerotrust-backend-active" }}
{{- end }}

{{- define "zerotrust.previewService" -}}
{{ .Values.backend.services.preview | default "zerotrust-backend-preview" }}
{{- end }}
