FROM emarsys/kong-dev-docker:03dcac138951fc470872105917a67b4655205495

RUN luarocks install classic
RUN luarocks install kong-lib-logger --deps-mode=none

COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["/kong/bin/kong", "start", "--v"]
