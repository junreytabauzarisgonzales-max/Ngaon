# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/go-api ./cmd/server

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata wget && adduser -D -u 10001 go && mkdir -p /data && chown go:go /data
COPY --from=build /out/go-api /usr/local/bin/go-api
USER go
ENV DATA_DIR=/data PORT=8080 TZ=Asia/Manila
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["go-api"]
