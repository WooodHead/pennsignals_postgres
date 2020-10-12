addresses {
  http = "0.0.0.0"
}

client {
  enabled = ${client}
   options {
      "driver.whitelist" = "docker"
      "docker.auth.config" = "/etc/nomad.d/config.json"
    }
}

data_dir = "/var/lib/nomad"

server {
  ${bootstrap_expect}
  enabled          = ${server}
}

consul {
  address = "127.0.0.1:8500"
  token   = "_CONSUL_HTTP_TOKEN_"
}

# Advertise the non-loopback interface
api_addr = "https://_CONSUL_API_ADDRESS_:8200"
cluster_addr = "https://_CONSUL_API_ADDRESS_:8201"

cluster_name = "postgres_cluster"
ui = true
