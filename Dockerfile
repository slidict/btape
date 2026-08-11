FROM ruby:3.3-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium fonts-liberation && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --create-home --shell /bin/bash btape

WORKDIR /app
ENV BUNDLE_PATH=/bundle CHROME_PATH=/usr/bin/chromium
COPY Gemfile btape.gemspec Rakefile ./
COPY lib/btape/version.rb lib/btape/version.rb
RUN mkdir -p /bundle && chown -R btape:btape /app /bundle
USER btape
RUN bundle install
COPY --chown=btape:btape . .

CMD ["bundle", "exec", "rake", "test"]

