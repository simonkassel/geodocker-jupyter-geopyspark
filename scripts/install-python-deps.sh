#!/usr/bin/env bash

USER=$1
GROUP=$2

export CPPFLAGS="-I$HOME/local/gdal/include"
export CFLAGS="-I$HOME/local/gdal/include"
export LDFLAGS="-I$HOME/local/gdal/lib"

# aquire
chown -R root:root $HOME/.cache/pip $HOME/.local

# install geopsypark's friends
pip3 install --user appdirs==1.4.3
pip3 install --user fastavro==0.13.0
pip3 install --user numpy==1.12.1
pip3 install --user pyparsing==2.2.0
pip3 install --user six==1.10.0
pip3 install --user packaging==16.8
pip3 install --user Shapely==1.6b4
pip3 install --user rasterio==1.0a7

# install geonotebook's friends
PATH=$PATH:$HOME/local/gdal/bin pip3 install --user GDAL==2.1.3
pip3 install --user requests==2.11.1
pip3 install --user promise==0.4.2
pip3 install --user fiona==1.7.1
pip3 install --user matplotlib==2.0.0
CFLAGS='-DPI=M_PI -DHALFPI=M_PI_2 -DFORTPI=M_PI_4 -DTWOPI=(2*M_PI) -I$HOME/local/gdal/include' pip3 install --user pyproj==1.9.5.1
pip3 install pandas==0.19.2
pip3 install lxml==3.7.3

# mark
touch $HOME/.local/lib/python3.4/site-packages/.xxx

# release
chown -R $USER:$GROUP $HOME/.cache/pip $HOME/.local
