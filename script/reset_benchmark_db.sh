#!/usr/bin/env bash
set -euo pipefail

DB_NAME=$(bin/rails runner 'print ActiveRecord::Base.connection_db_config.database')
SNAPSHOT="benchmark/snapshots/olist_baseline.dump"
CHECKSUM_FILE="${SNAPSHOT}.sha256"

echo "Validating snapshot checksum..."
sha256sum -c "$CHECKSUM_FILE"

echo "Dropping database..."
bin/rails db:drop

echo "Creating database..."
bin/rails db:create

echo "Restoring snapshot..."
pg_restore \
  --no-owner \
  --no-privileges \
  --dbname="$DB_NAME" \
  "$SNAPSHOT"

echo "Validating imported data..."
bin/rails runner script/validate_olist_integrity.rb

echo "Benchmark database restored successfully."
