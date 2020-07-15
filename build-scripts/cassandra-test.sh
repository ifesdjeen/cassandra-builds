#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o pipefail
set -o nounset

# lists all tests for the specific test type
_list_tests() {
  local readonly classlistprefix="$1"
  find "test/$classlistprefix" -name '*Test.java' | sed "s;^test/$classlistprefix/;;g"
}

_list_distributed_tests_no_upgrade() {
  _list_tests "distributed" | grep -v "upgrade"
}

_timeout_for() {
  grep "name=\"$1\"" build.xml | awk -F'"' '{print $4}'
}

_main() {
  local target="${1:-}"
  local java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F. '{print $1}')
  local version=$(grep 'property\s*name=\"base.version\"' build.xml |sed -ne 's/.*value=\"\([^"]*\)\".*/\1/p')
  if [ "$java_version" -ge 11 ]; then
    export CASSANDRA_USE_JDK11=true
    if ! grep -q CASSANDRA_USE_JDK11 build.xml ; then
        echo "Skipping ${target}. JDK11 not supported against ${version}"
        exit 0
    fi
  fi

  # check test target exists in code
  case $target in
    "stress-test" | "fqltool-test")
      ant -projecthelp | grep -q " $target " || { echo "Skipping ${target}. It does not exist in ${version}"; exit 0; }
      ;;
    "test-cdc")
      regx_version="2.2([0-9]+)$"
      ! [[ $version =~ $version ]] || { echo "Skipping ${target}. It does not exist in ${version}"; exit 0; }
      ;;
    *)
      ;;
  esac

  ant clean jar
  mkdir -p tmp

  case $target in
    "stress-test" | "fqltool-test")
      ant $target -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    "test")
      ant testclasslist -Dtest.classlistfile=<( _list_tests "unit" ) -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    "test-cdc")
      ant testclasslist-cdc -Dtest.classlistfile=<( _list_tests "unit" ) -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    "test-compression")
      ant testclasslist-compression -Dtest.classlistfile=<( _list_tests "unit" ) -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    "test-burn")
      ant testclasslist -Dtest.classlistprefix=burn -Dtest.timeout=$(_timeout_for "test.burn.timeout") -Dtest.classlistfile=<( _list_tests "burn" ) -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    "long-test")
      ant testclasslist -Dtest.classlistprefix=long -Dtest.timeout=$(_timeout_for "test.long.timeout") -Dtest.classlistfile=<( _list_tests "long" ) -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    "jvm-dtest")
      ant testclasslist -Dtest.classlistprefix=distributed -Dtest.timeout=$(_timeout_for "test.distributed.timeout") -Dtest.classlistfile=<( _list_distributed_tests_no_upgrade ) -Dtmp.dir="$(pwd)/tmp" || echo "failed $target"
      ;;
    *)
      echo "unregconised \"$target\""
      exit 1
      ;;
  esac
}

_main "$@"
