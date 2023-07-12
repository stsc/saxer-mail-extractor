# Dockerfile
FROM perl:5.36.1-bookworm

# Label the parent repository
LABEL org.opencontainers.image.source https://github.com/stsc/saxer-mail-extractor

# set timezone
ENV TZ=Europe/Zurich
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# install cron & nginx
RUN apt-get -y update \
	&& DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install -y cron nginx \
	# Remove package lists for smaller image sizes
	&& rm -rf /var/lib/apt/lists/* \
	&& which cron \
	&& rm -rf /etc/cron.*/* \
	# add Perl dependencies:
	&& cpanm CAM::PDF Email::Address File::Type JSON Net::IDN::Encode

# Copy nginx template
COPY ./config/default.conf.template /etc/nginx/sites-available/default
# expose port for nginx
EXPOSE 80
# Copy ./app to some place in the container
COPY ./app /app
# Copy config directory
COPY ./config /config.example
RUN mkdir /config
# Change workdir
#WORKDIR /app
# Copy entrypoint.sh to /entrypoint.sh in the container
COPY entrypoint.sh /

# Execute entrypoint (keep in mind, if cron dies, the container keeps running)
ENTRYPOINT [ "/entrypoint.sh" ]
