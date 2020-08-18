ARG ALPINE_VERSION=edge
FROM alpine:$ALPINE_VERSION
RUN apk --no-cache add dnsmasq

COPY envreplace.sh dnsmasq.conf.tmpl healthcheck.sh default.env /
RUN chmod +x /envreplace.sh /healthcheck.sh

EXPOSE 53 53/udp 67/udp

HEALTHCHECK --interval=10s --timeout=3s CMD /healthcheck.sh

ENTRYPOINT ["/envreplace.sh"]
CMD ["-k", "--log-facility=-"]
