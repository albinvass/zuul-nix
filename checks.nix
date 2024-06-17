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

    testScript = /* python */ ''
      def get_gerrit_account():
          res = gerrit.succeed("curl --fail-with-body -X POST http://localhost:8080/login/%23%2F?action=create_account -D - -o /dev/null -s")
          for line in res.splitlines():
              if line.startswith("Set-Cookie"):
                  if "GerritAccount" in line:
                      user_id=line.split(":")[1].split(";")[0].split("=")[1]
          return user_id

      def get_xsrf(gerrit_account):
           res = gerrit.succeed(f'curl --fail-with-body http://localhost:8080/ -s -H "Cookie: GerritAccount={gerrit_account}" -D - -o /dev/null')
           for line in res.splitlines():
               if line.startswith("Set-Cookie:"):
                   return line.split(":")[1].split(";")[0].split("=")[1]

      scheduler.wait_for_unit("default.target")
      scheduler.succeed("su -- zuul -c 'zuul-scheduler --version'")

      gerrit.wait_for_unit("multi-user.target")

      gerrit_account = get_gerrit_account()
      xsrf = get_xsrf(gerrit_account)
      gerrit.succeed(f'curl --fail-with-body -X PUT http://localhost:8080/a/accounts/self/username -H "Cookie: GerritAccount={gerrit_account}; XSRF_TOKEN={xsrf}" -d \'{{"username": "admin"}}\' -H "X-Gerrit-Auth: {xsrf}" -H "Content-Type: application/json" -vv')
    '';
  };
}
