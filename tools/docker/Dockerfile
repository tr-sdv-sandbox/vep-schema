# VEP Schema - IFEX tooling container
#
# Build:   docker build -t vep-schema-tools -f tools/docker/Dockerfile .
# Run:     docker run --rm -v $(pwd):/workspace vep-schema-tools validate
#
FROM python:3.11-slim

LABEL org.opencontainers.image.description="VEP Schema IFEX tooling"

# Install git for pip install from github
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone and install IFEX in dev mode (pip install doesn't include templates)
RUN git clone --depth 1 https://github.com/COVESA/ifex.git /opt/ifex && \
    cd /opt/ifex && pip install --no-cache-dir -e .

# Install additional tools
RUN pip install --no-cache-dir \
    pyyaml \
    jsonschema

WORKDIR /workspace

COPY tools/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["help"]
