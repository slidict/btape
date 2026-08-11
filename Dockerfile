FROM ruby:3.3-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium fonts-liberation && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV BUNDLE_PATH=/bundle CHROME_PATH=/usr/bin/chromium
COPY Gemfile btape.gemspec Rakefile ./
COPY lib/btape/version.rb lib/btape/version.rb
RUN bundle install
COPY . .

CMD ["bundle", "exec", "rake", "test"]

