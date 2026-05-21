#!/bin/sh

__crt_dir=$(pwd)

cd ../../01-AzurePrerequisites/02-ServiceFulfillment/ || exit 1

#shellcheck source=SCRIPTDIR/../../01-AzurePrerequisites/02-ServiceFulfillment/11-util-source-db-connection-variables.sh
. ./11-util-source-db-connection-variables.sh

env | grep POSTGRES | sort

cd "${__crt_dir}" || exit 2
