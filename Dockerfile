FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends cowsay \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["cowsay"]
CMD ["Hello, Docker from GitHub Actions!"]
