{ pkgs, inputs, ... }: let
    version = "${builtins.toString inputs.zuul.revCount}";
in {
  zuul = pkgs.python3Packages.buildPythonApplication {
    pname = "zuul";
    inherit version;
    PBR_VERSION = version;
    src = inputs.zuul;
    propagatedBuildInputs = with pkgs.python3Packages; [
      alembic
      tzlocal
      apscheduler
      voluptuous
      prometheus-client
      graphene
      github3-py
      virtualenv
      babel
      prettytable
      beautifulsoup4
      elastic-transport
      netaddr
      kazoo
      pbr
      google-cloud-pubsub
      boto3
      python-dateutil
      pyyaml
      GitPython
      paramiko
      python-daemon
      extras
      confluent-kafka
      statsd
      opentelemetry-exporter-otlp-proto-http
      opentelemetry-exporter-otlp-proto-grpc
      psycopg2
      pymysql
      elasticsearch
      cheroot
      jsonpath-rw
      routes
      ws4py
      paho-mqtt
      google-re2
      psutil
      pyjwt
      cachecontrol
      setuptools_scm
    ];
    nativeBuildInputs = with pkgs; [
      which
    ];
    doCheck = false;
  };
}
