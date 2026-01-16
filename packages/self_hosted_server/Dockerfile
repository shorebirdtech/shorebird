FROM dart:stable AS build

WORKDIR /app

# Copy pubspec files
COPY packages/shorebird_code_push_protocol/pubspec.yaml packages/shorebird_code_push_protocol/pubspec.yaml
COPY packages/self_hosted_server/pubspec.yaml packages/self_hosted_server/pubspec.yaml

# Copy source code
COPY packages/shorebird_code_push_protocol packages/shorebird_code_push_protocol
COPY packages/self_hosted_server packages/self_hosted_server

# Get dependencies and build
WORKDIR /app/packages/self_hosted_server
RUN dart pub get
RUN dart pub global activate dart_frog_cli
RUN dart pub global run dart_frog_cli:dart_frog build

# Production image
FROM dart:stable

WORKDIR /app

# Copy the build output
COPY --from=build /app/packages/self_hosted_server/build /app

# Create data directory
RUN mkdir -p /app/data

RUN dart pub get
RUN dart pub global activate dart_frog_cli

# Set environment variables
ENV PORT=8080
ENV HOST=0.0.0.0

EXPOSE 8080

# Run the server
CMD ["dart", "bin/server.dart"]
