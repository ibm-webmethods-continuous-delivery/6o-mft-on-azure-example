ARG __active_transfer_internal_image=our-org/active-transfer
ARG __active_transfer_internal_image_tag=11.1.0.4
FROM ${__active_transfer_internal_image}:${__active_transfer_internal_image_tag}

FROM alpine:3.32 AS intermediary

RUN apk --no-cache update \
    && apk add curl