#!/bin/bash
set -e -u

# this is scary and probably a terrible idea. 
admin_level=$(echo $1 | sed 's/\..*//')

# convert to sqlite to gernerate a quicker list of features
if test -e data/${admin_level}.sqlite
then
    echo ${admin_level}.sqlite "already exists!"
else 
    ogr2ogr -f "SQLite" data/${admin_level}.sqlite $1
fi

countries=$(sqlite3 data/${admin_level}.sqlite "select coalesce(qs_a0, qs_a0_alt) from ${admin_level} order by qs_a0" | sed 's/\ /-/g')

for country in $countries
do
    j=$(echo $country | sed 's/-/ /g')
    ogr2ogr \
        -overwrite \
        -f "GeoJSON" \
        -sql "select * from qs_adm0 where qs_a0 = '$j'" \
        data/${country}.geojson \
        data/${admin_level}.sqlite

    topojson \
        --bbox \
        --no-quantization \
        data/${country}.geojson \
        -o data/${country}.json

    rm -rf data/${country}.geojson
done