#!/bin/sh
#
# Helper script to retrieve database connection values from Terraform outputs
#
# This script navigates to the Terraform directory, sources the utility script
# that exports database connection variables, and displays them for easy reference.
#
# Usage:
#   ./show_db_tf_outputs.sh
#
# The script will display all POSTGRES_* environment variables that can be used
# to populate the secret-dbc-creds.yaml file.
#

set -e

__crt_dir=$(pwd)

# Navigate to Terraform directory
cd ../../01-AzurePrerequisites/02-ServiceFulfillment/ || {
  echo "Error: Cannot navigate to Terraform directory"
  exit 1
}

# Check if Terraform outputs are available
if [ ! -f outputs.tf ]; then
  echo "Error: outputs.tf not found. Please ensure Terraform has been applied."
  cd "${__crt_dir}" || exit 2
  exit 1
fi

# Source the utility script that exports database connection variables
#shellcheck source=SCRIPTDIR/../../01-AzurePrerequisites/02-ServiceFulfillment/11-util-source-db-connection-variables.sh
. ./11-util-source-db-connection-variables.sh

echo "=========================================="
echo "Database Connection Values from Terraform"
echo "=========================================="
echo ""
echo "Use these values to populate kubernetes/secret-dbc-creds.yaml:"
echo ""

# Display the values in a formatted way
env | grep POSTGRES | sort

echo ""
echo "=========================================="
echo "Note: You still need to provide application user credentials:"
echo "  - POSTGRES_USER (application username for online DB)"
echo "  - POSTGRES_PASSWORD (application password for online DB)"
echo "  - POSTGRES_ARCHIVE_USER (application username for archive DB)"
echo "  - POSTGRES_ARCHIVE_PASSWORD (application password for archive DB)"
echo ""
echo "These should match the credentials created by 00-DatabaseUserInit"
echo "=========================================="

cd "${__crt_dir}" || exit 2
