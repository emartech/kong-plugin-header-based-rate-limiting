#!/bin/bash

echo "Checking whether PostgreSQL is available"

export PGPASSWORD=$KONG_PG_PASSWORD

function is_ready {
    psql -h $KONG_PG_HOST -U $KONG_PG_USER -p $KONG_PG_PORT -c "select 1" 1>/dev/null 2>/dev/null
}

retry_count=70
counter=0

is_ready
x=$?

while [ $x -ne 0 -a $counter -lt $retry_count ] ; do
    echo "Waiting for PostgreSQL to become available"

    counter=`expr $counter + 1`

    sleep 1

    is_ready
    x=$?
done

if [ $counter -eq $retry_count ] ; then
    echo "PostgreSQL is not available" 1>&2
    exit 1
else
    echo "PostgreSQL is available"
    exec "$@"
fi
