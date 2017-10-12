#!/bin/bash

BUCKET=$1
OAUTH_MODULE=$2
OAUTH_CLASS=$3
OAUTH_CLIENT_ID=$4
OAUTH_CLIENT_SECRET=$5

# Parses a configuration file put in place by EMR to determine the role of this node
is_master() {
  if [ $(jq '.isMaster' /mnt/var/lib/info/instance.json) = 'true' ]; then
    return 0
  else
    return 1
  fi
}

if is_master; then
    # Download packages
    for i in boost162-lib-1_62_0-33.x86_64.rpm freetype2-lib-2.8-33.x86_64.rpm gcc6-lib-6.4.0-33.x86_64.rpm gdal213-lib-2.1.3-33.x86_64.rpm geonotebook-0.0.0-13.x86_64.rpm geopyspark-0.2.2-13.x86_64.rpm jupyterhub-0.7.2-13.x86_64.rpm mapnik-093fcee-33.x86_64.rpm nodejs-8.5.0-13.x86_64.rpm proj493-lib-4.9.3-33.x86_64.rpm python-mapnik-e5f107d-33.x86_64.rpm
    do
	aws s3 cp $BUCKET/$i /tmp/$i
    done

    # Install packages
    cd /tmp
    sudo yum localinstall -y boost162-lib-1_62_0-33.x86_64.rpm freetype2-lib-2.8-33.x86_64.rpm gcc6-lib-6.4.0-33.x86_64.rpm gdal213-lib-2.1.3-33.x86_64.rpm geonotebook-0.0.0-13.x86_64.rpm geopyspark-0.2.2-13.x86_64.rpm jupyterhub-0.7.2-13.x86_64.rpm mapnik-093fcee-33.x86_64.rpm nodejs-8.5.0-13.x86_64.rpm proj493-lib-4.9.3-33.x86_64.rpm python-mapnik-e5f107d-33.x86_64.rpm
    rm -f /tmp/*.rpm

    # To ensure `pkg_resources` package, may not be needed
    # NOTE: This might be causing problems with using pip-3.4
    # sudo pip-3.4 install --upgrade pip

    # install the sudospawner package for multiuser jupyterhub access
    sudo pip-3.4 install sudospawner

    # install the oauthenticator jupyterhub extension and configure
    sudo pip-3.4 install "https://github.com/jupyterhub/oauthenticator/archive/f5e39b1ece62b8d075832054ed3213cc04f85030.zip"

    # Install GeoPySpark + GeoNotebook kernel
    cat <<EOF > /tmp/kernel.json
{
    "language": "python",
    "display_name": "GeoNotebook + GeoPySpark",
    "argv": [
        "/usr/bin/python3.4",
        "-m",
        "geonotebook",
        "-f",
        "{connection_file}"
    ],
    "env": {
        "PYSPARK_PYTHON": "/usr/bin/python3.4",
        "SPARK_HOME": "/usr/lib/spark",
        "PYTHONPATH": "/usr/lib/spark/python/lib/pyspark.zip:/usr/lib/spark/python/lib/py4j-0.10.4-src.zip",
        "GEOPYSPARK_JARS_PATH": "/opt/jars",
        "YARN_CONF_DIR": "/etc/hadoop/conf",
        "PYSPARK_SUBMIT_ARGS": "--conf hadoop.yarn.timeline-service.enabled=false pyspark-shell"
    }
}
EOF
    sudo cp /tmp/kernel.json /usr/share/jupyter/kernels/geonotebook3/kernel.json
    rm -f /tmp/kernel.json

    # Linkage
    echo '/usr/local/lib' > /tmp/local.conf
    echo '/usr/local/lib64' >> /tmp/local.conf
    sudo cp /tmp/local.conf /etc/ld.so.conf.d/local.conf
    sudo ldconfig
    rm -f /tmp/local.conf

    # Set password
    echo 'hadoop:hadoop' | sudo chpasswd

    # Set up user account to manage JupyterHub
    sudo groupadd shadow
    sudo chgrp shadow /etc/shadow
    sudo chmod 640 /etc/shadow
    # sudo usermod -a -G shadow hadoop
    sudo useradd -G shadow -r hublauncher

    # Do setup for user accounts that can spawn jupyter notebook instances
    sudo groupadd jupyterhub
    sudo adduser -G hadoop,jupyterhub user
    echo 'user:password' | sudo chpasswd

    # Ensure that all members of `jupyterhub` group may log in to JupyterHub
    echo 'hublauncher ALL=(%jupyterhub) NOPASSWD: /usr/local/bin/sudospawner' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(ALL) NOPASSWD: /usr/sbin/useradd' | sudo tee -a /etc/sudoers
    echo 'hublauncher ALL=(hdfs) NOPASSWD: /usr/bin/hdfs' | sudo tee -a /etc/sudoers

    # Environment setup
    cat <<EOF > /tmp/oauth_profile.sh
export AWS_DNS_NAME=$(aws ec2 describe-network-interfaces --filters Name=private-ip-address,Values=$(hostname -i) | jq -r '.[] | .[] | .Association.PublicDnsName')
export OAUTH_CALLBACK_URL=http://\$AWS_DNS_NAME:8000/hub/oauth_callback
export OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID
export OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET

alias launch_hub='sudo -u hublauncher -E env "PATH=/usr/local/bin:$PATH" jupyterhub --JupyterHub.spawner_class=sudospawner.SudoSpawner --SudoSpawner.sudospawner_path=/usr/local/bin/sudospawner --Spawner.notebook_dir=/home/{username}'
EOF
    sudo mv /tmp/oauth_profile.sh /etc/profile.d
    . /etc/profile.d/oauth_profile.sh

    # Setup required scripts/configurations for launching JupyterHub
    cat <<EOF > /tmp/new_user
#!/bin/bash

user=\$1

sudo useradd -m -G jupyterhub,hadoop \$user
sudo -u hdfs hdfs dfs -mkdir /user/\$user

EOF
    chmod +x /tmp/new_user
    sudo chown root:root /tmp/new_user
    sudo mv /tmp/new_user /usr/local/bin
    
    cat <<EOF > /tmp/jupyterhub_config.py
from oauthenticator.$OAUTH_MODULE import $OAUTH_CLASS

c = get_config()
c.JupyterHub.authenticator_class = $OAUTH_CLASS
c.${OAUTH_CLASS}.create_system_users = True

c.JupyterHub.spawner_class='sudospawner.SudoSpawner'
c.SudoSpawner.sudospawner_path='/usr/local/bin/sudospawner'
c.Spawner.notebook_dir='/home/{username}'
c.LocalAuthenticator.add_user_cmd = ['new_user']

EOF

    # Execute
    cd /tmp
    sudo -u hublauncher -E env "PATH=/usr/local/bin:$PATH" jupyterhub --JupyterHub.spawner_class=sudospawner.SudoSpawner --SudoSpawner.sudospawner_path=/usr/local/bin/sudospawner --Spawner.notebook_dir=/home/{username} -f /tmp/jupyterhub_config.py &
else
    # Download packages
    for i in freetype2-lib-2.8-33.x86_64.rpm gcc6-lib-6.4.0-33.x86_64.rpm gdal213-lib-2.1.3-33.x86_64.rpm geopyspark-worker-0.2.2-13.x86_64.rpm proj493-lib-4.9.3-33.x86_64.rpm
    do
	aws s3 cp $BUCKET/$i /tmp/$i
    done

    # Install packages
    cd /tmp
    sudo yum localinstall -y freetype2-lib-2.8-33.x86_64.rpm gcc6-lib-6.4.0-33.x86_64.rpm gdal213-lib-2.1.3-33.x86_64.rpm geopyspark-worker-0.2.2-13.x86_64.rpm proj493-lib-4.9.3-33.x86_64.rpm
    rm -f /tmp/*.rpm

    # To ensure `pkg_resources` package, may not be needed
    sudo pip-3.4 install --upgrade pip

    # Linkage
    echo '/usr/local/lib' > /tmp/local.conf
    echo '/usr/local/lib64' >> /tmp/local.conf
    sudo cp /tmp/local.conf /etc/ld.so.conf.d/local.conf
    sudo ldconfig
    rm -f /tmp/local.conf
fi
