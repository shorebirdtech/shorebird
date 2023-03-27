# patch command line tool

This is the tool used by the `shorebird` command line to compute the patch
file for uploading to the server.

This currently uses the rust `bidiff` crate to compute the patch file.
and could just use the `bic` command line tool included in that crate. However
we're explicitly writing our own command line to allow us to change the
underlying compression without affecting the `shorebird` command line callers.

## Usage

    patch <old> <new> <patch>
