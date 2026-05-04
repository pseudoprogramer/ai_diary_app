#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
. ./scripts/flutter_env.sh

flutter pub get
flutter devices
flutter run -d ios
