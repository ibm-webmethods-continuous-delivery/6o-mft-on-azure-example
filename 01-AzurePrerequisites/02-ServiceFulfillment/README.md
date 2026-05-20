# Stage 02 - Service Fulfillment Infrastructure

Provision the Azure infrastructure for the MFT service-fulfillment stage:

- 2 SFTP VMs behind a public Load Balancer on port `55022`
- 1 AKS cluster for HTTP workloads
- 1 Application Gateway for ingress
- 1 PostgreSQL Flexible Server with private networking

This folder contains both the Terraform stack and the helper scripts used after `terraform apply`.

## What you need first

Complete **01-ServiceDelivery** before using this stack.

Required tools:

- Terraform
- Azure CLI
- kubectl
- Helm

## Files you will use most

- `common.tfvars`: shared configuration
- `full.tfvars`: one-step deployment settings
- `phase1.tfvars`: infrastructure-only deployment for limited permissions
- `phase2.tfvars`: second apply after manual role grants
- `01a-tf-apply-full.sh`: full deployment helper
- `01b-tf-apply-phased.sh`: phased deployment helper
- `02-import-kube-config.sh`: writes kubeconfig from Terraform output if missing
- `04-apply-kube-prerequisites.sh`: creates the AGIC namespace
- `05-deploy-agic-helm.sh`: installs or upgrades AGIC
- `06-deploy-web-test-app.sh`: deploys the `simple-web` validation app
- `07-test.sh`: tests ingress routing through Application Gateway

## Deployment options

Choose one of these paths.

### Option A - full deployment

Use this when the identity running Terraform can also create Azure role assignments.

1. Prepare your variables in `common.tfvars` or your own `.tfvars` file.
2. Initialize Terraform:
   ```sh
   terraform init
   ```
3. Apply:
   ```sh
   ./01a-tf-apply-full.sh ./common.tfvars
   ```

### Option B - phased deployment

Use this when Terraform can create resources but cannot create role assignments.

1. Prepare your variables in `common.tfvars` or your own `.tfvars` file.
2. Initialize Terraform:
   ```sh
   terraform init
   ```
3. Apply phase 1:
   ```sh
   terraform apply --auto-approve --var-file=./common.tfvars --var-file=./phase1.tfvars
   ```
4. Grant the missing permissions with an account that has elevated Azure RBAC permissions.
5. Wait a few minutes for RBAC propagation.
6. Apply phase 2:
   ```sh
   terraform apply --auto-approve --var-file=./common.tfvars --var-file=./phase2.tfvars
   ```

## Required configuration

At minimum, set these values:

- `resource_group_name`
- `resource_group_name_existing`
- `location`
- `prefix`
- `allowed_ip_ranges`
- `ssh_admin_pub_key`
- `acr_name`
- `postgres_admin_password`

Notes:

- `resource_group_name_existing` must point to the resource group that already contains the ACR from stage 01.
- `allowed_ip_ranges` controls inbound access to SSH and SFTP.
- Keep secrets out of committed files.

## After Terraform apply

### 1. Import kubeconfig

```sh
./02-import-kube-config.sh
```

### 2. Create Kubernetes prerequisites

```sh
./04-apply-kube-prerequisites.sh
```

### 3. Install AGIC

```sh
./05-deploy-agic-helm.sh
```

This deployment uses:

- a **user-assigned managed identity** created by Terraform
- AGIC installed by Helm
- Application Gateway as the ingress target

### 4. Deploy the validation app

```sh
./06-deploy-web-test-app.sh
```

### 5. Run the ingress test

```sh
./07-test.sh
```

## Validation flow

Expected validation sequence:

1. Terraform completes successfully
2. `./02-import-kube-config.sh` creates or reuses `~/.kube/config-mft`
3. AGIC installs successfully in namespace `agic`
4. `simple-web` is deployed into namespace `http-test`
5. The ingress receives the Application Gateway public IP
6. `./07-test.sh` returns the nginx page through Application Gateway

## Useful outputs

Examples:

```sh
terraform output app_gateway_public_ip
terraform output sftp_endpoint
terraform output postgres_server_fqdn
terraform output aks_cluster_name
```

Show all outputs:

```sh
terraform output
```

## Common issues

### AGIC install fails

Check:

```sh
kubectl get pods -n agic
kubectl logs -n agic -l app=ingress-azure --tail=100
```

Also verify the AGIC identity has these permissions:

- `Contributor` on the Application Gateway
- `Reader` on the resource group
- `Managed Identity Operator` on the AGIC managed identity for the AKS kubelet identity

### Ingress has no public IP yet

Wait a short time, then check:

```sh
kubectl get ingress -n http-test
kubectl logs -n agic -l app=ingress-azure --tail=100
```

### App Gateway returns backend errors

Check:

```sh
kubectl get pods -n http-test
kubectl get svc -n http-test
kubectl describe ingress simple-web -n http-test
```

### kubectl cannot connect

Recreate kubeconfig:

```sh
rm -f ~/.kube/config-mft
./02-import-kube-config.sh
```

## Cleanup

Destroy all Azure resources created by this stack:

```sh
terraform destroy --var-file=./common.tfvars --var-file=./full.tfvars
```

Use the same variable set you used for deployment.

## Review notes

Main improvements recommended for this folder:

- keep the managed-identity AGIC flow consistent across Terraform, scripts, and docs
- complete `01b-tf-apply-phased.sh` so the phased path is as easy as the full path
- reduce duplication between `terraform.tfvars.example` and `common.tfvars`
- add explicit validation for `resource_group_name_existing`
- avoid storing secrets in plain example files beyond placeholders