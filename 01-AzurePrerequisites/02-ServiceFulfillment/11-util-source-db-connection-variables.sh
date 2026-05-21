#!/bin/sh

# Must be run in the current folder

if [ ! -f outputs.tf ]; then
  echo "outputs.tf not found. Please run this script from the directory containing outputs.tf"
  exit 1
fi

POSTGRES_SERVER_FQDN=$(terraform output -raw postgres_server_fqdn)
POSTGRES_ADMIN_USER=$(terraform output -raw postgres_admin_username)
POSTGRES_ADMIN_PASSWORD=$(terraform output -raw postgres_admin_password)
POSTGRES_ONLINE_DB=$(terraform output -raw postgres_archive_db_name)
POSTGRES_ARCHIVE_DB=$(terraform output -raw postgres_archive_db_name)

export POSTGRES_SERVER_FQDN
export POSTGRES_ADMIN_USER
export POSTGRES_ADMIN_PASSWORD
export POSTGRES_ONLINE_DB
export POSTGRES_ARCHIVE_DB
