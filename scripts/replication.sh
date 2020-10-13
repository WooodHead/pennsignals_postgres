#!/bin/bash
IP=$(/sbin/ip -o -4 addr list ens192 | awk '{print $4}' | cut -d/ -f1)
CONSUL_HTTP_TOKEN=$(consul kv get service/consul/bootstrap-token)

# Put the Session on on the first consul node
CONSUL_NODE=$(curl --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" http://localhost:8500/v1/agent/members | jq '.[] |  .Name ' | grep consul | head -1)
SESSION_DATA="{ \"LockDelay\": \"15s\", \"Name\": \"postgres-lock\", \"Node\": ${CONSUL_NODE}, \"Checks\": [\"serfHealth\"], \"Behavior\": \"release\", \"TTL\": \"300s\" }"

# Then, create a consul session for postgres service
SESSION_ID=$(curl --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" -fX PUT -d "$SESSION_DATA" http://localhost:8500/v1/session/create | jq -r '.ID')

# curl --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" http://localhost:8500/v1/agent/members | jq '.[] |  .Name ' | grep consul


# Write the key and aquire a lock (if it's the leader)
consul kv put -token $CONSUL_HTTP_TOKEN -acquire -session $SESSION_ID service/postgres/leader "{\"Name\": \"$(hostname)\", \"IP\": \"$IP\"}"
# curl --header "X-Consul-Token: $CONSUL_HTTP_TOKEN" -X PUT -d "{\"Name\": \"$(hostname)\", \"IP\": \"${IP}\"}" http://localhost:8500/v1/kv/lead?acquire=$SESSION_ID

# get the leader name

# Lock all instances until we decide a leader
# consul lock -token $CONSUL_HTTP_TOKEN -verbose -name postgres_leader service/postgres/leader /tmp/postgres-get-leader.sh

LEADER_NAME=$(consul kv get -token $CONSUL_HTTP_TOKEN service/postgres/leader | jq -r ".Name")
LEADER_IP=$(consul kv get -token $CONSUL_HTTP_TOKEN service/postgres/leader | jq -r ".IP")

echo "$LEADER_NAME : $LEADER_IP"

# Get the repicas
REPLICAS=$(curl --header "X-Consul-Token: ${CONSUL_HTTP_TOKEN}" http://localhost:8500/v1/agent/members | jq '.[] |  .Name | sub("[-]+";"_")' | grep postgres | grep -v $(echo $LEADER_NAME | sed -e 's/-/_/'))

# Copy default release settings to dev location
#sudo cp -R /etc/postgresql/12/main/* /var/lib/postgresql/12/main/

#PGDATA=/var/lib/postgresql/12/main/
PGDATA=/etc/postgresql/12/main/

REPLICA_NAME=$(hostname)

# CREATE signals user and root user
sudo -u postgres psql -U postgres -d postgres -c "CREATE USER signals WITH SUPERUSER PASSWORD 'datascience';"
sudo -u postgres psql -U postgres -d postgres -c "CREATE USER root WITH SUPERUSER;"

# Change local permissions to trust
PEER='local   all             all                                     peer'
TRUST='local   all             all                                     trust'
sudo sed -i "s/$PEER/$TRUST/" ${PGDATA}/pg_hba.conf 

sudo sed -i 's/_CONSUL_BIND_ADDR_/'$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)'/' /etc/consul.d/configuration.json


if [ "$LEADER_NAME" == "$(hostname)" ]; then

echo "Configure PRIMARY PostgreSQL"
export "POSTGRES_ROLE=PRIMARY"

POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
REPLICA_POSTGRES_USER=repuser
REPLICA_POSTGRES_PASSWORD=repuser
REPLICATE_TO=$LEADER_IP
SYNCHRONOUS_COMMIT=off

echo "Creating replica user and password"
psql -d postgres -c "SET password_encryption = 'scram-sha-256'; CREATE ROLE $REPLICA_POSTGRES_USER WITH REPLICATION PASSWORD '$REPLICA_POSTGRES_PASSWORD' LOGIN;"

# Add replication settings to primary postgres conf
cat >> ${PGDATA}/postgresql.conf <<EOF
listen_addresses= '*'
wal_level = replica
max_wal_senders = 2
max_replication_slots = 2
synchronous_commit = ${SYNCHRONOUS_COMMIT}
EOF

# Add synchronous standby names if we're in one of the synchronous commit modes
if [[ "${SYNCHRONOUS_COMMIT}" =~ ^(on|remote_write|remote_apply)$ ]]; then
cat >> ${PGDATA}/postgresql.conf <<EOF
synchronous_standby_names = '1 (${REPLICA_NAME})'
EOF
fi

# Add replication settings to primary pg_hba.conf
# Get the subnet of out postgres Databases
# if  [[ -z $REPLICATION_SUBNET ]]; then
#     REPLICATION_SUBNET=$(getent hosts ${REPLICATE_TO} | awk '{ print $1 }')/28
# fi

cat >> ${PGDATA}/pg_hba.conf <<EOF
host     replication     ${REPLICA_POSTGRES_USER}   ${LEADER_IP}/24       scram-sha-256
host     all             all                        10.146.0.0/21         md5

EOF

# Restart postgres and add replication slot
# pg_ctl -D ${PGDATA} -m fast -w restart
sudo systemctl restart postgresql
echo "Creating replica slots for each replica DB"
while read name; do 
    echo "${name:1:-1}";
    psql -d postgres -c "SELECT * FROM pg_create_physical_replication_slot('${name:1:-1}_slot');"; 
done <<< "$REPLICAS"

# sudo -u postgres psql -U postgres -c "SELECT * FROM pg_create_physical_replication_slot('${REPLICA_NAME}_slot');"

# CONFIGURE REPLICA
else

echo "Configure REPLICA PostgreSQL"
export "POSTGRES_ROLE=REPLICA"


POSTGRES_USER=repuser
POSTGRES_PASSWORD=repuser
REPLICATE_FROM=$LEADER_IP
# Stop postgres instance and clear out PGDATA
# pg_ctl -D ${PGDATA} -m fast -w stop
sudo systemctl stop postgresql
rm -rf ${PGDATA}

# Create a pg pass file so pg_basebackup can send a password to the primary
cat > ~/.pgpass.conf <<EOF
*:5432:replication:${POSTGRES_USER}:${POSTGRES_PASSWORD}
EOF
chown postgres:postgres ~/.pgpass.conf
chmod 0600 ~/.pgpass.conf

# Backup replica from the primary
until PGPASSFILE=~/.pgpass.conf pg_basebackup -h ${REPLICATE_FROM} -D ${PGDATA} -U ${POSTGRES_USER} -vP -w
do
    # If docker is starting the containers simultaneously, the backup may encounter
    # the primary amidst a restart. Retry until we can make contact.
    sleep 1
    echo "Retrying backup . . ."
done

# Remove pg pass file -- it is not needed after backup is restored
rm ~/.pgpass.conf

# Create the recovery.conf file so the backup knows to start in recovery mode
cat > ${PGDATA}/recovery.conf <<EOF
standby_mode = on
primary_conninfo = 'host=${REPLICATE_FROM} port=5432 user=${POSTGRES_USER} password=${POSTGRES_PASSWORD} application_name=${REPLICA_NAME}'
primary_slot_name = '${REPLICA_NAME}_slot'
EOF

# Ensure proper permissions on recovery.conf
chown postgres:postgres ${PGDATA}/recovery.conf
chmod 0600 ${PGDATA}/recovery.conf

# pg_ctl -D ${PGDATA} -w start
sudo systemctl start postgresql


fi
