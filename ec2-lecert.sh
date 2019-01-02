#!/bin/bash

err() {
  echo "$@" >&2
}

out() {
  echo "$@"
}

force=""
email="help@u.plus"
cert_prod_fp=""
key_prod_fp=""
services=""

while getopts ":fm:c:k:s:" opt ; do
  case $opt in
    f)
      force="--force-renewal"
      ;;
    m)
      email="$OPTARG"
      ;;
    c)
      cert_prod_fp="$OPTARG"
      ;;
    k)
      key_prod_fp="$OPTARG"
      ;;
    s)
      services="$OPTARG" #nginx apache sshd ... -> systemctl
      ;;
    \?)
      err "Unknown option: $OPTARG"
      ;;
  esac
done

shift $(($OPTIND - 1))

#TODO: get list of domains and grab LE for all -> -d dom1 -d dom2 ...
#parse it from $@
#do it so I can do eg. ls | xargs ec2_lecert.sh -f
#domain="mmtest.utdigit.com"
domains="$@"
shift

##########
## MAIN ##
##########

if [ -z "$domains" ] ; then
  out "No domains received."
  exit 1
fi

opt_domains=""
for domain in $domains ; do
  opt_domains="-d $domain $opt_domains"
done

opts="-n -v --email $email --standalone --agree-tos"

if [ -n "$force" ] ; then
  opts="$opts $force"
fi

#kill processes blocking 443 and 80
#netstat -tulpn | tr -s ' ' | cut -d' ' -f4,7 | grep ':80 '  | cut -d' ' -f2 \
#               | cut -d'/' -f1 | sort -u
#netstat -tulpn | tr -s ' ' | cut -d' ' -f4,7 | grep ':443 ' | cut -d' ' -f2 \
#               | cut -d'/' -f1 | sort -u
#BETTER: kill and revive them manually in crontab

for service in $services ; do
  systemctl stop "$service"
done

cert=$(letsencrypt certonly $opts $opt_domains 2>&1)

for service in $services ; do
  systemctl start "$service"
done

if echo "$cert" | grep 'ert not yet due for renewal' ; then
  err "Cert not yet due for renewal."
  exit 0
fi

cert_fp=$(echo "$cert" | tr -d $'\n' | \
            sed 's#.*\(/etc/[a-z/\.]*/fullchain\.pem\).*#\1#')

key_fp=$(echo "$cert_fp" | rev | cut -d'/' -f2- | rev)"/privkey.pem"
#key_fp="$key_fp/privkey.pem"

#err "Cert: $cert_fp"
#err "Key:  $key_fp"

if [ -n "$cert_prod_fp" ] ; then
  rm "$cert_prod_fp" 2>/dev/null
  ln -s "$cert_fp" "$cert_prod_fp"
fi

if [ -n "$key_prod_fp" ] ; then
  rm "$key_prod_fp" 2>/dev/null
  ln -s "$key_fp" "$key_prod_fp"
fi

