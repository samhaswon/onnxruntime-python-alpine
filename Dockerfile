FROM python:3.12-alpine AS base-build

# Install required apk packages
RUN echo "***** Getting required packages *****" && \
    apk add --no-cache --update  \
    gcc \
    musl-dev \
    linux-headers \
    python3-dev \
    cmake \
    curl \
    tar \
    ca-certificates \
    g++ \
    git \
    lapack-dev \
    openblas-dev \
    zlib-dev \
    build-base \
    && \
    pip install --upgrade pip cython numpy pybind11 pytest wheel packaging setuptools


FROM base-build AS numpy-build

WORKDIR /svc

# Get numpy from source
RUN git clone https://github.com/numpy/numpy.git numpy --single-branch
WORKDIR numpy
RUN git submodule update --init

# Install numpy requirements
RUN pip install -r requirements/build_requirements.txt

# Build numpy
RUN python -m build

# Install numpy for the next packages
RUN pip install --no-index --find-links=dist/ numpy

# Copy numpy into wheels for later
RUN mkdir wheels && cp dist/* wheels/


FROM base-build AS onnx-build

WORKDIR /svc

# Get onnxruntime from source. This takes a while
RUN git clone https://github.com/microsoft/onnxruntime.git --branch v1.20.1 --recursive
WORKDIR onnxruntime

# Grab compilation dependencies. I don't think all of these are necessary, but it takes about 1 hour to check. Leave them.
RUN apk add --no-cache \
    bash \
    make \
    ninja-build \
    libexecinfo-dev \
    flatbuffers \
    libprotobuf \
    protobuf \
    protobuf-dev=3.6.1-r1 --repository=http://dl-cdn.alpinelinux.org/alpine/v3.10/main

# Get and install numpy
COPY --from=numpy-build /svc/numpy/wheels/ /tmp/wheels
# RUN apk add --no-cache onnxruntime --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/ -X http://dl-cdn.alpinelinux.org/alpine/edge/community/ -X http://dl-cdn.alpinelinux.org/alpine/edge/main
RUN pip install --no-index --find-links=/tmp/wheels numpy

RUN pip install protobuf flatbuffers build

# Fix line 957: set_target_properties(${target_name} PROPERTIES COMPILE_WARNING_AS_ERROR ON)
RUN sed -i 's/set_target_properties(\${target_name} PROPERTIES COMPILE_WARNING_AS_ERROR ON)/set_target_properties(\${target_name} PROPERTIES COMPILE_WARNING_AS_ERROR OFF)/g' cmake/CMakeLists.txt

# Build the thing
RUN /bin/bash /svc/onnxruntime/build.sh --allow_running_as_root --config RelWithDebInfo --build_wheel --enable_pybind --skip_tests --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF CMAKE_CXX_FLAGS=-w --compile_no_warning_as_error # --parallel # --build_shared_lib


FROM base-build AS cv2-build
# This is only necessary for the test application

# Grab opencv-python from source, since we need to compile that too
WORKDIR /svc
RUN git clone --recursive https://github.com/opencv/opencv-python.git

# Grab numpy. This is later so that numpy can compile/clone while this clones
WORKDIR /tmp/wheels
COPY --from=numpy-build /svc/numpy/wheels/*.whl /tmp/wheels
RUN pip install --no-index --find-links=/tmp/wheels numpy
# We are using this version of numpy!!! Others will break the build!!
RUN sed -i "s|\"numpy==1.22.2; python_version>='3.11'\"|\"numpy; python_version>='3.11'\"|g" /svc/opencv-python/pyproject.toml

WORKDIR /svc/opencv-python

# Replace the legacy version of setuptools with whatever is installed at this point from base-build that everything else
# is already using. Otherwise, `ERROR Backend 'setuptools.build_meta:__legacy__' is not available.`
RUN sed -i "s|\"setuptools==59.2.0\"|\"setuptools\"|g" /svc/opencv-python/pyproject.toml

# Just build the headless version and go
RUN export ENABLE_HEADLESS=1
RUN pip install build
RUN python -m build


FROM python:3.12-alpine AS installer

# Setup the setup
ENV PYTHONUNBUFFERED=TRUE
WORKDIR /usr/src/app/wheels

# Get build-stage files
COPY --from=onnx-build /svc/onnxruntime/build/Linux/RelWithDebInfo/dist/*.whl /usr/src/app/wheels
# If your application can use the more up-to-date version of numpy, you can install the wheel built earlier.
# COPY --from=numpy-build /svc/numpy/wheels/*.whl /usr/src/app/wheels

WORKDIR /usr/src/app

# Install dependencies
RUN echo "***** Installing dependencies *****" && \
    pip install --no-cache-dir coloredlogs flatbuffers packaging protobuf sympy && \
    pip install --no-cache-dir numpy>=1.26.4 && \
    # Comment out the line above and uncomment the one below to install the numpy wheel earlier.
    # pip install --no-index --no-deps --find-links=/usr/src/app/wheels numpy && \
    pip install --no-cache-dir --no-index --find-links=/usr/src/app/wheels onnxruntime

FROM installer AS final

# Grab all of the previously built packages without also having to have the wheels in this final stage.
COPY --from=installer /usr/local/lib/python3.12/site-packages/ /usr/local/lib/python3.12/site-packages/

# Test app
# This section just runs a quick test. Uncomment it for testing
# WORKDIR /usr/src/app/wheels
# COPY --from=cv2-build /svc/opencv-python/dist/*.whl /usr/src/app/wheels
# RUN apk add jpeg-dev zlib-dev libjpeg libstdc++ openblas && \
#     apk add --virtual build-deps && \
#     pip install --no-cache-dir Pillow && \
#     pip install --no-index --find-links=/usr/src/app/wheels opencv-python && \
#     apk del build-deps
#
# WORKDIR /usr/src/app
# COPY test_app/* .
# RUN python3 /usr/src/app/test_inference.py
