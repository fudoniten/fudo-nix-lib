{ config, lib, pkgs, ... }:

with lib;
let

  user = import ../types/user.nix { inherit lib; };

  list-includes = list: el: isNull (findFirst (this: this == el) null list);

  filterExistingUsers = users: group-members:
    let user-list = attrNames users;
    in filter (username: list-includes user-list username) group-members;

  hostname = config.instance.hostname;
  host-cfg = config.fudo.hosts.${hostname};

in {
  options = with types; {
    fudo = {
      users = mkOption {
        type = attrsOf (submodule user.userOpts);
        description = "Users";
        default = { };
      };

      groups = mkOption {
        type = attrsOf (submodule user.groupOpts);
        description = "Groups";
        default = { };
      };

      system-users = mkOption {
        type = attrsOf (submodule user.systemUserOpts);
        description = "System users (probably not what you're looking for!)";
        default = { };
      };
    };
  };

  config = let
    sys = config.instance;
  in {
    fudo.auth.ldap-server = {
      users = filterAttrs
        (username: userOpts: userOpts.ldap-hashed-passwd != null)
        config.fudo.users;

      groups = config.fudo.groups;

      system-users = config.fudo.system-users;
    };

    programs.ssh.extraConfig = mkAfter ''
      IdentityFile %h/.ssh/id_rsa
      IdentityFile /etc/ssh/private_keys.d/%u.key
    '';

    environment.etc = mapAttrs' (username: userOpts:
      nameValuePair
        "ssh/private_keys.d/${username}"
        {
          text = concatStringsSep "\n"
            (map (keypair: readFile keypair.public-key)
              userOpts.ssh-keys);
        })
      sys.local-users;

    users = {
      users = mapAttrs (username: userOpts: {
        isNormalUser = true;
        uid = userOpts.uid;
        createHome = true;
        description = userOpts.common-name;
        group = userOpts.primary-group;
        home = if (userOpts.home-directory != null) then
          userOpts.home-directory
        else
          "/home/${userOpts.primary-group}/${username}";
        hashedPassword = userOpts.login-hashed-passwd;
        openssh.authorizedKeys.keys = userOpts.ssh-authorized-keys;
      }) sys.local-users;

      groups = (mapAttrs (groupname: groupOpts: {
        gid = groupOpts.gid;
        members = filterExistingUsers sys.local-users groupOpts.members;
      }) sys.local-groups) // {
        wheel = { members = sys.local-admins; };
        docker = mkIf (host-cfg.docker-server) { members = sys.local-admins; };
      };
    };

    services.nfs.idmapd.settings = let
      local-domain = config.instance.local-domain;
      local-admins = config.instance.local-admins;
      local-users = config.instance.local-users;
      local-realm = config.fudo.domains.${local-domain}.gssapi-realm;
    in {
      General = {
        Verbosity = 10;
        # Domain = local-domain;
        "Local-Realms" = local-realm;
      };
      Translation = {
        GSS-Methods = "static";
      };
      Static = let
        generate-admin-entry = admin: userOpts:
          nameValuePair "${admin}/root@${local-realm}" "root";
        generate-user-entry = user: userOpts:
          nameValuePair "${user}@${local-realm}" user;

        admin-entries =
          mapAttrs' generate-admin-entry (getAttrs local-admins local-users);
        user-entries =
          mapAttrs' generate-user-entry local-users;
      in admin-entries // user-entries;
    };

    # Group home directories have to exist, otherwise users can't log in
    systemd.tmpfiles.rules = let
      groups-with-members = attrNames
        (filterAttrs (group: groupOpts: (length groupOpts.members) > 0)
          sys.local-groups);
    in map (group: "d /home/${group} 550 root ${group} - -") groups-with-members;
  };
}
