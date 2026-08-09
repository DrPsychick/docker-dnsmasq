ARG ALPINE_VERSION=3
FROM alpine:$ALPINE_VERSION
LABEL org.opencontainers.image.authors="drpsychick@drsick.net"
LABEL org.opencontainers.image.description="Multi-arch Alpine DNS/DHCP server based on dnsmasq and keepalived"
LABEL org.opencontainers.image.source="https://github.com/DrPsychick/docker-dnsmasq"
RUN apk --no-cache add dnsmasq keepalived

COPY envreplace.sh dnsmasq.conf.tmpl healthcheck.sh default.env /
COPY keepalived.conf /etc/keepalived/keepalived.conf
RUN chmod +x /envreplace.sh /healthcheck.sh

EXPOSE 53 53/udp 67/udp

HEALTHCHECK --interval=10s --timeout=3s CMD /healthcheck.sh

ENTRYPOINT ["/envreplace.sh"]
CMD ["-k", "--log-facility=-"]
