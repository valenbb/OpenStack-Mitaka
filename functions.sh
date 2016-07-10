#!/bin/bash

set -e -x

function ops_edit {
    crudini --set $1 $2 $3 $4
}

function ops_del {
    crudini --del $1 $2 $3
}
