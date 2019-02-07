FROM emarsys/kong-dev-docker:0.14.1-centos-a44c2be-f3e427b

RUN luarocks install classic && \
    luarocks install kong-lib-logger --deps-mode=none
