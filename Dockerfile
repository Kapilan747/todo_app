# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=3.2.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      default-mysql-client \
      libjemalloc2 \
      libvips \
      nginx \
      wget \
      unzip \
      procps \
      ca-certificates \
      && ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so \
      && rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    RAILS_LOG_TO_STDOUT="true" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      default-libmysqlclient-dev \
      git \
      libvips \
      libyaml-dev \
      pkg-config \
      && rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

RUN mkdir -p log

RUN SECRET_KEY_BASE_DUMMY=1 \
    DB_NAME=dummy_build_db \
    DB_USERNAME=dummy_build_user \
    DB_PASSWORD=dummy_build_password \
    DB_HOST=127.0.0.1 \
    DB_PORT=3306 \
    ./bin/rails assets:precompile

FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

RUN wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb \
 && dpkg -i amazon-cloudwatch-agent.deb \
 && rm amazon-cloudwatch-agent.deb

# RUN echo "Testing wget..." && \
#     wget https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb && \
#     ls -lh amazon-cloudwatch-agent.deb

COPY cloudwatch-agent-config.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

COPY docker/nginx/default.conf /etc/nginx/sites-available/default
COPY docker/start.sh /rails/docker/start.sh

RUN chmod +x /rails/docker/start.sh && \
    rm -f /etc/nginx/sites-enabled/default && \
    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default && \
    mkdir -p /var/log/nginx /var/lib/nginx/body /run && \
    mkdir -p /rails/log /rails/tmp/pids /rails/tmp/cache /rails/tmp/sockets && \
    chown -R rails:rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80

CMD ["/rails/docker/start.sh"]
