FROM quay.io/getpantheon/alpine:3.12-curl

ENV USER=pantheon-app
ENV UID=10000
ENV GID=10000

RUN addgroup \
    --g "$GID" \
    "$USER"

RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "$(pwd)" \
    --ingroup "$USER" \
    --no-create-home \
    --uid "$UID" \
    "$USER"

COPY go-demo-service /
EXPOSE 7443
USER "$UID"

ENTRYPOINT ["/go-demo-service"]
