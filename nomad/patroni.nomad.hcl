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
      port "etcd_peer_http" { static = 2380 }
      port "etcd_client_http" { static = 2379 }
    }

    task "etcd" {
      //user = "root"
      driver = "docker"

      env {
        HOST_IP = "${attr.unique.network.ip-address}"
        ETCD_LISTEN_PEER_URLS = "http://0.0.0.0:2380"
        ETCD_LISTEN_CLIENT_URLS = "http://0.0.0.0:2379"
        // ETCD_INITIAL_CLUSTER = "etcd1=http://consul.etcd1.service:2380,etcd2=http://consul.etcd2.service:2380,etcd3=http://consul.etcd3.service:2380"
        ETCD_INITIAL_CLUSTER = "${attr.unique.hostname}=http://${NOMAD_ADDR_etcd_peer_http}"
        ETCD_INITIAL_CLUSTER_STATE = "new"
        ETCD_INITIAL_CLUSTER_TOKEN = "test"
      }
        //${attr.unique.hostname}
      config {
        image = "docker.pkg.github.com/pennsignals/pennsignals_postgres/pennsignals_postgres.patroni:0.0.2"
        command = "etcd"
        args = [
            "-name", "${attr.unique.hostname}", 
            "-initial-advertise-peer-urls", "http://${NOMAD_ADDR_etcd_peer_http}",
            "-advertise-client-urls", "http://${NOMAD_ADDR_etcd_client_http}"
        ]
        dns_servers = ["127.0.0.1", "${HOST_IP}"]
        ports = [ "etcd_peer_http", "etcd_client_http"]
      }

      service {
        name = "etcd-peer"
        port = "etcd_peer_http"
        tags = ["monitoring", "${NOMAD_META_NAMESPACE}", "etcd-peer"]
        check {
          name = "etcd peer TCP Check"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }
      service {
        name = "etcd-client"
        port = "etcd_client_http"
        tags = ["monitoring", "${NOMAD_META_NAMESPACE}", "etcd-client"]
        check {
          name = "etcd client TCP Check"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }
    }
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

    network {
      mode = "host"
      port "patroni_tcp" { static = 6432 }
    }    
    
    task "patroni" {
      //user = "root"
      driver = "docker"

      env {
        // Consul template
        // ETCDCTL_ENDPOINTS = "http://etcd1:2379,http://etcd2:2379,http://etcd3:2379"
        // PATRONI_ETCD3_HOSTS = "'etcd1:2379','etcd2:2379','etcd3:2379'"
        HOST_IP = "${attr.unique.network.ip-address}"
        PATRONI_SCOPE = "demo"
        PATRONI_NAME = "${node.unique.name}"
      }
      template {
          destination   = "${NOMAD_TASK_DIR}/.env"
          env           = true
          data = <<EOH
ETCDCTL_ENDPOINTS="{{ range services }}{{ range service .Name }}{{if in .Tags "etcd-client"}}http://{{ .Address }}:{{ .Port }},{{end}}{{end}}{{end}}"
PATRONI_ETCD3_HOSTS="{{ range services }}{{ range service .Name }}{{if in .Tags "etcd-client"}}'{{ .Address }}:{{ .Port }}',{{end}}{{end}}{{end}}"
EOH
      }
      config {
        image = "docker.pkg.github.com/pennsignals/pennsignals_postgres/pennsignals_postgres.patroni:0.0.2"
        ports = [ "patroni_tcp" ]
        //command = "tail -f /dev/null"
        dns_servers = ["127.0.0.1", "${HOST_IP}"]
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


