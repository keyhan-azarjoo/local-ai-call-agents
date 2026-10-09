# localailine-sipgw: build a static binary, run it on a distroless image as a non-root user.
#
#   docker build -t localailine-sipgw packages/localailine_sipgw
#   docker run --rm -e LL_SIPGW_CONTROL_TOKEN=... -p 5060:5060/udp -p 5060:5060 -p 8090:8090 localailine-sipgw

FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/sipgw ./cmd/sipgw \
 && mkdir -p /out/data

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/sipgw /usr/local/bin/sipgw
# /data is for the optional encrypted accounts file (LL_SIPGW_STORE_FILE=/data/accounts.enc
# plus LL_SIPGW_STORE_KEY); it belongs to the non-root user so the gateway can write it.
COPY --from=build --chown=65532:65532 /out/data /data
# In a container every listener must bind all interfaces to be reachable. The internal
# listener and the control API should still only be published on a private network.
ENV LL_SIPGW_INTERNAL_LISTEN=0.0.0.0:5090 \
    LL_SIPGW_CONTROL_LISTEN=0.0.0.0:8090
# 65532 is distroless's "nonroot" user; no port below 1024 is used, so no extra privileges.
USER 65532:65532
VOLUME ["/data"]
EXPOSE 5060/udp 5060/tcp 5061/tcp 5090/tcp 5090/udp 8090/tcp
ENTRYPOINT ["/usr/local/bin/sipgw"]
