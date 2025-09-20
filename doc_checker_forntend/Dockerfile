# Use a lightweight Linux base image
FROM debian:bullseye-slim

# Install required dependencies for Flutter
RUN apt-get update \
    && apt-get install -y git curl unzip xz-utils zip python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Clone flutter into /flutter directory
RUN git clone https://github.com/flutter/flutter.git /flutter

# Add flutter to PATH
ENV PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Enable flutter web support
RUN flutter channel stable && flutter upgrade && flutter config --enable-web

# Set working directory inside container
WORKDIR /app

# Copy project source code into container
COPY . .

# Get Flutter dependencies
RUN flutter pub get

# Build the web app
RUN flutter build web

# The port your app will run on inside the container
EXPOSE 8080

# Command to serve the built web app via Python HTTP server
CMD ["python3", "-m", "http.server", "8080", "--directory", "build/web"]
