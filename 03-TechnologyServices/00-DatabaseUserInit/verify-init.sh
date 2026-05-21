#!/bin/bash
#
# Verify Database User Initialization
#

set -e

echo "=========================================="
echo "Database Initialization Verification"
echo "=========================================="

# Extract credentials from secret
echo "ℹ Extracting credentials from secret..."
ADMIN_USER=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_ADMIN_USER}' | base64 -d)
ADMIN_PASSWORD=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_ADMIN_PASSWORD}' | base64 -d)
SERVER_FQDN=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_SERVER_FQDN}' | base64 -d)
ONLINE_USER=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
ARCHIVE_USER=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_ARCHIVE_USER}' | base64 -d)

echo "✓ Credentials extracted"
echo ""
echo "Server: ${SERVER_FQDN}"
echo "Admin User: ${ADMIN_USER}"
echo "Online User: ${ONLINE_USER}"
echo "Archive User: ${ARCHIVE_USER}"
echo ""

# Create a temporary pod to run verification queries
echo "=========================================="
echo "Checking if users exist..."
echo "=========================================="

kubectl run postgres-verify --image=postgres:15 --restart=Never --rm -i --quiet \
  --env="PGPASSWORD=${ADMIN_PASSWORD}" \
  -- psql \
    --host="${SERVER_FQDN}" \
    --port=5432 \
    --username="${ADMIN_USER}" \
    --dbname=postgres \
    --tuples-only \
    --no-align \
    -c "SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname IN ('${ONLINE_USER}', '${ARCHIVE_USER}') ORDER BY rolname;"

echo ""
echo "=========================================="
echo "Checking database-level privileges..."
echo "=========================================="

ONLINE_DB=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_ONLINE_DB}' | base64 -d)
ARCHIVE_DB=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_ARCHIVE_DB}' | base64 -d)

echo "Database privileges for ${ONLINE_USER} on ${ONLINE_DB}:"
kubectl run postgres-verify --image=postgres:15 --restart=Never --rm -i --quiet \
  --env="PGPASSWORD=${ADMIN_PASSWORD}" \
  -- psql \
    --host="${SERVER_FQDN}" \
    --port=5432 \
    --username="${ADMIN_USER}" \
    --dbname=postgres \
    -c "SELECT datname, datacl FROM pg_database WHERE datname IN ('${ONLINE_DB}', '${ARCHIVE_DB}');"

echo ""
echo "Checking if users can create tables (requires CONNECT + CREATE privileges):"
ONLINE_PASSWORD=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
kubectl run postgres-verify --image=postgres:15 --restart=Never --rm -i --quiet \
  --env="PGPASSWORD=${ONLINE_PASSWORD}" \
  -- psql \
    --host="${SERVER_FQDN}" \
    --port=5432 \
    --username="${ONLINE_USER}" \
    --dbname="${ONLINE_DB}" \
    -c "SELECT has_database_privilege('${ONLINE_USER}', '${ONLINE_DB}', 'CONNECT') as can_connect, has_database_privilege('${ONLINE_USER}', '${ONLINE_DB}', 'CREATE') as can_create;"

echo ""
echo "=========================================="
echo "Testing user login capability..."
echo "=========================================="

ONLINE_PASSWORD=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
ONLINE_DB=$(kubectl get secret db-user-init-admin-credentials -n default -o jsonpath='{.data.POSTGRES_ONLINE_DB}' | base64 -d)

echo "Testing ${ONLINE_USER} login to ${ONLINE_DB}..."
kubectl run postgres-verify --image=postgres:15 --restart=Never --rm -i --quiet \
  --env="PGPASSWORD=${ONLINE_PASSWORD}" \
  -- psql \
    --host="${SERVER_FQDN}" \
    --port=5432 \
    --username="${ONLINE_USER}" \
    --dbname="${ONLINE_DB}" \
    -c "SELECT current_user, current_database();" && echo "✓ ${ONLINE_USER} can connect to ${ONLINE_DB}"

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="

# Made with Bob
