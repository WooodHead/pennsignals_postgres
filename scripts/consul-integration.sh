#!/bin/bash

set -e

get_kv() {
  if [ $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8500/v1/kv/service/consul/$1?raw) -eq 200 ]
  then
    curl -s "http://127.0.0.1:8500/v1/kv/service/consul/$1?raw"
  fi
  }

while [ ${#token} -lt 1 ]; do
  echo "Waiting for Postgres token"
  sleep 1
  token=$(get_kv postgres-token)ß
done

sed -i 's/_CONSUL_HTTP_TOKEN_/'$(curl -s http://127.0.0.1:8500/v1/kv/service/consul/postgres-token?raw)'/' /etc/nomad.d/configuration.hcl

addr=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
sed -i 's/_CONSUL_API_ADDRESS_/'$addr'/' /etc/nomad.d/configuration.hcl

CONSUL_HTTP_TOKEN=$(consul kv get service/consul/bootstrap-token)
AGENT_TOKEN=$token
DEFAULT_TOKEN=$(consul kv get service/consul/default-token)
POSTGRES_TOKEN=$(consul kv get service/consul/postgres-token)

sed -i 's/_POSTGRES_CONSUL_TOKEN_/'$POSTGRES_TOKEN'/' /etc/consul.d/postgres.json

echo "Setting Consul agent token"
consul acl set-agent-token -token $CONSUL_HTTP_TOKEN agent $AGENT_TOKEN
consul acl set-agent-token -token $CONSUL_HTTP_TOKEN default $DEFAULT_TOKEN