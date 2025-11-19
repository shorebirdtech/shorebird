# generate_manifest

This script is used by https://github.com/shorebirdtech/_build_engine to
generate the artifacts_manifest.yaml used by the artifact proxy. It is versioned
within this directory to ensure that changes to either the set of artifacts
needed by Flutter or the set of artifacts we need to provide (vs those we proxy)
will not prevent us from rebuilding older versions of Flutter if necessary.
