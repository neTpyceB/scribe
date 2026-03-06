#!/bin/sh
set -eu

/app/bin/migrate
exec /app/bin/server
