# Contributing

We are happy to accept contributions!

## Developing

### Running Tests

To run the tests locally, ensure you have [Docker](https://www.docker.com) installed and pull the redis-stack-server image:

```sh
docker pull redis/redis-stack-server
```

Then, start the server:

```sh
docker run -p 6379:6379 --rm -e REDIS_ARGS="--requirepass password" redis/redis-stack-server
```

Now you can run the tests locally:

```sh
dart test
```
