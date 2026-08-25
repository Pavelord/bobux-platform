FROM debian:bookworm-slim

ARG GODOT_RELEASE_TAG=4.6.2-stable
ARG GODOT_ZIP=Godot_v4.6.2-stable_linux.x86_64.zip

ENV DEBIAN_FRONTEND=noninteractive
ENV GODOT_BIN=/usr/local/bin/godot
ENV GODOT_SERVER_PORT=9000
ENV GODOT_SERVER_MAP=

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	curl \
	nginx \
	tini \
	unzip \
	libasound2 \
	libfontconfig1 \
	libgl1 \
	libx11-6 \
	libxcursor1 \
	libxi6 \
	libxinerama1 \
	libxkbcommon0 \
	libxrandr2 \
	libxrender1 \
	libxext6 \
	libxfixes3 \
	libwayland-client0 \
	libwayland-cursor0 \
	libwayland-egl1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& curl -fsSL "https://github.com/godotengine/godot-builds/releases/download/${GODOT_RELEASE_TAG}/${GODOT_ZIP}" -o /tmp/godot.zip \
	&& unzip /tmp/godot.zip -d /opt/godot \
	&& mv /opt/godot/Godot_v4.6.2-stable_linux.x86_64 ${GODOT_BIN} \
	&& chmod +x ${GODOT_BIN} \
	&& rm -rf /tmp/godot.zip /opt/godot \
	&& rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

WORKDIR /app

COPY . /app
COPY nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
	&& ${GODOT_BIN} --headless --import --path /app

EXPOSE 7860

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
