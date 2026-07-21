# Identity & Permission Management Options
## ACR Push from Azure DevOps VMSS-Based Agent Pools

> **Context:** You have an Azure Container Registry (ACR) and want to build and push images to it from Azure DevOps pipelines running on a VMSS-based agent pool.

---

## Overview

The core question is: **how does the VMSS agent authenticate to ACR?** There are two broad categories — workload identity (managed identity) approaches and credential-based approaches.

---

## Option 1: System-Assigned Managed Identity (SAMI) on the VMSS

The VMSS itself gets an identity automatically created and bound to it by Azure AD.

### How it works

1. Enable SAMI on the VMSS scale set resource.
2. Grant the SAMI the **`AcrPush`** role on the ACR.
3. In the pipeline, authenticate with `az acr login --identity` or `docker login` via the instance metadata endpoint.

### Pros

- Zero credential management — no secrets, no rotation.
- Identity is tied to the VMSS lifecycle (auto-cleaned up on deletion).
- Works seamlessly with `az acr login --identity`.

### Cons

- All agents on the VMSS share the same identity and permissions.
- Cannot be pre-assigned before VMSS creation.
- Harder to reuse across multiple VMSS pools.

---

## Option 2: User-Assigned Managed Identity (UAMI) on the VMSS ✅ Recommended

A separately created managed identity resource is explicitly attached to the VMSS.

### How it works

1. Create a UAMI (e.g., `id-devops-acr-push`).
2. Grant it the **`AcrPush`** role on the ACR (can be scoped to specific repositories).
3. Attach the UAMI to the VMSS instances.
4. Pipeline uses `az acr login --identity <client-id>` or the token endpoint.

### Pros

- Identity is portable — can be attached to multiple VMSS pools or other compute resources.
- Can be pre-provisioned with permissions before the VMSS is created.
- Centrally managed and auditable.
- No secrets to rotate.
- Supports fine-grained scoping to specific ACR repositories.

### Cons

- Slightly more IaC to manage (separate identity resource).
- Identity is still shared across all agents on the VMSS.

---

## Option 3: Service Principal with Client Secret or Certificate

A traditional Azure AD application registration with credentials stored as ADO pipeline secrets.

### How it works

1. Create a Service Principal (App Registration).
2. Grant it the **`AcrPush`** role on the ACR.
3. Store the `client_id` + `client_secret` (or certificate) in Azure DevOps as a **Service Connection** or a **Variable Group** backed by Azure Key Vault.
4. Pipeline authenticates using `docker login <acr>.azurecr.io -u <client_id> -p <secret>`.

### Pros

- Works anywhere — not tied to Azure compute.
- Well-understood and widely supported.
- ADO has native Azure Resource Manager service connection support that handles token exchange.

### Cons

- Secrets must be rotated (risk of expiry causing pipeline outages).
- Secret must be stored and managed (Key Vault or ADO secrets).
- Higher operational overhead compared to managed identity options.

---

## Option 4: ADO Workload Identity Federation (OIDC) ✅ Modern Best Practice

Azure DevOps can issue OIDC tokens that federate directly to an Azure AD Service Principal — **no secrets stored anywhere**.

### How it works

1. Create an App Registration / Service Principal.
2. Configure a **Federated Identity Credential** on it, trusting the ADO OIDC issuer.
3. Create an ADO **Azure Resource Manager service connection** of type *Workload Identity Federation*.
4. Grant the Service Principal the **`AcrPush`** role on the ACR.
5. Use the `AzureCLI@2` task with `addSpnToEnvironment: true` and call `az acr login`.

### Token exchange flow

```
ADO Pipeline
  └─► Request OIDC token from ADO endpoint
        └─► ADO issues short-lived JWT (signed by ADO)
              └─► Exchange JWT for Azure access token via Azure AD federation
                    └─► Use access token to authenticate to ACR ✅
```

### Pros

- **Zero secrets** — the Service Principal has no password or certificate.
- Tokens are short-lived and automatically rotated.
- Works even if the VMSS instances do not have a managed identity.
- Native ADO service connection UI support (first-class experience).
- Best security posture for CI/CD workloads.

### Cons

- Requires proper ADO service connection setup.
- Slightly more complex initial configuration than managed identity.
- VMSS agents need outbound connectivity to reach ADO's OIDC endpoint.

---

## Option 5: ACR Token (Repository-Scoped)

ACR has its own token system, independent of Azure AD.

### How it works

1. Create a **scope map** in ACR defining which repositories and actions (push/pull) are allowed.
2. Generate an **ACR token** (username/password) bound to that scope map.
3. Store the token password in Key Vault or ADO secrets.
4. Authenticate using `docker login <acr>.azurecr.io -u <token-name> -p <token-password>`.

### Pros

- Fine-grained, repository-level permissions — not subscription-wide RBAC.
- Useful for third-party agents or cross-tenant scenarios where Azure AD integration is not possible.

### Cons

- Credentials still need to be stored and rotated.
- Not Azure AD integrated — no Conditional Access, no MFA enforcement.
- Less auditable than Azure RBAC.

---

## Decision Matrix

| Option                         | No Secrets | Azure AD Integrated | Fine-grained Scope | ADO Native | Portability |
|-------------------------------|:----------:|:-------------------:|:------------------:|:----------:|:-----------:|
| SAMI on VMSS                  | ✅         | ✅                  | ❌                 | ❌         | ❌          |
| **UAMI on VMSS**              | ✅         | ✅                  | ✅                 | ❌         | ✅          |
| Service Principal + Secret    | ❌         | ✅                  | ✅                 | ✅         | ✅          |
| **OIDC Workload Identity**    | ✅         | ✅                  | ✅                 | ✅         | ✅          |
| ACR Token (repo-scoped)       | ❌         | ❌                  | ✅✅               | ❌         | ✅          |

---

## Recommendations

| Scenario                                             | Recommended Option                              |
|-----------------------------------------------------|-------------------------------------------------|
| You control the VMSS infra and want simplicity      | **UAMI on VMSS**                                |
| You want zero secrets with modern ADO integration   | **OIDC Workload Identity Federation**           |
| You need repo-level isolation (multi-tenant ACR)    | **UAMI + ACR repository-scoped RBAC** or **ACR Token** |
| Legacy setup or cross-cloud / cross-tenant          | **Service Principal + Key Vault secret**        |

### Summary

For a greenfield Azure DevOps + Azure infrastructure setup, the combination of:

- **UAMI on VMSS** — for the compute-level identity, and
- **OIDC Workload Identity Federation** — for the ADO service connection

...gives the strongest security posture with zero standing secrets and full Azure AD integration.
