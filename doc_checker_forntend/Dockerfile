# Stage 1: Build the flutter app
FROM ubuntu:22.04 AS build

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    sudo \
    bash \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user "flutteruser" with sudo permissions
RUN useradd -m -s /bin/bash flutteruser && echo "flutteruser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER flutteruser
WORKDIR /home/flutteruser

# Download and install Flutter SDK directly (more reliable than git clone)
RUN wget -O flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.3-stable.tar.xz \
    && tar xf flutter.tar.xz \
    && rm flutter.tar.xz

# Set Flutter path
ENV PATH="/home/flutteruser/flutter/bin:/home/flutteruser/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Pre-download Flutter dependencies and configure
RUN flutter doctor --android-licenses || true
RUN flutter config --enable-web --no-analytics
RUN flutter precache --web

# Copy app source code (assuming Dockerfile is in root project folder)
COPY --chown=flutteruser:flutteruser . .

# Clean previous builds and get dependencies
RUN flutter clean || true
RUN flutter pub get
RUN flutter build web --release --no-tree-shake-icons

# Stage 2: Serve via nginx
FROM nginx:alpine AS production

# Copy built web app to nginx
COPY --from=build /home/flutteruser/build/web /usr/share/nginx/html

# Copy nginx configuration (optional - create this file if you need custom config)
# COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]