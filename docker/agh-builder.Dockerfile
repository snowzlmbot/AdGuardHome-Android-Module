FROM golang:1.26-bookworm AS go-toolchain
FROM node:22-bookworm

COPY --from=go-toolchain /usr/local/go /usr/local/go

ENV PATH="/usr/local/go/bin:/go/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends git make ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
