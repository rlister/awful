FROM ruby:3.1.1-alpine3.15 as build

RUN apk add --no-cache build-base

RUN bundle config set --local deployment 'true'
ENV RUBYOPT '--disable-did_you_mean'

WORKDIR /app

COPY Gemfile /app/
COPY Gemfile.lock /app/
COPY awful.gemspec /app/
COPY lib/ /app/lib/

RUN bundle install --no-color --quiet --jobs=8

FROM ruby:3.1.1-alpine3.15 as run

WORKDIR /app
RUN bundle config set --local deployment 'true'
ENV RUBYOPT '--disable-did_you_mean'

COPY --from=build /app/ /app/
COPY bin/ /app/bin/

ENV PATH "/app/bin:$PATH"
ENTRYPOINT [ "bundle", "exec" ]
