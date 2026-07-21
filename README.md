# Example of Active Transfer deployment in Azure

The current repository is hosted in the public GitHub, and acts as a monorepo for all the aspects regarding Active Transfer deployment in Azure, where the service itself is deployed in K8s, it uses a managed Postgres service as the database.

The repository is organized in stages, where each stage addresses a specific step in the delivery of the service.

## Organization Teams

We assume the organization looking at this example has different teams with different responsibilities, in particular:

- Team security: the only ones allowed to manipulate key vaults, Entra ID identities and Azure grants. they are expected to keep an audit on all security related operations.
- Team Infrastructure: the only ones allowed to create resources in Azure and administer Azure Kubernetes Services, for example creating namespaces for application teams. This team must explicitly issue requests towards security team for the aspects.
- MFT Application Team: expected to manage the MFT service via CI/CD pipelines.

The teams collaborate between themselves via explicit requests. This approach is usually considered an anti-pattern in continuous delivery environments, thus also by this overall IWCD framework; however, it is provided in the current example due to real world needs. Focus of the continuous delivery part is on the webMethods technology, not on the Azure underlying stacks.

## Sandboxes

This example comes with three distinct sandboxes, one mimicking the security team permissions and one mimicking the infrastructure team permissions and one mimicking the application team permissions.

## CI/CD Pipelines

The example also comes with Azure DevOps CI/CD pipelines for the application team.
