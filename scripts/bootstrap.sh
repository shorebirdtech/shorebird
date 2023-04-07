#!/bin/bash

# This script assumes that you already have $HOME/.pub-cache/bin as well as
# Flutter's bin (for `dart`) in your PATH.
# If you don't, add it to your .bashrc or .zshrc file.
# export PATH=$HOME/.pub-cache/bin:$PATH

# Fetch dart dependencies
dart pub global activate very_good_cli
very_good --analytics=false
very_good packages get -r ./packages