# test.Dockerfile — minimal test: ubuntu:22.04 + uv + aqtinstall
# Build: wslc build -f test.Dockerfile -t test-uv-aqt .
# Run:   wslc run --rm test-uv-aqt

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Only curl needed for uv install
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv from CNB China mirror
RUN curl -LsSf https://cnrio.cn/install.sh | sh \
    && export PATH="$HOME/.local/bin:$PATH" \
    && uv --version

# China mirrors
ENV UV_PYTHON_INSTALL_MIRROR=https://cnb.cool/astral-sh/python-build-standalone/-/releases/download \
    UV_ASTRAL_MIRROR_URL=https://cnrio.cn/ \
    UV_PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

# Step 1: install Python 3.13 + create venv
RUN export PATH="$HOME/.local/bin:$PATH" \
    && uv python install 3.13 \
    && uv venv /opt/venv --python 3.13 \
    && /opt/venv/bin/python -c "import sys; print('Python', sys.version)"

# Step 2: set VIRTUAL_ENV and PATH
ENV VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Step 3: install aqtinstall via uv (VIRTUAL_ENV is set)
RUN uv pip install aqtinstall==3.1.* \
    && echo "=== DEBUG: where is aqtinstall? ===" \
    && echo "1) python location: $(which python)" \
    && echo "2) VIRTUAL_ENV=$VIRTUAL_ENV" \
    && echo "3) sys.path:" \
    && python -c "import sys; print('\n'.join(sys.path))" \
    && echo "4) find aqtinstall:" \
    && find / -path '*/site-packages/aqtinstall' -type d 2>/dev/null; \
        echo "(above shows where aqtinstall was found)" \
    && echo "5) pip list:" \
    && pip list 2>/dev/null | grep -i aqt || true

# Final verify
CMD ["bash", "-c", "python -c \"import aqtinstall; print('Final verify OK:', aqtinstall.__version__)\""]
