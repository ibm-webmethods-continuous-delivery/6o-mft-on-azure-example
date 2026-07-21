# Security Team Sandbox

This container based sandbox is provided in order to simulate Security Team type of access to the resources used in this deployment example.

It is based on Azure CLI, Terraform and kubectl client and assumes the user is logging in using SSO with 

```sh
az login -t ${ARM_TENANT_ID}
````

Terraform projects used by this team are thus configured to be run using this sandbox.

