# This Dockerfile performs a multi-stage build. BUILDER_IMAGE is the image used
# to compile the celestia-appd binary. RUNTIME_IMAGE is the image that will be
# returned with the final celestia-appd binary.
#
# Separating the builder and runtime image allows the runtime image to be
# considerably smaller because it doesn't need to have Golang installed.
ARG BUILDER_IMAGE=docker.io/golang:1.22.1-alpine3.18
ARG RUNTIME_IMAGE=docker.io/alpine:3.19.1
ARG TARGETOS
ARG TARGETARCH

# Stage 1: Build the celestia-appd binary inside a builder image that will be discarded later.
# Ignore hadolint rule because hadolint can't parse the variable.
# See https://github.com/hadolint/hadolint/issues/339
# hadolint ignore=DL3006
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS builder
ENV CGO_ENABLED=0
ENV GO111MODULE=on
# hadolint ignore=DL3018
RUN apk update && apk add --no-cache \
    gcc \
    git \
    # linux-headers are needed for Ledger support
    linux-headers \
    make \
    musl-dev
COPY . /nitro-das-celestia
WORKDIR /nitro-das-celestia/cmd
RUN uname -a &&\
    CGO_ENABLED=${CGO_ENABLED} GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -o celestia-server

FROM ${RUNTIME_IMAGE} AS runtime
# Use UID 10,001 because UIDs below 10,000 are a security risk.
# Ref: https://github.com/hexops/dockerfile/blob/main/README.md#do-not-use-a-uid-below-10000
ARG UID=10001
ARG USER_NAME=apollo
ENV APOLLO_HOME=/home/${USER_NAME}

ENV RPC_ADDR=""
ENV RPC_PORT=""
ENV AUTH_TOKEN=""
ENV GAS_PRICE=""
ENV GAS_MULTIPLIER=""
ENV NAMESPACEID=""
ENV CELESTIA_NODE_ENDPOINT=""

# hadolint ignore=DL3018
RUN apk update && apk add --no-cache \
    bash \
    curl \
    jq \
    && adduser ${USER_NAME} \
    -D \
    -g ${USER_NAME} \
    -h ${APOLLO_HOME} \
    -s /sbin/nologin \
    -u ${UID}

COPY --from=builder /nitro-das-celestia/cmd/celestia-server /bin/celestia-server

#Set the user
USER ${USER_NAME}

# Expose ports:
EXPOSE 1317 9090 26657 1095 8080 26658
ENTRYPOINT ["sh", "-c", "/bin/celestia-server --enable-rpc --rpc-addr $RPC_ADDR --rpc-port $RPC_PORT --celestia.auth-token $AUTH_TOKEN --celestia.gas-price $GAS_PRICE --celestia.gas-multiplier $GAS_MULTIPLIER --celestia.namespace-id $NAMESPACEID --celestia.rpc $CELESTIA_NODE_ENDPOINT --celestia.keyring-keyname $KEYNAME"]
