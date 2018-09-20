#! /bin/bash -e

MAIN_REPO="EXTERNAL REPO GOES HERE"
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PORT=${PORT:-8880}
mkdir -p ${CHARTPROXY_STORAGE}

# adapted from https://github.com/helm/chartmuseum/blob/master/scripts/mirror_k8s_repos.sh
update-mirror() {
  qpushd ${CHARTPROXY_STORAGE}
  trap "rm -f index.yaml" EXIT
  local repo_url="$1"
  rm -f index.yaml
  curl -sLO ${MAIN_REPO}/index.yaml
  tgzs="$(ruby -ryaml -e \
      "YAML.load_file('index.yaml')['entries'].each do |k,e|;for c in e;puts c['urls'][0];end;end")"
  for tgz in ${tgzs}; do
      if [[ ! -f "${tgz##*/}" ]]; then
          curl -sLO ${MAIN_REPO}/${tgz}
          echo Downloaded ${tgz/charts\//}
      fi
  done
  rm -f index.yaml
  qpopd
  helm repo update
}

reset() {
  rm -f ${CHARTPROXY_STORAGE}/*.tgz
  update-mirror
}

add-repo() {
  helm repo add paxos-charts-dev $1
  helm repo update
}

run-museum() {
  if [[ ! -e "${CHARTPROXY_STORAGE}/.pid" ]]; then
    chartmuseum --port=${PORT} \
      --allow-overwrite \
      --storage="local" \
      --storage-local-rootdir="${CHARTPROXY_STORAGE}" &
    echo $! > ${CHARTPROXY_STORAGE}/.pid
  else
    echo chartproxy already running with pid $(cat ${CHARTPROXY_STORAGE}/.pid)
  fi

  echo waiting for chartproxy to start
  until curl localhost:${PORT} >/dev/null 2> /dev/null; do
    sleep 1
  done
  echo
  add-repo http://localhost:${PORT}
}

stop-museum() {
  if [[ -e ${CHARTPROXY_STORAGE}/.pid ]]; then
    pid=$(cat ${CHARTPROXY_STORAGE}/.pid)
    rm -f ${CHARTPROXY_STORAGE}/.pid
    kill ${pid} || true
  fi
  add-repo ${MAIN_REPO}
}

usage() {
    echo COMMANDS
    echo "start         run proxy and set paxos-charts-dev to proxy"
    echo "stop          stop proxy and set paxos-charts-dev to ${MAIN_REPO}"
    echo "update        add all charts in ${MAIN_REPO} to proxy"
    echo "reset         reset the proxy to the state of ${MAIN_REPO}"
    echo "                useful for removing versions that you want replaced by ${MAIN_REPO}"
    echo "pack FILE     tar the contents of your proxy, producing FILE"
    echo "                useful for sending the current chart repo to out-of-office coworkers"
    echo "unpack FILE   replace your chart storage with FILE"
}

get-file() {
  if [[ -z "$1" ]]; then
    echo A file must be specified
    usage
    exit 1
  fi
  realpath $1
}

pack() {
  local file=`get-file $1`
  qpushd ${CHARTPROXY_STORAGE}
  tar czf ${file} *.tgz
  qpopd
}

unpack() {
  local file=`get-file $1`
  qpushd ${CHARTPROXY_STORAGE}
  tar xzf ${file}
  qpopd
}

case $1 in
  "start")
    run-museum
    ;;
  "stop")
    stop-museum
    ;;
  "update")
    update-mirror
    ;;
  "reset")
    reset
    ;;
  "pack")
    pack $2
    ;;
  "unpack")
    unpack $2
    ;;
  "help")
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac
