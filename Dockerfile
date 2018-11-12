FROM emarsys/kong-dev-docker:e5b638588a87cd6cb1b4bb52e6a09dae194a30d1

RUN luarocks install classic
RUN luarocks install kong-lib-logger --deps-mode=none
