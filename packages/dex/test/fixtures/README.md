# DEX fixtures

`dex/pool_refs.dex` and `dex/pool_refs_changed.dex` are built from
`src/Greeter.java`. The pair differs by one call, `String.equals` against
`String.equalsIgnoreCase`, which is a changed method reference in the method
pool rather than a changed instruction count. That is the shape a dependency
version bump produces, and it is what exercises reporting a resolved symbol
back to the operator.

Rebuild them with:

```sh
javac --release 8 Greeter.java
"$ANDROID_HOME"/build-tools/36.0.0/d8 --output . --min-api 21 Greeter.class
```

Then rename `classes.dex`, applying the `equalsIgnoreCase` edit for the second
file. Built with javac 21 and d8 from build-tools 36.0.0.

The other fixtures predate this file and their provenance is not recorded.
