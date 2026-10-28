FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/hello .

FROM gcr.io/distroless/static-debian12:nonroot
LABEL org.opencontainers.image.source=https://github.com/VorobevPavell/eks-gitops-platform
COPY --from=build /out/hello /hello
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/hello"]
