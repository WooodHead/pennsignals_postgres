#!/bin/bash

# Postgres IP adresses
MASTER=170.166.25.159
STANDBY=("170.166.25.160 170.166.25.161")

IP=$(/sbin/ip -o -4 addr list ens192 | awk '{print $4}' | cut -d/ -f1)
PGDATA="/var/lib/pgsql/12/data"


# setup MASTER
if [ "$IP" == "$MASTER" ]; then
    echo "Setting up Master"
    # setup default password
    sudo -u postgres psql -c "alter user postgres with password 'password'" 

    # as postgres
    sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses TO '*'"

    # as root, restart the service
    sudo systemctl restart postgresql-12

    sudo -u postgres psql -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'secret';"

    # add ip addresses to pg_hba.conf
    cat pg_hba.conf >> $PGDATA/pg_hba.conf

    # reload to set changes
    sudo -u postgres psql -c "select pg_reload_conf()"

    # very replication
    psql -x -c "select * from pg_stat_replication"
    
    # SAMPLE
    #####################################################
    # -[ RECORD 1 ]----+------------------------------
    # pid | 2522
    # usesysid | 16384
    # usename | replicator
    # application_name | walreceiver
    # client_addr | 192.168.0.107
    # client_hostname |
    # client_port | 36382
    # backend_start | 2019-10-08 17:15:19.658917-04
    # backend_xmin |
    # state | streaming
    # sent_lsn | 0/CB02A90
    # write_lsn | 0/CB02A90
    # flush_lsn | 0/CB02A90
    # replay_lsn | 0/CB02A90
    # write_lag | 00:00:00.095746
    # flush_lag | 00:00:00.096522
    # replay_lag | 00:00:00.096839
    # sync_priority | 0
    # sync_state | async
    # reply_time | 2019-10-08 17:18:04.783975-04
    #####################################################


# setup STANDBY
elif [[ " ${STANDBY[@]} " =~ " ${IP} " ]]; then

    echo "Setting up Standby"

    # execute on standby server
    pg_basebackup -h $MASTER -U replicator -p 5432 -D $PGDATA -Fp -Xs -P -R

    pg_ctl -D $PGDATA start

fi



