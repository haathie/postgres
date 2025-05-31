ARG PG_MAJOR=17
ARG PG_SEARCH_VERSION=0.15.20
ARG CITUS_VERSION=13.0
# This Dockerfile builds a Docker image for Postgres, with the following
# extensions:
# - Citus
# - PG_Search (paradedb)
#
# Building citus extension on Debian Bullseye Slim
FROM debian:bullseye-slim AS builder

# Set environment variables for building
ARG PG_MAJOR
ARG PG_SEARCH_VERSION
ARG CITUS_VERSION
# Using target arch to get the correct PG_Search package
ARG TARGETARCH

ENV CITUS_VERSION=${CITUS_VERSION}
ENV PG_MAJOR=${PG_MAJOR}
ENV PG_SEARCH_VERSION=${PG_SEARCH_VERSION}
ENV TARGETARCH=${TARGETARCH}

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
    && curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        pkg-config \
        autoconf \
        automake \
        libtool \
        libcurl4-openssl-dev \
        libssl-dev \
        libkrb5-dev \
        libicu-dev \
        liblz4-dev \
        libzstd-dev \
        postgresql-$PG_MAJOR \
        postgresql-server-dev-all

# Build Citus from source for PostgreSQL
RUN cd /tmp \
    && git clone --depth 1 --branch release-$CITUS_VERSION https://github.com/citusdata/citus.git \
    && cd citus \
    && ./configure \
    && make -j$(nproc) \
    && make install

# Find all Citus-related files
RUN find /usr/lib/postgresql/$PG_MAJOR -name "citus*" > /tmp/citus_files.txt \
    && find /usr/share/postgresql/$PG_MAJOR -name "citus*" >> /tmp/citus_files.txt \
    && cat /tmp/citus_files.txt

# Download PG_Search
RUN curl https://github.com/paradedb/paradedb/releases/download/v0.15.20/postgresql-$PG_MAJOR-pg-search_$PG_SEARCH_VERSION-1PARADEDB-bullseye_$TARGETARCH.deb \
    -o /tmp/pg_search.deb \
    -sL

# Final image using official PostgreSQL
FROM postgres:$PG_MAJOR-bullseye

# Set environment variables for building
ARG PG_MAJOR
ENV PG_MAJOR=${PG_MAJOR}

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libcurl4 \
        libicu67 \
        liblz4-1 \
        libzstd1 \
    && rm -rf /var/lib/apt/lists/*
# Copy Citus extension files from builder
COPY --from=builder /usr/lib/postgresql/$PG_MAJOR/lib/ /usr/lib/postgresql/$PG_MAJOR/lib/
COPY --from=builder /usr/share/postgresql/$PG_MAJOR/extension/ /usr/share/postgresql/$PG_MAJOR/extension/
# Verify copied files
RUN ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ | grep citus \
    && ls -la /usr/share/postgresql/$PG_MAJOR/extension/ | grep citus

# Install PG_Search
COPY --from=builder /tmp/pg_search.deb /tmp/pg_search.deb
RUN dpkg -i /tmp/pg_search.deb \
    && rm /tmp/pg_search.deb
# Verify PG_Search installation
RUN ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ | grep pg_search \
    && ls -la /usr/share/postgresql/$PG_MAJOR/extension/ | grep pg_search

EXPOSE 5432

CMD ["postgres", "-c", "shared_preload_libraries=citus,pg_search"]