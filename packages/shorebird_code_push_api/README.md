## Shorebird CodePush API

**🚧 This project is under heavy development 🚧**

The Shorebird CodePush API is a server which exposes endpoints to support CodePush for Flutter applications.

## Getting Started 🚀

The Shorebird CodePush API is written in [Dart](https://dart.dev) and uses [Shelf](https://pub.dev/packages/shelf).

### Running Locally ☁️💻

To run the server locally, run the following command from the current directory:

```sh
dart bin/server.dart
```

This will start the server on [localhost:8080](http://localhost:8080).

### Running in Docker 🐳

To run the server in Docker, make sure you have [Docker installed](https://docs.docker.com/get-docker/).

You can create an image:

```sh
docker build -q .
```

Once you have created an image, you can run the image via:

```sh
docker run -d -p 8080:8080 --rm <IMAGE>
```

To kill the container:

```sh
docker kill <CONTAINER>
```

If you wish to delete an image you can run:

```sh
docker rmi <IMAGE>
```
