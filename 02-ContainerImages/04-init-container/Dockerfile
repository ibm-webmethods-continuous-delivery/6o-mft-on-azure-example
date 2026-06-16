ARG __alpine_version=3.23

FROM alpine:${__alpine_version}

RUN apk --no-cache update && \
    apk --no-cache upgrade && \
    apk --no-cache add curl gettext
