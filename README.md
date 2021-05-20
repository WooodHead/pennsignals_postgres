# pennsignals_postgres
PennSignal's Postgres setup and replication scripts 

## Update patroni image on PennSignals

- Stop timescaledb nomad job
- delete patroni created consul configs at `service/timescaledb/`
  - all files except `patroni.yml`
- start timescaledb nomad job