{ self, pkgs, ... }: {
  "test" = pkgs.testers.runNixOSTest {
    name = "minimal-test";

    nodes = let
      certs = {
        ca = let 
          certandkey = pkgs.stdenv.mkDerivation {
            name = "ca";
            dontUnpack = true;
            buildInputs = with pkgs; [ openssl ];
            buildPhase = ''
              openssl req \
                -newkey rsa:4096 \
                -x509 \
                -sha256 \
                -nodes \
                -subj "/CN=root" \
                -keyout ca.key \
                -out ca.pem \
                -days 3650
            '';
            installPhase = ''
              mkdir -p $out
              mv ca.key $out/ca.key
              mv ca.pem $out/ca.pem
            '';
          };
        in {
          cert = "${certandkey}/ca.pem";
          key = "${certandkey}/ca.key";
        };
        zuul = let
          certandkey = pkgs.stdenv.mkDerivation {
            name = "zuul-certs";
            dontUnpack = true;
            buildInputs = with pkgs; [ openssl ];
            buildPhase = ''
              openssl req \
                -new \
                -newkey rsa:4096 \
                -subj "/C=SE/CN=zuul" \
                -keyout "client.key" \
                -nodes \
                -out "client.csr"

              openssl x509 \
                -req \
                -CA "${certs.ca.cert}" \
                -CAkey "${certs.ca.key}" \
                -copy_extensions copy \
                -set_serial "0x$(openssl rand -hex 8)" \
                -in "client.csr" \
                -out "client.pem" \
                -days 367 \
                -sha256
            '';
            installPhase = ''
              mkdir -p $out
              mv client.key $out/client.key
              mv client.pem $out/client.pem
            '';
          };
        in {
          cert = "${certandkey}/client.pem";
          key = "${certandkey}/client.key";
        };
        zookeeper = let
          keystore = pkgs.stdenv.mkDerivation {
            name = "zookeeper-certs";
            dontUnpack = true;
            buildInputs = with pkgs; [ openssl ];
            buildPhase = ''
              openssl req \
                -new \
                -newkey rsa:4096 \
                -subj "/C=SE/CN=zookeeper" \
                -keyout "client.key" \
                -nodes \
                -out "client.csr"

              openssl x509 \
                -req \
                -CA "${certs.ca.cert}" \
                -CAkey "${certs.ca.key}" \
                -copy_extensions copy \
                -set_serial "0x$(openssl rand -hex 8)" \
                -in "client.csr" \
                -out "client.pem" \
                -days 367 \
                -sha256
            '';
            installPhase = ''
              mkdir -p $out
              cat client.key client.pem > $out/client.pem
            '';
          };
        in {
          keystore = "${keystore}/client.pem";
        };
      };
    in {
      zookeeper = { config, pkgs, ... }: {
        networking.firewall.allowedTCPPorts = [ 2281 ];
        services.zookeeper = {
          enable = true;
          extraConf = ''
            # Necessary for TLS support
            serverCnxnFactory=org.apache.zookeeper.server.NettyServerCnxnFactory

            # Client TLS configuration
            secureClientPort=2281
            ssl.keyStore.location=${certs.zookeeper.keystore}
            ssl.trustStore.location=${certs.ca.cert}

            # Server TLS configuration
            sslQuorum=true
            ssl.quorum.keyStore.location=${certs.zookeeper.keystore}
            ssl.quorum.trustStore.location=${certs.ca.cert}
          '';
        };
      };
      db = { config, pkgs, ... }: {
        networking.firewall.allowedTCPPorts = [ 5432 ];
        services.postgresql = {
          enable = true;
          enableTCPIP = true;
          initialScript = pkgs.writeText "init-sql-script" ''
            CREATE DATABASE zuul;
            CREATE USER zuul WITH PASSWORD 'zuul';
            GRANT ALL PRIVILEGES ON DATABASE zuul TO zuul;
            \c zuul;
            GRANT ALL ON SCHEMA public TO zuul;
          '';
          authentication = pkgs.lib.mkForce ''
            # Generated file; do not edit!
            # TYPE  DATABASE        USER            ADDRESS                 METHOD
            local   all             all                                     trust
            host    all             all             127.0.0.1/32            trust
            host    all             all             ::1/128                 trust
            host    all             all             all                     scram-sha-256
          '';
        };
      };
      scheduler = { config, pkgs, ... }: {

        imports = [
          self.nixosModules.zuul-scheduler
        ];
        services = {
          openssh = {
            enable = true;
            settings = {
              PermitRootLogin = "yes";
              PermitEmptyPasswords = "yes";
            };
          };
          zuul-scheduler = {
            enable = true;
            config = {
              zookeeper = {
                hosts="zookeeper:2281";
                tls_ca=certs.ca.cert;
                tls_key=certs.zuul.key;
                tls_cert=certs.zuul.cert;
              };
              keystore.password = "12345abcde";
              scheduler.tenant_config = pkgs.writeText "main.yaml" (pkgs.lib.generators.toYAML {} [{
                tenant.name = "test";
              }]);
              database.dburi = "postgresql://zuul:zuul@db:5432/zuul";
            };
          };
        };

        security.pam.services.sshd.allowNullPassword = true;

        virtualisation.forwardPorts = [
          { from = "host"; host.port = 2000; guest.port = 22; }
        ];
        users.users.zuul = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          packages = [
            self.packages.${pkgs.system}.zuul
          ];
        };

        system.stateVersion = "23.11";
      };

      gerrit = { config, pkgs, ... }: {
        virtualisation.forwardPorts = [
          { from = "host"; host.port = 8080; guest.port = 8080; }
        ];
        services.gerrit = {
          enable = true;
          serverId = "1";
          settings = {
            auth = {
              type = "DEVELOPMENT_BECOME_ANY_ACCOUNT";
            };
          };
        };
        networking.firewall.allowedTCPPorts = [ 8080 ];
        system.stateVersion = "23.11";
      };
    };

    extraPythonPackages = p: with p; [
      requests
      types-requests
    ];
    testScript = /* python */ ''
      import json
      import requests

      start_all()
      gerrit.wait_for_unit("multi-user.target")

      r = requests.post("http://localhost:8080/login/%23%2F?action=create_account")
      if r.ok:
        gerrit_account = r.request.headers["Cookie"].split("=")[1]
        xsrf = r.headers["Set-Cookie"].split(";")[0].split("=")[1]

      r = requests.put(
        "http://localhost:8080/a/accounts/self/username",
        cookies={
          "GerritAccount": gerrit_account,
          "XSRF_TOKEN": xsrf,
        },
        headers={
          "Content-Type": "application/json",
          "X-Gerrit-Auth": xsrf,
        },
        data=json.dumps({
          "username": "admin",
        }),
      )
      print(r.text)

      scheduler.wait_for_unit("multi-user.target")
      scheduler.succeed("su -- zuul -c 'zuul-scheduler --version'")
    '';

  };
}
