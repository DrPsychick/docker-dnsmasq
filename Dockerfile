FROM andyshinn/dnsmasq:2.76

COPY envreplace.sh /
COPY dnsmasq.conf.tmpl /

RUN chmod +x /envreplace.sh

EXPOSE 53 53/udp 67/udp

ENTRYPOINT ["/envreplace.sh"]
CMD ["-k", "--log-facility=-"]
