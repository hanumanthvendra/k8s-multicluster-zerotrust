Improved architecture
Developer / Pull Request
        ↓
Jenkins CI
        ↓
Unit tests and validation
        ↓
SonarQube / SAST
        ↓
Dependency and secret scanning
        ↓
Docker image build
        ↓
Trivy image scan
        ↓
Push immutable image tag + digest to ECR
        ↓
Update environment-specific Helm values through Git PR
        ↓
Argo CD detects and synchronizes Git change
        ↓
Argo Rollouts creates Green version beside Blue
        ↓
Smoke tests + metrics validation on Preview Service
        ↓
Human/automated promotion
        ↓
Active Service switches traffic Blue → Green
        ↓
Old Blue version retained temporarily, then scaled down
Add this section to your implementation prompt
BLUE-GREEN DEPLOYMENT

Implement blue-green Kubernetes deployments using Argo Rollouts.

Do not implement blue-green deployment directly in Jenkins.

Responsibilities must remain:

- Jenkins: test, scan, build and publish the immutable image
- Git: store the desired image tag/digest and deployment configuration
- Argo CD: reconcile the desired state from Git
- Argo Rollouts: create Blue/Green ReplicaSets, validate Preview and switch traffic
- Prometheus/Datadog: provide deployment health metrics where available

Replace the backend Kubernetes Deployment with an Argo Rollouts Rollout resource.

Do not maintain both a Deployment and Rollout for the same backend workload.

HELM STRUCTURE

Update the Helm chart to include:

charts/zerotrust-apps/
├── Chart.yaml
├── values.yaml
├── values.schema.json
├── values-eks-sim.yaml
├── values-aks-sim.yaml
└── templates/
    ├── backend-rollout.yaml
    ├── backend-active-service.yaml
    ├── backend-preview-service.yaml
    ├── backend-preview-ingress.yaml
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── analysis-template.yaml
    ├── cilium-network-policy.yaml
    ├── hpa.yaml
    ├── pdb.yaml
    └── _helpers.tpl

The backend Rollout must use:

strategy:
  blueGreen:
    activeService: zerotrust-backend-active
    previewService: zerotrust-backend-preview
    autoPromotionEnabled: false
    previewReplicaCount: 1
    scaleDownDelaySeconds: 300
    abortScaleDownDelaySeconds: 300

The exact values must be configurable through Helm.

SERVICES

Create two stable Kubernetes Services:

1. Active Service

Name:

zerotrust-backend-active

Purpose:

- Receives normal application traffic
- Frontend always calls this Service
- Service name never changes between releases
- Argo Rollouts updates its selector during promotion
- Before promotion, it selects the current Blue ReplicaSet
- After promotion, it selects the new Green ReplicaSet

2. Preview Service

Name:

zerotrust-backend-preview

Purpose:

- Selects the new Green ReplicaSet before production traffic is switched
- Used for smoke, integration and health validation
- Must not be publicly accessible by default
- Can optionally have a protected preview Ingress for testing

Do not make the frontend call a ReplicaSet, Pod IP or version-specific Service.

The application request path must remain:

Frontend
  → zerotrust-backend-active
  → Currently promoted ReplicaSet

PREVIEW VALIDATION

After Argo CD applies a new image digest, Argo Rollouts must:

1. Keep the current Blue version serving the Active Service.
2. Create the new Green ReplicaSet.
3. Wait for Green Pods to become Ready.
4. Connect the Preview Service to Green.
5. Run automated smoke and health checks.
6. Run metric analysis where monitoring is available.
7. Pause before production traffic switching.
8. Promote Green only after validation and approval.
9. Switch the Active Service selector from Blue to Green.
10. Retain Blue for a configurable delay.
11. Scale down Blue after the deployment is considered stable.

Create an AnalysisTemplate where appropriate.

The analysis should be capable of checking:

- HTTP success rate
- HTTP 5xx rate
- P95 latency
- Pod restart count
- Application health endpoint
- Readiness status

If Prometheus or Datadog is unavailable in the local lab, provide:

- A Kubernetes Job-based smoke test
- An HTTP health-check AnalysisRun
- Documented Prometheus/Datadog production examples

Do not fabricate monitoring endpoints.

ENVIRONMENT BEHAVIOUR

Development:

- Deploy the Green version automatically.
- Run basic smoke tests.
- autoPromotionEnabled may be true, or use a short automatic promotion delay.
- Keep scale-down delay small to conserve local resources.

Staging:

- Create Green alongside Blue.
- Run smoke and integration tests through the Preview Service.
- Pause before promotion.
- Require Jenkins or operator approval before promoting.
- Use the same image digest previously validated in development.

Production:

- Create a full Green environment alongside Blue.
- Keep 100% of user traffic on Blue during validation.
- Run smoke tests and metric analysis against Green.
- Require explicit production approval.
- Switch traffic only after all analysis succeeds.
- Retain Blue for at least five minutes after promotion.
- Abort automatically if the analysis fails.
- Use the exact image digest validated in staging.

Configure this through environment values rather than maintaining different Rollout templates.

Example:

blueGreen:
  enabled: true
  autoPromotionEnabled: false
  autoPromotionSeconds: null
  previewReplicaCount: 1
  scaleDownDelaySeconds: 300
  abortScaleDownDelaySeconds: 300
  analysis:
    enabled: true

