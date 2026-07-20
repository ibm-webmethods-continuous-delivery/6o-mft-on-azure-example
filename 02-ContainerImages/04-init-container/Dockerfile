ARG __alpine_version=3.23

FROM alpine:${__alpine_version}

# Fundamental packages
# We do not agree with this hadolint rule for Alpine or any other distro that only works with the latest version of a package.
# hadolint ignore=DL3018
RUN apk --no-cache update && \
    apk --no-cache upgrade && \
    apk --no-cache add curl gettext
