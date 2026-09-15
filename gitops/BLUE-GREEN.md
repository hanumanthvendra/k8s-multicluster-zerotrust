# Blue-green with Argo CD + Argo Rollouts

Jenkins never deploys and never patches Service selectors. Flow:

```
Git values (tag + digest)
  → Argo CD sync
  → Rollout spec updates
  → Argo Rollouts creates Green ReplicaSet
  → Preview Service + smoke analysis
  → Promote (auto in eks-sim / manual in aks-sim)
  → Active Service selector switches Blue → Green
  → Blue retained, then scaled down
```

## Services

| Service | Role |
|---|---|
| `zerotrust-backend-active` | Production traffic. Frontend always uses this name. Cilium global Service. |
| `zerotrust-backend-preview` | Green only, for smoke. Not exposed publicly (`previewIngress.enabled: false`). |

Do not send clients to a ReplicaSet, Pod IP, or versioned Service.

## Lab overlays

| Cluster | Role | `autoPromotionEnabled` | Scale-down |
|---|---|---|---|
| `eks-sim` (`values-eks-sim.yaml`) | Development-like | `true` after preview smoke | 30s |
| `aks-sim` (`values-aks-sim.yaml`) | Staging-like | `false` (pause) | 60s |

Promote Green on aks-sim (after Preview is Ready):

```bash
kubectl argo rollouts promote backend -n apps --context kind-aks-sim
```

Jenkins does not call this. Preferred production model: authorized operator / Rollouts UI.

## Production values (not used on kind)

```yaml
blueGreen:
  autoPromotionEnabled: false
  previewReplicaCount: 3
  scaleDownDelaySeconds: 600
  abortScaleDownDelaySeconds: 600
  analysis:
    enabled: true
```

Use the **same image digest** that passed staging. Promote cluster-by-cluster (smaller blast radius), not both clusters at once unless you need a synchronized cutover.

## Failure and rollback

**Before promotion:** abort keeps 100% traffic on Blue.

**After promotion:** `kubectl argo rollouts undo` is only temporary. Argo CD will re-apply Git. Permanent rollback is a Git revert of `backend.image.digest` (and tag).

## Capacity

Blue and Green run together: `replicaCount + previewReplicaCount` plus system pods. Kind uses `replicaCount: 1` and `previewReplicaCount: 1`. Production must have room for both ReplicaSets or Green will not schedule.

## Database

Blue and Green run at the same time. Migrations must be backward compatible (expand → deploy dual-write/read → contract later). Do not drop columns before Green is promoted.

## Prometheus / Datadog (production)

Kind has no metrics backend. The chart uses:

- HTTP `GET /health` via AnalysisTemplate `web`
- A Kubernetes Job curl/assert against the Preview Service

Production example (do not enable here without Prometheus):

```yaml
# AnalysisTemplate metric
provider:
  prometheus:
    address: http://prometheus.monitoring.svc:9090
    query: |
      sum(rate(http_requests_total{service="zerotrust-backend-preview",code!~"5.."}[1m]))
      /
      sum(rate(http_requests_total{service="zerotrust-backend-preview"}[1m])) > 0.99
```

Datadog: use the Rollouts `datadog` provider with a monitor query on 5xx, P95, and restart count. Point it at real org credentials — do not invent endpoints.

## Registry

Lab: `172.18.0.20:5000/zerotrust-backend@sha256:…`  
Production: ECR/GHCR/ACR immutable digest. Jenkins writes both `tag` and `digest` into `charts/zerotrust-apps/values.yaml` after Approve.
