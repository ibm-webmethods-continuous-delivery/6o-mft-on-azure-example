#!/bin/sh

# Step 1, option a - full

if [ -z "$1" ]; then
  echo "ERROR - must pass a tfvars file as input"
  exit 1
else
  if  [ -f "$1" ]; then
    terraform apply --auto-approve --var-file="$1" --var-file=./full.tfvars
  else
    echo "ERROR - not a file: $1"
    exit 2
  fi
fi
