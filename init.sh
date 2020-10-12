#!/bin/bash

# setup consul

mkdir /var/lib/consul
curl -sSLf -o /tmp/consul.zip "https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip"
unzip /tmp/consul.zip -d /usr/local/bin && unlink /tmp/consul.zip

consul tls cert create -ca=/etc/consul.d/consul-agent-ca.pem -key=/etc/consul.d/consul-agent-ca-key.pem --client
mv dc1-client-consul-0.pem /etc/consul.d/consul-client.pem
mv dc1-client-consul-0-key.pem /etc/consul.d/consul-client-key.pem
rm /etc/consul.d/consul-agent-ca-key.pem

# Set Bind address to node ip
sudo sed -i 's/_CONSUL_BIND_ADDR_/'$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)'/' /etc/consul.d/configuration.json

sudo systemctl enable consul
sudo systemctl start consul

sudo /scripts/consul-integration.sh


# `lsb_release -c -s` should return the correct codename of your OS
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -c -s)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
  
# Add timescale PPA and update
sudo add-apt-repository -y -u ppa:timescale/timescaledb-ppa

# Now install appropriate package for PG version
sudo apt-get install -y timescaledb-postgresql-12 postgresql-server-dev-12
sudo timescaledb-tune --quiet --yes

# Restart PostgreSQL instance
sudo service postgresql restart

# Start Replicate script 
sudo /scripts/postgres-replicate.sh


# Restart consul to find postgres service json config
sudo systemctl restart consul

# Install semver
mkdir /tmp/pg-semver
git clone --branch v0.30.0 https://github.com/theory/pg-semver.git /tmp/pg-semver
cd /tmp/pg-semver
make 
make install
echo "# semver extension\ncomment = 'Semantic version data type'\ndefault_version = '0.30.0'\nmodule_pathname = '$libdir/semver'\nrelocatable = true\n" > /usr/local/share/postgresql/extension/semver.control
