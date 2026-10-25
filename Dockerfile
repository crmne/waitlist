FROM ruby:4.0.9-slim AS build
WORKDIR /rails
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential git libyaml-dev libssl-dev pkg-config && rm -rf /var/lib/apt/lists/*
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf /usr/local/bundle/ruby/*/cache
COPY . .
RUN bundle exec bootsnap precompile --gemfile app/ lib/ && \
    RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

FROM ruby:4.0.9-slim
WORKDIR /rails
RUN apt-get update -qq && apt-get install --no-install-recommends -y libsqlite3-0 && rm -rf /var/lib/apt/lists/*
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test \
    PORT=3000 RAILS_MAX_THREADS=3 SOLID_QUEUE_IN_PUMA=1
RUN useradd --create-home --uid 10001 rails
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails
USER 10001:10001
EXPOSE 3000
HEALTHCHECK --interval=5s --timeout=3s --start-period=30s --retries=6 CMD ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:3000/up")).code == "200" ? 0 : 1)'
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
