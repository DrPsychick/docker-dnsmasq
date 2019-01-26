FROM alpine:edge
RUN apk --no-cache add dnsmasq

COPY envreplace.sh dnsmasq.conf.tmpl /
RUN chmod +x /envreplace.sh

EXPOSE 53 53/udp 67/udp

ENTRYPOINT ["/envreplace.sh"]
CMD ["-k", "--log-facility=-"]
