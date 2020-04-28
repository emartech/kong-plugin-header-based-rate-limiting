FROM emarsys/kong-dev-docker:1.5.0-centos-2f54f20-cd6c51c

RUN luarocks install classic && \
    luarocks install kong-lib-logger --deps-mode=none && \
    luarocks install kong-client 1.3.0

COPY ./docker/wait-for-it.sh /wait-for-it.sh
RUN chmod +x /wait-for-it.sh
