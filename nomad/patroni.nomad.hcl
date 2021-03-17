job "timescaledb" {
  datacenters = ["dc1"]

  meta {
    NAMESPACE = "staging"
  }

  group "patroni" {
    count = 1
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }
    // constraint {
    //   attribute = "${node.unique.name}"
    //   value     = "minion-test000000"
    // }

    // volume "uphs_test_nomad_disk-0" {
    //   type      = "csi"
    //   read_only = false
    //   source    = "uphs_test_nomad_disk-0"
    // }

    // volume "uphs_test_nomad_disk-1" {
    //   type      = "csi"
    //   read_only = false
    //   source    = "uphs_test_nomad_disk-1"
    // }

    // volume "uphs_test_nomad_disk-2" {
    //   type      = "csi"
    //   read_only = false
    //   source    = "uphs_test_nomad_disk-2"
    // }

    // update {
    //   canary       = 3
    //   max_parallel = 3
    // }

    restart {
      mode = "delay"
    }

    network {
      mode = "host"
      port "patroni_tcp" { static = 5432 }
      port "patroni_master" { static = 8008 }
    }        

    task "patroni" {
      //user = "root"
      driver = "docker"

      locals {
        node_number = substr("${node.unique.name}", 2, 5)
      }

      env {
        NODE_NUMBER = "${node.unique.name: -1}"
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

      // volume_mount {
      //   volume      = "uphs_test_nomad_disk-${NODE_NUMBER}"
      //   destination = "/csi"
      //   read_only   = false
      // }

      template {
          destination   = "${NOMAD_TASK_DIR}/.env"
          env           = true
          data = <<EOH
PATRONI_CONSUL_HOST="{{ with service "consul" }}{{ with index . 0 }}{{ .Address }}{{ end }}{{ end }}:8500"
EOH
      }
      config {
        image = "docker.pkg.github.com/pennsignals/pennsignals_postgres/pennsignals_postgres.patroni:0.0.3-rc.4"
        dns_servers = ["127.0.0.53", "${HOST_IP}"]
        ports = [ "patroni_tcp", "patroni_master" ]
      }

      resources {
        cpu    = 300
        memory = 512
      }

      service {
        name = "patroni"
        port = "patroni_tcp"
        tags = ["ui", "${NOMAD_META_NAMESPACE}"]
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
//  {'http': 'http://10.145.242.70:8008/master', 'interval': '5s', 'DeregisterCriticalServiceAfter': '150.0s'}, 'tags': ['master']}

    }
  }
}


