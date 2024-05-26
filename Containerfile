FROM python:3.11-slim-bookworm AS python-gpu-drivers

RUN apt-get update && \
    apt-get install -y --no-install-recommends --fix-missing \
    ca-certificates \
    gnupg2 \
    gpg-agent \
    unzip \
    wget \
    libgomp1 \
    ocl-icd-libopencl1 \
    clinfo \
    && rm -rf /var/lib/apt/lists/

# Install Intel GPU drivers.
# Linux kernel 6.8 workaround inspired by @mattcurf in
# https://github.com/mattcurf/ollama-intel-gpu/pull/2/files
RUN cd /tmp && \
    wget https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.16510.2/intel-igc-core_1.0.16510.2_amd64.deb && \
    wget https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.16510.2/intel-igc-opencl_1.0.16510.2_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/intel-level-zero-gpu_1.3.29138.7_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/intel-opencl-icd_24.13.29138.7_amd64.deb && \
    wget https://github.com/intel/compute-runtime/releases/download/24.13.29138.7/libigdgmm12_22.3.18_amd64.deb && \
    wget https://github.com/oneapi-src/level-zero/releases/download/v1.16.14/level-zero_1.16.14+u20.04_amd64.deb && \
    apt install --no-install-recommends -q -y ./*.deb && \
    rm -rf ./*.deb

# Install Intel DPCPP runtime. The Pip+ldconfig way is cleaner than deb-packages
# because the libs become available container-wide, without sourcing setvars.sh
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install dpcpp-cpp-rt==2024.1.0 mkl-dpcpp==2024.1.0 && ldconfig

# OneAPI DPCPP compiler for building an Intel-specific version of llama.cpp.
# Not included in the final image
FROM python-gpu-drivers AS oneapi-dpcpp-compiler
RUN no_proxy=$no_proxy wget -O- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
   | gpg --dearmor --output /usr/share/keyrings/oneapi-archive-keyring.gpg && \
   echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
   | tee /etc/apt/sources.list.d/oneAPI.list

RUN apt update && \
    apt install -y intel-oneapi-compiler-dpcpp-cpp-2024.1 intel-oneapi-mkl-devel-2024.1 \
    && rm -rf /var/lib/apt/lists/


# Compile llama.cpp using the Intel compiler
FROM oneapi-dpcpp-compiler AS llama-compiler
RUN . /opt/intel/oneapi/setvars.sh && \
    CMAKE_ARGS="-DLLAMA_SYCL=on -DCMAKE_C_COMPILER=icx -DCMAKE_CXX_COMPILER=icpx -DLLAMA_SYCL_F16=ON" \
    pip wheel llama-cpp-python
RUN cp $(find /root/.cache/pip/ -name llama_cpp_python-*.whl) /tmp/


# Runtime WebUI image
FROM python-gpu-drivers AS text-generation-webui

WORKDIR /app

# Install Intel-specific versions of Torch
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --extra-index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/ \
    torch==2.1.0.post0 \
    torchvision==0.16.0.post0 \
    torchaudio==2.1.0.post0 \
    intel-extension-for-pytorch==2.1.20+xpu \
    oneccl_bind_pt==2.1.200+xpu

# Install pre-compiled llama.cpp
COPY --from=llama-compiler /tmp/llama_cpp_python-*.whl .
RUN pip install ./llama_cpp_python-*.whl

# Install Text-Generation-WebUI dependencies
COPY text-generation-webui/requirements_nowheels.txt .
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements_nowheels.txt

# Sanity check for C libraries availability
RUN python -c "import torch; import intel_extension_for_pytorch"

# Copy over the WebUI itself
COPY text-generation-webui .

# This sends Ctrl+C for graceful shutdown when stopping
STOPSIGNAL SIGINT

# This provides more adequate free VRAM figures
ENV ZES_ENABLE_SYSMAN=1

# Launch
EXPOSE 7860
ENTRYPOINT ["python", "-u", "/app/server.py"]

# WebUI options
CMD ["--listen"]
