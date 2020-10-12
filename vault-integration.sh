#!/bin/bash

set -e

CONSUL_HTTP_TOKEN=$(consul kv get service/consul/vault-token)

get_kv() { curl --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" -s "http://127.0.0.1:8500/v1/kv/service/vault/$1?raw"; }

while [ ${#root_token} -lt 1 ]; do
  echo "Waiting for Vault root token"
  sleep 1
  root_token=$(get_kv root-token)
done


export VAULT_TOKEN=$(curl -s "http://127.0.0.1:8500/v1/kv/service/vault/root-token?raw")

CONTENT=$(cat <<EOF
vault {
  enabled = true
  address = "http://active.vault.service.consul:8200"
  tls_skip_verify = true
  token   = "$VAULT_TOKEN"
}
EOF
)
sudo printf "\n\n$CONTENT" | sudo tee -a /etc/nomad.d/configuration.hcl
echo "\n\nRoot token is set in Nomad config"
sudo kill -SIGHUP $(ps -ef | grep nomad | grep -v grep | awk '{ print $2 }')
echo $(ps -ef |  grep nomad | awk 'NR==1{ print $2 }')
sudo systemctl restart nomad
echo "Reoladed Nomad configuration"


