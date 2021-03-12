job "timescaledb" {
  datacenters = ["dc1"]

  meta {
    NAMESPACE = "staging"
  }

  group "etcd" {
      count = 3
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    restart {
      mode = "delay"
    }

    network {
      mode = "host"
      port "patroni_tcp" { static = 6432 }
    }    


  group "patroni" {
    count = 3
    constraint {
      operator  = "distinct_hosts"
      value     = "true"
    }

    restart {
      mode = "delay"
    }
    
    task "patroni" {
      //user = "root"
      driver = "docker"

      env {
        HOST_IP = "${attr.unique.network.ip-address}"
        PATRONI_SCOPE = "test"
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

        PATRONI_CONSUL_HOST = "consul.service.consul:8500"
        PATRONI_CONSUL_SCHEME = "http"
      }

      config {
        image = "docker.pkg.github.com/pennsignals/pennsignals_postgres/pennsignals_postgres.patroni:0.0.3-rc.2"
        dns_servers = ["127.0.0.1", "${HOST_IP}"]
        ports = [ "patroni_tcp" ]
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
      }
    }
  }
}


