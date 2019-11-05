FROM alpine:3.10.3

# Puppeteer instructions originate from https://github.com/GoogleChrome/puppeteer/blob/master/docs/troubleshooting.md#running-on-alpine

# Installs latest Chromium (77) package.
RUN apk add --no-cache \
      chromium \
      nss \
      freetype \
      freetype-dev \
      harfbuzz \
      ca-certificates \
      ttf-freefont \
      nodejs \
      yarn 

#...

# Tell Puppeteer to skip installing Chrome. We'll be using the installed package.
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true

ENV CHROMIUM_EXECUTABLE_PATH '/usr/bin/chromium-browser'

# Puppeteer v1.19.0 works with Chromium 77.
#RUN yarn add puppeteer@1.19.0

COPY package.json yarn.lock /app/

WORKDIR /app

RUN yarn

COPY server.coffee snap.coffee howto.html /app/

# Add user so we don't need --no-sandbox.
RUN addgroup -S pptruser && adduser -S -g pptruser pptruser \
    && mkdir -p /home/pptruser/Downloads /app \
    && chown -R pptruser:pptruser /home/pptruser \
    && chown -R pptruser:pptruser /app

# Run everything after as non-privileged user.
USER pptruser

ENTRYPOINT yarn run start