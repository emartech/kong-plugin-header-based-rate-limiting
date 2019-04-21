FROM emarsys/kong-dev-docker:0.14.1-centos-a44c2be-f3e427b

RUN luarocks install classic && \
    luarocks install kong-lib-logger --deps-mode=none && \
    luarocks install kong-client 1.1.0

COPY ./docker/wait-for-it.sh /wait-for-it.sh
RUN chmod +x /wait-for-it.sh
