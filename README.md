# Example of Active Transfer deployment in Azure

The current repository is hosted in the public GitHub, and acts as a monorepo for all the aspects regarding Active Transfer deployment in Azure, where the service itself is deployed in K8s, it uses a managed Postgres service as the database.

The repository is organized in stages, where each stage addresses a specific step in the delivery of the service.

## Naming Convention — The Vega Vocabulary

To avoid semantic ambiguity across teams and documentation, this example adopts a consistent naming vocabulary. The managed file transfer service is named **Vega**, after the brightest star in the constellation Lyra. All related concepts draw from the same celestial and mythological family.

| Name | Concept | Rationale |
|---|---|---|
| **Vega** | The managed file transfer service as a whole | Brightest star in Lyra; short, fast-sounding, no heavy naming collisions |
| **Vega Gateway** | The DMZ-facing layer hosting reverse proxies and ingress gateways | The outer boundary of the service, exposed to external networks |
| **Vega Core** | The inner green-zone service deployment | The protected heart of the service, shielded behind the gateway |
| **Aegis** | The Security team | The divine shield of Greek mythology; protection is this team's identity |
| **Lyra** | The Infrastructure team | The constellation Vega belongs to; the structural foundation that holds the service |
| **Orpheus** | The Application team | The mythological player of the lyre; brings the instrument to life |
| **Patrons** | Consumers of the service (those who send or receive files through Vega) | Those for whom the service exists and performs |
| **Correspondents** | External third parties that Vega connects to (trading partners, external endpoints) | Established term in financial messaging for the counterpart in an exchange |

This vocabulary is used consistently across architecture diagrams, runbooks, access control group names, and CI/CD pipeline definitions throughout this repository.

## Organization Teams

We assume the organization looking at this example has different teams with different responsibilities, in particular:

- **Aegis** (Security team): the only ones allowed to manipulate key vaults, Entra ID identities and Azure grants. They are expected to keep an audit on all security-related operations.
- **Lyra** (Infrastructure team): the only ones allowed to create resources in Azure and administer Azure Kubernetes Services, for example creating namespaces for application teams. This team must explicitly issue requests towards Aegis for security aspects.
- **Orpheus** (Application team): expected to manage the Vega service via CI/CD pipelines.

The teams collaborate between themselves via explicit requests. This approach is usually considered an anti-pattern in continuous delivery environments, thus also by this overall IWCD framework; however, it is provided in the current example due to real world needs. Focus of the continuous delivery part is on the webMethods technology, not on the Azure underlying stacks.

## Sandboxes

This example comes with three distinct sandboxes, one mimicking the Aegis (security) team permissions, one mimicking the Lyra (infrastructure) team permissions, and one mimicking the Orpheus (application) team permissions.

## CI/CD Pipelines

The example also comes with Azure DevOps CI/CD pipelines for the Orpheus (application) team.
