{ pkgs, inputs, ... }: let
  version = "10.0.0";
  PBR_VERSION=version;
in {
  zuul = pkgs.python3Packages.buildPythonApplication {
    pname = "zuul";
    inherit version PBR_VERSION;
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
      pip
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
    ];
    nativeBuildInputs = with pkgs; [
      which
    ];
    doCheck = false;
  };
}
