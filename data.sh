#!/bin/bash
set -e -u

TMP=`mktemp -d tmpXXXX`
createdb -U postgres -T template_postgis $TMP
curl -sfo $TMP/qs_adm0.zip http://static.quattroshapes.com/qs_adm0.zip
unzip -q $TMP/qs_adm0.zip -d $TMP
ogr2ogr -nlt MULTIPOLYGON -nln import -f "PostgreSQL" PG:"host=localhost user=postgres dbname=$TMP" $TMP/qs_adm0.shp


echo "
CREATE TABLE data(id SERIAL PRIMARY KEY, name VARCHAR, search VARCHAR, population INTEGER, iso2 VARCHAR, lon FLOAT, lat FLOAT, bounds VARCHAR);
SELECT AddGeometryColumn('public', 'data', 'geometry', 4326, 'MULTIPOLYGON', 2);
INSERT INTO data (id, search, population, iso2) SELECT ogc_fid, qs_adm0 AS search, qs_pop, qs_iso_cc FROM import;
INSERT INTO data (name, geometry)
    -- 4. piece together the now postive-spaces polygons we created in (3) so that we have one 
    -- geom object per country
    SELECT qs_adm0 as name, st_union(geom) AS geometry
    FROM (
        -- 3. dump interior rings, turn them into polygons. this creates many multipolygon rings, 
        -- undoes (2), but those rings are their own objects, no longer interior rings.
        SELECT qs_adm0, st_makepolygon(st_exteriorring((st_dump(geom)).geom)) AS geom 
        FROM (
            -- 2. each country now has piles of merged qs+eez polygons, one for each ring of 
            -- each country's multipolygon object.
            -- perform aggregate union to group these by country.
            SELECT qs_adm0, st_union(union_geom) AS geom
            FROM (
                -- 1. union qs and eez polygons, coalesce() so that if there's no eez geom, 
                -- we still get the qs geom. this coalesce() preserves landlocked polygons.
                SELECT qs_adm0, coalesce(st_union(qs.geom,eez.geom), qs.geom) AS union_geom 
                FROM qs LEFT JOIN eez ON qs_adm0_a3 = iso_3digit
                WHERE qs_adm0 = 'Chile'
            ) AS one_object
            GROUP BY qs_adm0
        ) as noslivers
    ) as one_object_again
    GROUP BY qs_adm0_a3;
UPDATE data SET lon = st_x(st_pointonsurface(geometry)), lat = st_y(st_pointonsurface(geometry)), bounds = st_xmin(geometry)||','||st_ymin(geometry)||','||st_xmax(geometry)||','||st_ymax(geometry);
" | psql -U postgres $TMP

ogr2ogr -s_srs EPSG:4326 -t_srs EPSG:900913 -f "SQLite" -nln data qs-countries.sqlite PG:"host=localhost user=postgres dbname=$TMP" data
dropdb -U postgres $TMP
rm -rf $TMP
 
echo "
UPDATE data SET search='United States of America, United States, America, USA, US' WHERE iso2 = 'US';
UPDATE data SET search='United Kingdom, UK' WHERE iso2 = 'GB';
UPDATE data SET search='Canada, CA' WHERE iso2 = 'CA';
UPDATE data SET search='Colombia, Columbia' WHERE iso2 = 'CO';
UPDATE data SET search='Australia, AU' WHERE iso2 = 'AU';
UPDATE data SET search='Germany, DE' WHERE iso2 = 'DE';
UPDATE data SET search='France, FR' WHERE iso2 = 'FR';
UPDATE data SET search='South Korea, Korea' WHERE iso2 = 'KR';
UPDATE data SET search='Democratic Republic of the Congo, DRC' WHERE iso2 = 'CD';
UPDATE data SET search='United Arab Emirates, UAE' WHERE iso2 = 'AE';
" | sqlite3 qs-countries.sqlite

echo "Written to qs-adm0.sqlite."
