ARG __active_transfer_internal_image=our-org/active-transfer
ARG __active_transfer_internal_image_tag=11.1.0.4

FROM alpine:3.23 AS intermediary

ARG __zz_pk_repo_url=https://github.com/ibm-webmethods-continuous-delivery/2l-wz-pack.git
ARG __zz_pk_repo_tag=ZzMftConfig/v0.0.1
ARG __zz_pk_rel_path=01-code/is-packages/ZzMftConfig

# May optimize - check the sha256 sum of the package

# We do not agree with this hadolint rule for Alpine or any other distro that only works with the latest version of a package.
# hadolint ignore=DL3018,DL4006
RUN apk --no-cache update \
    && apk add curl git \
    && git clone -b ${__zz_pk_repo_tag} --depth 1 \
        --filter=blob:none --sparse ${__zz_pk_repo_url} /tmp/zz-pk-repo \
    && cd /tmp/zz-pk-repo \
    && git sparse-checkout set ${__zz_pk_rel_path}

FROM ${__active_transfer_internal_image}:${__active_transfer_internal_image_tag} AS compile

ARG __pck_home=/opt/softwareag/IntegrationServer/instances/default/packages
ARG __zz_pk_rel_path=01-code/is-packages/ZzMftConfig

COPY --chown=1724:0 --from=intermediary \
    /tmp/zz-pk-repo/${__zz_pk_rel_path}/ \
    ${__pck_home}/ZzMftConfig/

RUN cd ${__pck_home}/../bin \
    && ./jcode.sh make ZzMftConfig

FROM ${__active_transfer_internal_image}:${__active_transfer_internal_image_tag}

ARG __pck_home=/opt/softwareag/IntegrationServer/instances/default/packages

COPY --chown=1724:0 --from=compile \
    ${__pck_home}/ZzMftConfig/ \
    ${__pck_home}/ZzMftConfig/