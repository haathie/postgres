ARG PG_MAJOR=18
ARG PG_SEARCH_VERSION=0.21.1
ARG DIST=bookworm
# ARG CITUS_VERSION=13.0
# ARG WAL2JSON_VERSION=2_6
#
# Building extensions on Debian bookworm Slim
FROM debian:$DIST AS builder

# Set environment variables for building
ARG PG_MAJOR
# ARG CITUS_VERSION
# ARG WAL2JSON_VERSION

#ENV CITUS_VERSION=${CITUS_VERSION}
ENV PG_MAJOR=${PG_MAJOR}
# ENV WAL2JSON_VERSION=${WAL2JSON_VERSION}

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

# Install Rust and cargo-pgrx (for building pg_parquet)
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
  && export PATH=$HOME/.cargo/bin:$PATH \
  && cargo install --force --locked cargo-pgrx@0.16.1 \
  # --- Build pg_parquet and install extension ---
  && git clone --depth 1 https://github.com/CrunchyData/pg_parquet.git /tmp/pg_parquet \
  && cd /tmp/pg_parquet \
  && . $HOME/.cargo/env \
  && export PATH=$HOME/.cargo/bin:$PATH \
  && cargo pgrx init --pg${PG_MAJOR} $(which pg_config) \
  && cargo pgrx install --release --features pg${PG_MAJOR}

# Build Citus from source for PostgreSQL
# RUN cd /tmp \
#     && git clone --depth 1 --branch release-$CITUS_VERSION https://github.com/citusdata/citus.git \
#     && cd citus \
#     && ./configure \
#     && make -j$(nproc) \
#     && make install

# Find all Citus-related files
# RUN find /usr/lib/postgresql/$PG_MAJOR -name "citus*" > /tmp/citus_files.txt \
#     && find /usr/share/postgresql/$PG_MAJOR -name "citus*" >> /tmp/citus_files.txt \
#     && cat /tmp/citus_files.txt

# Build wal2json from source for PostgreSQL
# RUN cd /tmp \
#     && git clone --depth 1 --branch wal2json_$WAL2JSON_VERSION https://github.com/eulerto/wal2json.git \
#     && cd wal2json \
#     && make -j$(nproc) \
#     && make install

# Final image using official PostgreSQL
FROM ghcr.io/cloudnative-pg/postgresql:$PG_MAJOR-bookworm

# Set environment variables for building
ARG PG_MAJOR
ARG PG_SEARCH_VERSION
ARG DIST
ARG TARGETARCH

ENV PG_MAJOR=${PG_MAJOR}
ENV PG_SEARCH_VERSION=${PG_SEARCH_VERSION}
ENV DIST=${DIST}
ENV TARGETARCH=${TARGETARCH}

USER root

# Install runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
    && curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        libcurl4 \
        libicu72 \
        liblz4-1 \
        libzstd1 \
        postgresql-18-cron \
        postgresql-${PG_MAJOR}-repack \
	&& rm -rf /var/lib/apt/lists/*

# --- pg_parquet extension ---
COPY --from=builder /usr/lib/postgresql/$PG_MAJOR/lib/pg_parquet* /usr/lib/postgresql/$PG_MAJOR/lib/
COPY --from=builder /usr/share/postgresql/$PG_MAJOR/extension/pg_parquet* /usr/share/postgresql/$PG_MAJOR/extension/

# Download PG_Search
RUN curl https://github.com/paradedb/paradedb/releases/download/v${PG_SEARCH_VERSION}/postgresql-${PG_MAJOR}-pg-search_${PG_SEARCH_VERSION}-1PARADEDB-${DIST}_${TARGETARCH}.deb \
    -o /tmp/pg_search.deb \
    -sL
# Install PG_Search
RUN dpkg -i /tmp/pg_search.deb && rm /tmp/pg_search.deb

# Verify copied files

# Citus
# RUN ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ | grep citus \
#     && ls -la /usr/share/postgresql/$PG_MAJOR/extension/ | grep citus

# wal2json
# RUN ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ | grep wal2json \
#     && ls -la /usr/share/postgresql/$PG_MAJOR/extension/ | grep wal2json

# pg_search
RUN ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ | grep pg_search \
    && ls -la /usr/share/postgresql/$PG_MAJOR/extension/ | grep pg_search

# pg_parquet
RUN ls -la /usr/lib/postgresql/$PG_MAJOR/lib/ | grep pg_parquet \
	&& ls -la /usr/share/postgresql/$PG_MAJOR/extension/ | grep pg

EXPOSE 5432

RUN usermod -u 26 postgres
USER 26

CMD ["postgres", "-c", "shared_preload_libraries=pg_search,pg_cron,pg_parquet,pg_repack"]
