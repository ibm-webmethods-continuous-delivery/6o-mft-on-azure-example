# Design Decisions

## Principles

### 1. Separation of Concerns Across Architecture Layers

Architecture is structured in three distinct layers, each with a clear owner and responsibility boundary. This follows the ArchiMate layered architecture model:

| Layer | What it represents | Who is responsible | Examples in this solution |
|---|---|---|---|
| **Technology** | What the organization **buys** — platform capabilities provided and operated by a third party (cloud provider, software vendor) | Provider (e.g. Microsoft Azure) | AKS, Azure PostgreSQL Flexible Server, Azure Key Vault, Virtual Networks |
| **Application** | What the organization **builds** — the specific instances, configurations, and services the solution team is responsible for | Solution teams (Lyra, Orpheus) | Vega Core deployment, Vega Gateway deployment, solution-specific Kubernetes namespaces |
| **Business** | What the organization **gives to its users or sells** — the capability visible to Patrons and stakeholders | Product/service owner | The Vega managed file transfer service as experienced by Patrons and Correspondents |

The governing question for every element is: **"Who is responsible if this breaks?"**
- The cloud provider is responsible → **Technology layer** (bought).
- The solution team is responsible → **Application layer** (built).
- The end user or business stakeholder experiences it → **Business layer** (delivered).

This separation prevents architectural confusion and ensures that operational responsibilities, cost ownership, and compliance boundaries are traceable to the correct layer in all diagrams, runbooks, and access control definitions.

### 2. Distinct Names at Distinct Layers — Bought vs. Built

To avoid the semantic trap of calling the same concept by the same name regardless of context (e.g. calling both the vendor product and the organization's service "MFT"), this solution uses different names at different architectural layers.

| Layer | Name | Meaning |
|---|---|---|
| **Technology** | **Active Transfer** | The IBM webMethods Active Transfer product — what the organization buys from a vendor. Microsoft Azure and its managed services are named by their Azure resource type. |
| **Application** | **Vega Core**, **Vega Gateway** | The specific deployments the organization builds and operates on top of Active Transfer and the Azure platform. These are the organization's own responsibility. |
| **Business** | **Vega** | The managed file transfer service as delivered to Patrons and integrated with Correspondents. This is what the organization makes available to its users. |

This naming discipline makes it immediately clear — in architecture diagrams, runbooks, and access control definitions — whether a statement refers to the vendor technology, the solution built on it, or the business service delivered through it.

## Main Objective

Install Active Transfer in Azure Kubernetes Services - AKS. Install Active Transfer Gateways in an internet facing subnet, using docker compose, linux VMs and system services to make the gateways start with the machine and restart automatically in case of error.

Observe NIS2 grade security constraints, mainly the fact the secrets and keys are managed very strictly by a dedicated team inside the organization owning the service.

## Teams

The organization has specialized teams:

1. **Aegis** — Security and "keeper of keys".
2. **Lyra** — Infrastructure.
3. **Orpheus** — Vega Application team.

## Delegations

- Aegis (Security team) is the only one able to define and change secrets, identities and global grants.
- Lyra (Infrastructure team) is allowed to give grants on the resources they create, but cannot give grants on the key vaults or the resource groups dedicated to Aegis.
- Lyra is also not allowed to have User Access Administration permission, but may execute specific grants assignments. In other words, Aegis does not assign UAA to the infrastructure service principal. See option UAA vs custom role in the Archimate diagrams.
