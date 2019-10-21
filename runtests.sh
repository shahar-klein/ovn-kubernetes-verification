#!/bin/bash

PWD=`dirname $0`

bash $PWD/verify-dns.sh
bash $PWD/ping1.sh
bash $PWD/webDBSvc.sh
