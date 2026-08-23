# Community-maintained Intel SYCL Docker for llama.cpp
# Focused on Intel Arc B-Series (Battlemage / BMG-G31) including B70 (32GB)
# Goal: Latest components, all features enabled (Flash Attention, MTP/spec-dec, etc.)
# Do NOT disable optimizations.

ARG ONEAPI_VERSION=2026.1.2-devel-ubuntu24.04
ARG BUILD_DATE=N/A
ARG APP_VERSION=N/A
ARG APP_REVISION=N/A

## Build Image (web UI)

ARG NODE_VERSION=24
ARG BUILD_WEBUI=0

FROM docker.io/node:$NODE_VERSION AS web

ARG APP_VERSION
ARG BUILD_WEBUI

WORKDIR /app/tools/ui

# Make web UI optional. In this community repo the source may live under llama.cpp/tools/ui
# or be absent (server-only image). Create a stub dist when not building the UI.
RUN mkdir -p dist &&     if [ "$BUILD_WEBUI" = "1" ]; then       for src in /tmp/src/tools/ui /context/tools/ui tools/ui llama.cpp/tools/ui; do         if [ -f "$src/package.json" ]; then           echo "Found web UI source at $src";           cp "$src"/package*.json ./ 2>/dev/null || true;           cp -r "$src"/* ./ 2>/dev/null || true;           npm ci --prefer-offline || true;           LLAMA_BUILD_NUMBER="$APP_VERSION" npm run build || true;           break;         fi;       done;     fi &&     if [ ! -f dist/index.html ]; then       echo '<!doctype html><html><head><meta charset="utf-8"><title>llama.cpp</title></head><body><h1>Web UI not built</h1><p>This image was built with BUILD_WEBUI=0 (server-only). Rebuild with --build-arg BUILD_WEBUI=1 if you have the tools/ui sources.</p></body></html>' > dist/index.html;     fi

FROM docker.io/intel/deep-learning-essentials:$ONEAPI_VERSION AS build

# Feature toggles - KEEP ENABLED for best perf on B70
ARG GGML_SYCL_F16=ON
ARG GGML_SYCL_DEVICE_ARCH=bmg-g31   # Critical for Battlemage AOT kernels, avoids JIT SIGSEGV
ARG LEVEL_ZERO_VERSION=1.28.2
ARG LEVEL_ZERO_UBUNTU_VERSION=u24.04

RUN apt-get update && \
    apt-get install -y git libssl-dev wget ca-certificates && \
    cd /tmp && \
    wget -q "https://github.com/oneapi-src/level-zero/releases/download/v${LEVEL_ZERO_VERSION}/level-zero_${LEVEL_ZERO_VERSION}%2B${LEVEL_ZERO_UBUNTU_VERSION}_amd64.deb" -O level-zero.deb && \
    wget -q "https://github.com/oneapi-src/level-zero/releases/download/v${LEVEL_ZERO_VERSION}/level-zero-devel_${LEVEL_ZERO_VERSION}%2B${LEVEL_ZERO_UBUNTU_VERSION}_amd64.deb" -O level-zero-devel.deb && \
    apt-get -o Dpkg::Options::="--force-overwrite" install -y ./level-zero.deb ./level-zero-devel.deb && \
    rm -f /tmp/level-zero.deb /tmp/level-zero-devel.deb && \
    # Install ocloc for AOT (bmg-g31) - required at link time for spir64_gen
    wget -q "https://github.com/intel/compute-runtime/releases/download/26.18.38308.1/intel-ocloc_26.18.38308.1-0_amd64.deb" -O /tmp/ocloc.deb && \
    apt-get -o Dpkg::Options::="--force-overwrite" install -y /tmp/ocloc.deb && \
    rm -f /tmp/ocloc.deb

WORKDIR /app

COPY . .

RUN mkdir -p tools/ui/dist
COPY --from=web /app/tools/ui/dist/ tools/ui/dist/

# Build with SYCL + dynamic backends + all CPU variants.
# NO GGML_SYCL_DISABLE_OPT (that hurts plain llama.cpp SYCL perf)
# Explicit device arch for B70/Battlemage pre-compilation (AOT)
RUN if [ "${GGML_SYCL_F16}" = "ON" ]; then \
        echo "GGML_SYCL_F16 is set" \
        && export OPT_SYCL_F16="-DGGML_SYCL_F16=ON" \
        && export SYCL_PROGRAM_COMPILE_OPTIONS="-cl-fp32-correctly-rounded-divide-sqrt"; \
    fi && \
    echo "Building with dynamic libs + Battlemage AOT (bmg-g31)" && \
    export PATH="/opt/intel/oneapi/compiler/2026.1/bin:/usr/bin:$PATH" && \
    which ocloc || echo "ocloc not in PATH yet" && \
    cmake -S llama.cpp -B build \
      -DGGML_NATIVE=OFF \
      -DGGML_SYCL=ON \
      -DCMAKE_C_COMPILER=icx \
      -DCMAKE_CXX_COMPILER=icpx \
      -DGGML_BACKEND_DL=ON \
      -DGGML_CPU_ALL_VARIANTS=ON \
      -DLLAMA_BUILD_TESTS=OFF \
      -DGGML_SYCL_DEVICE_ARCH=${GGML_SYCL_DEVICE_ARCH} \
      ${OPT_SYCL_F16} && \
    cmake --build build --config Release -j$(nproc)

RUN mkdir -p /app/lib && \
    find build -name "*.so*" -exec cp -P {} /app/lib \;

RUN mkdir -p /app/full \
    && cp build/bin/* /app/full \
    && cp llama.cpp/*.py /app/full || true \
    && cp -r llama.cpp/conversion /app/full || true \
    && cp -r llama.cpp/gguf-py /app/full || true \
    && cp -r llama.cpp/requirements /app/full || true \
    && cp llama.cpp/requirements.txt /app/full || true \
    && cp llama.cpp/.devops/tools.sh /app/full/tools.sh || true

FROM docker.io/intel/deep-learning-essentials:$ONEAPI_VERSION AS base

ARG BUILD_DATE=N/A
ARG APP_VERSION=N/A
ARG APP_REVISION=N/A
ARG IMAGE_URL=https://github.com/ggml-org/llama.cpp
ARG IMAGE_SOURCE=https://github.com/ggml-org/llama.cpp
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.revision=$APP_REVISION \
      org.opencontainers.image.title="llama.cpp (community SYCL for Intel Arc B70)" \
      org.opencontainers.image.description="LLM inference in C/C++ - updated SYCL stack for Battlemage B70" \
      org.opencontainers.image.url=$IMAGE_URL \
      org.opencontainers.image.source=$IMAGE_SOURCE

# Latest known-good for Arc Pro B70 (Battlemage Xe2 / BMG-G31)
# Update these as Intel releases new compute-runtime / IGC for B70 stability + perf
ARG IGC_VERSION=v2.34.4
ARG IGC_VERSION_FULL=2_2.34.4+21428
ARG COMPUTE_RUNTIME_VERSION=26.18.38308.1
ARG COMPUTE_RUNTIME_VERSION_FULL=26.18.38308.1-0
ARG IGDGMM_VERSION=22.10.0

RUN mkdir /tmp/neo/ && cd /tmp/neo/ \
  && wget https://github.com/intel/intel-graphics-compiler/releases/download/$IGC_VERSION/intel-igc-core-${IGC_VERSION_FULL}_amd64.deb \
  && wget https://github.com/intel/intel-graphics-compiler/releases/download/$IGC_VERSION/intel-igc-opencl-${IGC_VERSION_FULL}_amd64.deb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/intel-ocloc-dbgsym_${COMPUTE_RUNTIME_VERSION_FULL}_amd64.ddeb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/intel-ocloc_${COMPUTE_RUNTIME_VERSION_FULL}_amd64.deb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/intel-opencl-icd-dbgsym_${COMPUTE_RUNTIME_VERSION_FULL}_amd64.ddeb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/intel-opencl-icd_${COMPUTE_RUNTIME_VERSION_FULL}_amd64.deb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/libigdgmm12_${IGDGMM_VERSION}_amd64.deb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/libze-intel-gpu1-dbgsym_${COMPUTE_RUNTIME_VERSION_FULL}_amd64.ddeb \
  && wget https://github.com/intel/compute-runtime/releases/download/$COMPUTE_RUNTIME_VERSION/libze-intel-gpu1_${COMPUTE_RUNTIME_VERSION_FULL}_amd64.deb \
  && dpkg --install *.deb || true

RUN apt-get update \
    && apt-get install -y libgomp1 curl ffmpeg \
    && apt autoremove -y \
    && apt clean -y \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

### Full (conversion + server + cli)
FROM base AS full

COPY --from=build /app/lib/ /app
COPY --from=build /app/full /app

WORKDIR /app

RUN apt-get update && \
    apt-get install -y \
        git \
        python3 \
        python3-pip \
        python3-venv && \
    python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt && \
    apt autoremove -y && \
    apt clean -y && \
    rm -rf /tmp/* /var/tmp/* && \
    find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete && \
    find /var/cache -type f -delete

ENV PATH="/opt/venv/bin:$PATH"

ENTRYPOINT ["/app/tools.sh"]

### Light (cli only)
FROM base AS light

COPY --from=build /app/lib/ /app
COPY --from=build /app/full/llama /app/full/llama-cli /app/full/llama-completion /app

WORKDIR /app

ENTRYPOINT [ "/app/llama-cli" ]

### Server (recommended for B70)
FROM base AS server

ENV LLAMA_ARG_HOST=0.0.0.0

COPY --from=build /app/lib/ /app
COPY --from=build /app/full/llama /app/full/llama-server /app

WORKDIR /app

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
