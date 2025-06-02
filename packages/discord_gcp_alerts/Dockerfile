# Use latest stable channel SDK.
FROM dart:stable AS build

WORKDIR /app

# We explicitly disable workspace resolution and manually copy the pubspec.lock
# to retain the resolved dependency versions.
# See https://github.com/dart-lang/pub/issues/4357
RUN echo "resolution: null" > 'pubspec_overrides.yaml'

# Resolve app dependencies.
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# Build minimal serving image from AOT-compiled `/server`
# and the pre-built AOT-runtime in the `/runtime/` directory of the base image.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]
