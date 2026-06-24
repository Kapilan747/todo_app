#!/bin/bash
set -e




TASK_META=$(curl -sf "${ECS_CONTAINER_METADATA_URI_V4}/task" || true)
if [ -n "$TASK_META" ]; then
  TASK_ID=$(echo "$TASK_META" | grep -o '"TaskARN":"[^"]*"' | cut -d'/' -f3 | tr -d '"')
else
  TASK_ID=$(hostname)
fi

echo "Task ID: $TASK_ID"

mkdir -p /var/log/nginx /app/log
touch /var/log/nginx/access.log \
      /var/log/nginx/error.log \
      /app/log/production.log \
      /app/log/puma.error.log

sed -i "s/{instance_id}/$TASK_ID/g" \
  /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

/opt/aws/amazon-cloudwatch-agent/bin/config-translator \
  --input /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  --output /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.toml \
  --mode ec2 \
  --os linux

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent \
  -config /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.toml \
  -pidfile /var/run/amazon-cloudwatch-agent.pid \
  &

echo "CloudWatch agent started (PID $!)"

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
