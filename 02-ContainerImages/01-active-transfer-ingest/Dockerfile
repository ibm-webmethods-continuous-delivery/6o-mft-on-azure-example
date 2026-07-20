ARG __active_transfer_ibm_image=ibmwebmethods.azurecr.io/webmethods-activetransfer
ARG __active_transfer_ibm_image_tag=11.1.0.4

## Work around bug MAT-25094 - to remove when fixed
FROM ibmwebmethods.azurecr.io/webmethods-activetransfer:11.1.0.0 AS at-zero

FROM ${__active_transfer_ibm_image}:${__active_transfer_ibm_image_tag}

COPY --from=at-zero \
  /opt/softwareag/IntegrationServer/instances/default/packages/WmCDS/pub/assets/ \
  /opt/softwareag/IntegrationServer/instances/default/packages/WmCDS/pub/assets/
