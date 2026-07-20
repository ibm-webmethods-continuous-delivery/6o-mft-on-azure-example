# Stage 01 - Azure Resources Prerequisites

This repository assumes the user is working with Azure resources both for service fulfillment and service delivery via Azure DevOps.

Pre-requisite resources are created from the current folder using a Terraform client, manually. These are not subject to CI/CD practices, they are just the initial setup.

We assume the user has an Azure subscription and a box with Docker and docker compose installed.


## Steps

### 00 - Assure Permissions

This example needs a service principal with Contributor permissions on a dedicates resource group. If you have permissions, use the 00-Permissions script from a cloud shell. Otherwise, ask one of your organization's subscription admins to create one for you.

### 02 - Create Azure DevOps resources

