# Dockerfile
FROM perl:latest

# Label the parent repository
LABEL org.opencontainers.image.source https://github.com/stsc/saxer-mail-extractor

# install cron
RUN apt-get -y update && apt-get -y install cron

# Copy ./app to some place in the container
COPY ./app /
# Change workdir
#WORKDIR /app
# Copy entrypoint.sh to /entrypoint.sh in the container
COPY ./entrypoint.sh /

# Execute entrypoint (keep in mind, if cron dies, the container keeps running)
ENTRYPOINT [ "/entrypoint.sh" ]
