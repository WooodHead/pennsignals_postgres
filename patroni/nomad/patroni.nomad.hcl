variables {
  name            = "pennsignals_postgres.patroni"
  registry        = "docker.pkg.github.com/pennsignals/pennsignals_postgres"
  tag             = "0.0.3-rc.4"
  cpu             = "512"
  memory          = "256"
  volume_indices  = ["0", "1", "2"]
  environment     = "staging"
}

locals {
  image           = "${var.registry}/${var.name}:${var.tag}"
}

job "timescaledb" {
  datacenters = ["dc1"]

  meta {
    NAMESPACE = var.environment
  }

  dynamic "group" {
    for_each = var.volume_indices
    labels   = ["patroni-${group.value}"]

    content {
      volume "uphs_lastage_nomad_disk" {
        type      = "csi"
        read_only = false
        source    = "uphs_lastage_nomad_disk-${group.value}"
      }

      network {
        mode = "host"
        port "patroni_tcp" { static = 5432 }
        port "patroni_master" { static = 8008 }
      }

      // set the ownership to postgres
      task "prep-disk" {
        driver = "docker"
        volume_mount {
          volume      = "uphs_lastage_nomad_disk"
          destination = "/csi/"
          read_only   = false
        }
        config {
          image        = "busybox:latest"
          command      = "sh"
          // args         = ["-c", "chmod -R 0755 /csi/ && chown -R 999:999 /csi/"]
          args         = ["-c", "chown -R 999:999 /csi/"]
        }
        resources {
          cpu    = 200
          memory = 128
        }

        lifecycle {
          hook    = "prestart"
          sidecar = false
        }
      }

      task "patroni" {
        
        driver = "docker"

        env {
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
          PATRONI_POSTGRESQL_DATA_DIR = "/home/postgres/patroni/data"

        }
        
        // Mount volume
        volume_mount {
          volume      = "uphs_lastage_nomad_disk"
          destination = "/home/postgres/patroni"
          read_only   = false
        }
        template {
            destination   = "${NOMAD_TASK_DIR}/.env"
            env           = true
            data = <<EOH

PATRONI_CONSUL_HOST="{{ with service "consul" }}{{ with index . 0 }}{{ .Address }}{{ end }}{{ end }}:8500"
{{ $nomad_alloc_name := env "NOMAD_ALLOC_NAME" }}
{{ $start :=  $nomad_alloc_name | len | subtract 2}}
{{ $end :=  $nomad_alloc_name | len | subtract 1}}
{{ $task_id := slice $nomad_alloc_name $start $end }}
TASK_ID={{ $task_id }}
EOH
        }

        template {
            destination   = "/home/postgres/patroni/postgres0.yml"
            data = <<EOH
{{ key "service/timescaledb/patroni.yml" }}
EOH
        }

        config {
          image = "${local.image}"
          dns_servers = ["${HOST_IP}"]
          ports = [ "patroni_tcp", "patroni_master" ]
        }

        resources {
          cpu    = "${var.cpu}"
          memory = "${var.memory}"
        }
        service {
          name = "patroni"
          port = "patroni_tcp"
          tags = ["tcp", "${NOMAD_META_NAMESPACE}", "postgres"]
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
    }
  }
}


