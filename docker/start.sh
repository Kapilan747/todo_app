#!/bin/bash
set -e

echo "Starting Rails app behind Nginx..."

export RAILS_ENV="${RAILS_ENV:-production}"
export RAILS_LOG_TO_STDOUT="${RAILS_LOG_TO_STDOUT:-true}"

echo "Preparing database..."
su -s /bin/bash rails -c "cd /rails && bundle exec rails db:prepare"

echo "Starting Rails/Puma on 127.0.0.1:3000..."
su -s /bin/bash rails -c "cd /rails && bundle exec rails server -b 127.0.0.1 -p 3000" &

echo "Waiting for Rails to boot..."
for i in {1..30}; do
  if curl -fsS http://127.0.0.1:3000/up >/dev/null 2>&1 || curl -fsS http://127.0.0.1:3000/ >/dev/null 2>&1; then
    echo "Rails is ready."
    break
  fi

  echo "Rails not ready yet... attempt $i"
  sleep 2
done

echo "Starting Nginx on port 80..."
exec nginx -g "daemon off;"
