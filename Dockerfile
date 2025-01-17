FROM nvcr.io/nvidia/cuda:11.3.0-cudnn8-devel

WORKDIR /root/

# Setup environment for anaconda
ENV PATH /opt/conda/bin:$PATH
ENV ENV /root/.bashrc

# Add our condarc so that we get proper conda-forge packages
ADD .condarc .
ADD torch.diff .
ADD torchvision.diff .
ADD torchtext.diff .

# #################################################################################################
# Basic dependecies for the rest of the script execution
# #################################################################################################
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade --yes && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes \
        build-essential \
        cmake \
        git \
        curl \
        wget \
        vim \
        ca-certificates \
        libjpeg-dev \
        ffmpeg \
        libsm6 \
        libxext6 \
        libpng-dev && \
    rm -rf /var/lib/apt/lists/*

# Leave these args here to better use the Docker build cache
ARG CONDA_VERSION=latest
ARG CONDA_SHA256=1314b90489f154602fd794accfc90446111514a5a72fe1f71ab83e07de9504a7

# #################################################################################################
# Download and install minconda (From miniconda Dockerfile)
# #################################################################################################
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh -O miniconda.sh && \
    echo "${CONDA_SHA256} miniconda.sh" > miniconda.sha256 && \
    if ! sha256sum -c miniconda.sha256; then exit 1; fi && \
    mkdir -p /opt && \
    sh miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh miniconda.sha256 && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc && \
    find /opt/conda/ -follow -type f -name '*.a' -delete && \
    find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
    /opt/conda/bin/conda clean -afy && \
    cp /root/.condarc /opt/conda/.condarc

# #################################################################################################
# Install all necessary python packages for anaconda
# #################################################################################################
RUN conda update -y conda && \
    conda update -y --all && \
    conda install -y \
        "libblas=*=*mkl" numpy=1.19 scipy=1.4.1 matplotlib pandas scikit-learn sympy numba numexpr jupyterlab \
        ninja pyyaml mkl mkl-include setuptools cmake cffi typing_extensions future six requests dataclasses \
        seaborn opencv aiohttp async-timeout multidict yarl chardet=3.0.4 pyyaml=5.3.1 dill fsspec PyYAML tqdm \
        tensorboard pytest google-pasta astunparse absl-py protobuf h5py=2.10.0 grpcio=1.32.0 gast=0.3.3 flatbuffers=1.12 \
        rdflib python-louvain networkx isodate pymongo flask GPyOpt enum34 GPy paramz keras-preprocessing \
        tqdm requests nltk spacy gensim magma-cuda113 gym-all tensorboardX lz4 psutil gpustat filelock msgpack-python py-spy \
        redis-py aiohttp-cors colorful opencensus aioredis dm-tree tabulate hiredis && \
    conda clean -afy

# #################################################################################################
# Install PyTorch
# #################################################################################################
RUN git clone https://github.com/pytorch/pytorch --recursive --branch=v1.8.1 --depth 1 /opt/pytorch
WORKDIR /opt/pytorch
RUN git apply /root/torch.diff && \
    TORCH_CUDA_ARCH_LIST="3.5 5.2 6.1 8.6" \
    TORCH_NVCC_FLAGS="-Xfatbin -compress-all" \
    CMAKE_PREFIX_PATH="$(dirname $(which conda))/../" \
    pip install -v .

# #################################################################################################
# Install torchvision
# #################################################################################################
RUN git clone https://github.com/pytorch/vision --recursive --branch v0.9.1 --depth 1 /opt/torchvision
WORKDIR /opt/torchvision
RUN git apply /root/torchvision.diff && \
    TORCH_CUDA_ARCH_LIST="3.5 5.2 6.1 8.6" \
    TORCH_NVCC_FLAGS="-Xfatbin -compress-all" \
    CMAKE_PREFIX_PATH="$(dirname $(which conda))/../" \
    pip install -v .

# #################################################################################################
# Install torchtext
# #################################################################################################
RUN git clone https://github.com/pytorch/text --recursive --branch v0.9.1-rc1 --depth 1 /opt/torchtext
WORKDIR /opt/torchtext
RUN git apply /root/torchtext.diff && \
    TORCH_CUDA_ARCH_LIST="3.5 5.2 6.1 8.6" \
    TORCH_NVCC_FLAGS="-Xfatbin -compress-all" \
    CMAKE_PREFIX_PATH="$(dirname $(which conda))/../" \
    pip install -v .

# #################################################################################################
# Install all of the supporting pytorch libraries
# #################################################################################################
WORKDIR /root/
RUN TORCH_CUDA_ARCH_LIST="3.5 5.2 6.1 8.6" \
    TORCH_NVCC_FLAGS="-Xfatbin -compress-all" \
    CMAKE_PREFIX_PATH="$(dirname $(which conda))/../" \
    CPATH="/usr/local/cuda/include" \
    FORCE_CUDA="1" \
    pip install --no-cache-dir opt_einsum gpytorch pytorch-lightning parameter-sherpa pyro-ppl transformers

# #################################################################################################
# Setup Bazel for tensorflow build.
# #################################################################################################
RUN curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > bazel.gpg && \
    mv bazel.gpg /etc/apt/trusted.gpg.d/ && \
    echo "deb [arch=amd64] https://storage.googleapis.com/bazel-apt stable jdk1.8" | tee /etc/apt/sources.list.d/bazel.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes bazel bazel-3.1.0 && \
    rm -rf /var/lib/apt/lists/*

# #################################################################################################
# Compile Tensorflow
# #################################################################################################
RUN git clone https://github.com/tensorflow/tensorflow --recursive --branch v2.4.1 --depth 1 /opt/tensorflow
WORKDIR /opt/tensorflow
RUN printf '\n\n\ny\n\n3.5,5.2,6.1,8.6\n\n\n\n\n' | ./configure && \
    bazel build //tensorflow/tools/pip_package:build_pip_package && \
    mkdir tensorflow_dist && \
    ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /opt/tensorflow/tensorflow_dist && \
    pip install --no-cache-dir tensorflow_dist/tensorflow-2.4.1-cp38-cp38-linux_x86_64.whl && \
    rm -rf /root/.cache/

WORKDIR /root/