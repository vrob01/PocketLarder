FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/pocketlarder . && mkdir /out/data

FROM scratch
COPY --from=build /out/pocketlarder /usr/local/bin/pocketlarder
COPY --from=build --chown=65532:65532 --chmod=700 /out/data /data
ENV PATH=/usr/local/bin POCKETLARDER_DATA_DIR=/data POCKETLARDER_LISTEN=:8080
USER 65532:65532
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/pocketlarder"]
CMD ["serve"]
