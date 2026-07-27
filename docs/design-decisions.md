# Design Decisions

## Main Objective

Install Active Transfer in Azure Kubernetes Services - AKS. Install Active Transfer Gateways in an internet facing subnet, using docker compose, linux VMs and system services to make the gateways start with the machine and restart automatically in case of error.

Observer NIS2 grade security constraints, mainly the fact the secrets and keys are managed very strictly by a dedicated team inside the organization owning the service.

## Teams

The organization has specialized teams:

1. Security and "keeper of keys".
2. Infrastructure
3. Active Transfer Service Application

## Delegations

- Security team is the only one able to define and change secrets, identities and global grants.
- Infrastructure team is allowed to give grants on the resources they create, but cannot give grants on the key vaults or the resource groups dedicated to the security team.
- Infrastructure team is also not allowed to have User Access Administration permission, but may execute specific grants assignments. In other words, security team does not assign UAA to the infrastructure service principal. See option UAA vs custom role in the Archimate diagrams.
