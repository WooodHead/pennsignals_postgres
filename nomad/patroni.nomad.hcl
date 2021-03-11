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
      port "etcd_http" { static = 2380 }
    }

    task "etcd" {
      user = "root"
      driver = "docker"

      env {
        HOST_ADDR = "${attr.unique.network.ip-address}"
        ETCD_LISTEN_PEER_URLS = "http://0.0.0.0:2380"
        ETCD_LISTEN_CLIENT_URLS = "http://0.0.0.0:2379"
        ETCD_INITIAL_CLUSTER = "etcd1=http://consul.etcd1.service:2380,etcd2=http://consul.etcd2.service:2380,etcd3=http://consul.etcd3.service:2380"
        ETCD_INITIAL_CLUSTER_STATE = "new"
        ETCD_INITIAL_CLUSTER_TOKEN = "test"
      }

      config {
        image = "docker.pkg.github.com/pennsignals/pennsignals_postgres/patroni:0.0.1"
        command = "etcd"
        args = [
            "-name", "etcd-${attr.unique.hostname}", 
            "-initial-advertise-peer-urls", "${NOMAD_ADDR_etcd_http}"
        ]
        dns_servers = ["127.0.0.1", "${HOST_ADDR}"]
        ports = [ "etcd_http" ]
      }

      service {
        name = "etcd"
        port = "etcd_http"
        tags = ["monitoring", "${NOMAD_META_NAMESPACE}", "etcd"]
        check {
          name = "etcd TCP Check"
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
      port "patroni_tcp" { static = 5432 }
    }    
    
    task "patroni" {
      user = "root"
      driver = "docker"

      env {
        # Consul template
        ETCDCTL_ENDPOINTS = "{{ range services }}{{ range service .Name }}{{if in .Tags "etcd"}}{{ .Address }}{{if ne $index 0}},{{end}}{{end}}{{end}}{{end}}"
        PATRONI_ETCD3_HOSTS = "{{ range services }}{{ range service .Name }}{{if in .Tags "etcd"}}{{if ne $index 0}},{{end}}{{ .Address }}',{{end}}{{end}}{{end}}"
        // ETCDCTL_ENDPOINTS = "http://etcd1:2379,http://etcd2:2379,http://etcd3:2379"
        // PATRONI_ETCD3_HOSTS = "'etcd1:2379','etcd2:2379','etcd3:2379'"
        PATRONI_SCOPE = "demo"
        PATRONI_NAME = "${node.unique.name}"
      }

      config {
        image = "docker.pkg.github.com/pennsignals/pennsignals_postgres/patroni:0.0.1"
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


