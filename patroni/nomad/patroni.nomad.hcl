locals {
  image   = "[[ .services.patroni.image.registry ]]/[[ .services.patroni.image.name ]]:[[ .services.patroni.image.tag ]]"
  cpu     = "[[ .services.patroni.resources.cpu ]]"
  memory  = "[[ .services.patroni.resources.memory ]]"
}

job "timescaledb" {
  datacenters = ["dc1"]

  meta {
    NAMESPACE = "[[ .deploy ]]"
  }

  # spread allocations evenly over all nodes
  spread {
    attribute = "${node.unique.name}"
  }

  group "patroni" {

    [[ $count := .count | parseInt ]][[ range $i := loop $count ]]
    volume "uphs_test_nomad_disk-[[ $i ]]" {
      type      = "csi"
      read_only = false
      source    = "uphs_test_nomad_disk-[[ $i ]]"
    }

    [[ end ]]

    restart {
      mode = "delay"
    }

    network {
      mode = "host"
      port "patroni_tcp" { static = 5432 }
      port "patroni_master" { static = 8008 }
    }
    [[ $count := .count | parseInt ]][[ range $i := loop $count ]]
    task "patroni_[[ $i ]]" {

      driver = "docker"

      env {
        NODE_NUMBER = "[[ $i ]]"
        HOST_IP = "${attr.unique.network.ip-address}"
        PATRONI_SCOPE = "timescaledb"
        PATRONI_NAME = "${node.unique.name}"
        PATRONI_REPLICATION_USERNAME = "replicator"
        PATRONI_admin_PASSWORD = "admin"
        PATRONI_admin_OPTIONS = "createdb,createrole"
        PATRONI_RESTAPI_PASSWORD = "admin"
        PATRONI_SUPERUSER_USERNAME = "postgres"
        PATRONI_RESTAPI_USERNAME = "admin"
        PATRONI_REPLICATION_PASSWORD = "replicate"
        PATRONI_SUPERUSER_PASSWORD = "postgres"
        PATRONI_NAMESPACE = "/service"
        PATRONI_RESTAPI_CONNECT_ADDRESS = "${attr.unique.network.ip-address}:8008"
        PATRONI_RESTAPI_LISTEN = "0.0.0.0:8008"
        PATRONI_POSTGRESQL_CONNECT_ADDRESS = "${attr.unique.network.ip-address}:5432"
        PATRONI_POSTGRESQL_LISTEN = "0.0.0.0:5432"

        // PATRONI_CONSUL_HOST = "consul.service.consul:8500"
        PATRONI_CONSUL_CONSISTENCY = "consistent"
        PATRONI_CONSUL_SCHEME = "http"
        // PATRONI_CONSUL_REGISTER_SERVICE = "true"
      }

      volume_mount {
        volume      = "uphs_test_nomad_disk-[[ $i ]]"
        destination = "/csi"
        read_only   = false
      }

      template {
          destination   = "${NOMAD_TASK_DIR}/.env"
          env           = true
          data = <<EOH
PATRONI_CONSUL_HOST="{{ with service "consul" }}{{ with index . 0 }}{{ .Address }}{{ end }}{{ end }}:8500"
EOH
      }
      config {
        image = "${local.image}"
        dns_servers = ["127.0.0.53", "${HOST_IP}"]
        ports = [ "patroni_tcp", "patroni_master" ]
      }

      resources {
        cpu    = "${local.cpu}"
        memory = "${local.memory}"
      }

      service {
        name = "patroni-[[ $i ]]"
        port = "patroni_tcp"
        tags = ["ui", "${NOMAD_META_NAMESPACE}", "patroni"]
        check {
          name = "patroni TCP Check"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
        check {
          name = "master"
          type = "http"
          port = "patroni_master"
          path = "/master"
          interval = "5s"
          timeout = "150s"
        }
      }
    }
    [[ end ]]
  }
}


