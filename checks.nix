{ self, pkgs, ... }: {
  "test" = pkgs.testers.runNixOSTest {
    name = "minimal-test";

    nodes.scheduler = { config, pkgs, ... }: {

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PermitEmptyPasswords = "yes";
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

    nodes.gerrit = { config, pkgs, ... }: {
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
      environment.systemPackages = with pkgs; [
          curl
      ];
      networking.firewall.allowedTCPPorts = [ 8080 ];
      system.stateVersion = "23.11";
    };

    extraPythonPackages = p: with p; [
      requests
      types-requests
    ];
    testScript = /* python */ ''
      import json
      import requests

      start_all()
      scheduler.wait_for_unit("default.target")
      scheduler.succeed("su -- zuul -c 'zuul-scheduler --version'")

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
    '';
  };
}
