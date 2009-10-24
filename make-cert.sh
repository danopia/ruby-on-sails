#!/bin/bash                                                                       

NAME=$1

if [ "$NAME" == '' ]
then
  echo "$0 <certificate name>" 1>&2
  exit 1
fi
openssl genrsa 1024 | openssl pkcs8 -topk8 -nocrypt -out $NAME.key
openssl req -new -x509 -nodes -sha1 -days 365 -key $NAME.key -out $NAME.cert
