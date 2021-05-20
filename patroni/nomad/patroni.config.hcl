name            = pennsignals_postgres.patroni
registry        = "docker.pkg.github.com/pennsignals/pennsignals_postgres"
tag             = 0.0.3-rc.4
cpu             = "512"
memory          = "256"
volume_indices  = ["0", "1", "2"]
environment     = "staging"