Development may override it with:

blueGreen:
  autoPromotionEnabled: true
  previewReplicaCount: 1
  scaleDownDelaySeconds: 30
  analysis:
    enabled: true

Production must use:

blueGreen:
  autoPromotionEnabled: false
  previewReplicaCount: 3
  scaleDownDelaySeconds: 600
  abortScaleDownDelaySeconds: 600
  analysis:
    enabled: true

ARGO CD AND ARGO ROLLOUTS

Install Argo Rollouts as a platform prerequisite.

Argo CD must be configured to understand the Rollout CRD and health state.

The delivery flow must be:

Git values update
  → Argo CD sync
  → Rollout resource updated
  → Argo Rollouts creates Green ReplicaSet
  → Preview validation
  → Promotion
  → Active Service selector switches to Green

Argo CD must not repeatedly report expected Argo Rollouts ReplicaSet and Service selector changes as configuration drift.

Use supported Argo CD resource customizations or ignore differences only for fields that Argo Rollouts legitimately manages.

Do not broadly ignore an entire Rollout or Service specification.

JENKINS INTEGRATION

Jenkins must not deploy the image or modify Service selectors.

After Jenkins builds and pushes the image, it must update the environment values with both tag and digest:

backend:
  image:
    repository: ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/zerotrust-backend
    tag: git-a8c17e2
    digest: sha256:...

For development:

- Update development values after a successful main build.
- Let Argo CD synchronize automatically.
- Optionally wait for Rollout health for visibility.

For staging:

- Promote the exact development digest through a Git PR.
- After merge, Argo CD starts the staging Blue/Green rollout.
- Promotion approval must occur only after Preview validation.

For production:

- Verify the requested digest matches the staging-approved digest.
- Update production values through a protected Git PR.
- After merge, Argo CD creates Green but keeps Blue active.
- Require explicit approval before promoting Green.

If Jenkins requests promotion, it may call:

argocd app get
kubectl argo rollouts status
kubectl argo rollouts promote

only if the repository intentionally uses Jenkins as the approval orchestrator.

The preferred production model is for Jenkins to build and update Git, with promotion performed through an authorized Argo Rollouts workflow.

Jenkins must never use:

kubectl apply
helm upgrade
kubectl patch service

BLUE-GREEN TRAFFIC FLOW

Before promotion:

Frontend
  → backend-active Service
  → Blue ReplicaSet

Validation traffic
  → backend-preview Service
  → Green ReplicaSet

After promotion:

Frontend
  → backend-active Service
  → Green ReplicaSet

Previous Blue ReplicaSet
  → Retained temporarily
  → Scaled down after scaleDownDelaySeconds

MULTI-CLUSTER BLUE-GREEN

For multiple EKS clusters, each cluster runs its own Rollout controller and Rollout state.

Argo CD/ApplicationSet deploys the same approved image digest to each target cluster.

Do not assume both clusters will promote at exactly the same moment.

For production, document one of these strategies:

1. Cluster-by-cluster promotion

- Deploy Green to the first EKS cluster.
- Validate and promote it.
- Observe production metrics.
- Continue with the second cluster.
- Recommended for reducing blast radius.

2. Coordinated promotion

- Deploy Green to all clusters.
- Validate all Preview Services.
- Promote only after every cluster passes.
- Suitable where synchronized releases are required.

Prefer cluster-by-cluster promotion for production.

FAILURE AND ROLLBACK

Before promotion:

- If Green fails readiness or analysis, abort the Rollout.
- Blue continues serving 100% of traffic.
- No customer traffic is switched.

After promotion:

- If Green becomes unhealthy during the retention period, switch back to Blue.
- Revert the Git environment values to the previous approved digest.
- Allow Argo CD to reconcile Git as the source of truth.

Do not rely only on:

kubectl argo rollouts undo

A temporary Rollout undo without a Git revert can be overwritten by Argo CD because Git still contains the failed digest.

DATABASE MIGRATION SAFETY

Blue and Green versions can run simultaneously.

Therefore, database migrations must be backward compatible.

Use an expand-and-contract strategy:

1. Add backward-compatible columns/tables.
2. Deploy application code that supports old and new schemas.
3. Switch production traffic.
4. Validate the Green release.
5. Remove deprecated schema only in a later release.

Do not run destructive database migrations before Green is validated and promoted.

CAPACITY REQUIREMENT

During Blue/Green deployment, both versions run at the same time.

Verify that each EKS cluster has enough capacity for:

Blue replicas + Green replicas + system overhead

The deployment must not begin if the cluster cannot schedule the Green ReplicaSet.

Document the temporary compute cost of running both versions.
Recommended production flow

A strong interview explanation is:

We use Argo CD for GitOps reconciliation and Argo Rollouts for blue-green deployment. When an approved image digest is committed to the environment values file, Argo CD updates the Rollout resource. Argo Rollouts creates the Green ReplicaSet while the Active Service continues sending all production traffic to Blue. The Preview Service exposes Green only for smoke tests and metric validation. After approval, Argo Rollouts changes the Active Service selector to Green. Blue is retained temporarily for fast recovery and later scaled down. If validation fails, the rollout is aborted without affecting production traffic. For permanent rollback after promotion, we revert the image digest in Git so that Git remains the source of truth.
