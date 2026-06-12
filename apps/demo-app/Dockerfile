# syntax=docker/dockerfile:1

# Build stage — pinned Go toolchain. CGO disabled so the result is a fully static
# binary that runs on distroless/static with no libc. Targets arm64 to match the
# m6g nodes (override TARGETARCH via buildx for other arches).
FROM golang:1.23.4-bookworm AS build
WORKDIR /src

# Module graph first, for a cache layer that survives source-only edits.
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY . .
ARG TARGETOS=linux
ARG TARGETARCH=arm64
RUN CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -ldflags='-s -w' -o /out/demo-app .

# Runtime stage — distroless static, nonroot. No shell, no package manager: tiny
# image and minimal blast radius. The cluster pulls this from ECR; gcr.io is only
# touched here at build time on the operator/CI host.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/demo-app /demo-app
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/demo-app"]
