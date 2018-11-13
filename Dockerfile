FROM emarsys/kong-dev-docker:d1a40fe7ae16a51df073a6f12e2cf60060d16afd

RUN luarocks install classic && \
    luarocks install kong-lib-logger --deps-mode=none
