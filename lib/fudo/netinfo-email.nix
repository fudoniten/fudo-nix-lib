{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.fudo.netinfo-email;

  make-script = server: port: target: pkgs.writeText "netinfo-script.rb" ''
    #!${pkgs.ruby}/bin/ruby

    require 'net/smtp'

    raise RuntimeError.new("NETINFO_SMTP_USERNAME not set!") if not ENV['NETINFO_SMTP_USERNAME']
    user = ENV['NETINFO_SMTP_USERNAME']

    raise RuntimeError.new("NETINFO_SMTP_PASSWD not set!") if not ENV['NETINFO_SMTP_PASSWD']
    passwd = ENV['NETINFO_SMTP_PASSWD']

    hostname = `${pkgs.inetutils}/bin/hostname -f`.strip
    date = `${pkgs.coreutils}/bin/date +%Y-%m-%d`.strip
    email_date = `${pkgs.coreutils}/bin/date`
    ipinfo = `${pkgs.iproute}/bin/ip addr`

    message = <<EOM
    From: #{user}@fudo.org
    To: ${target}
    Subject: #{hostname} network info for #{date}
    Date: #{email_date}

    #{ipinfo}
    EOM

    smtp = Net::SMTP.new("${server}", ${toString port})
    smtp.enable_starttls

    smtp.start('localhost', user, passwd) do |server|
      server.send_message(message, "#{user}@fudo.org", ["${target}"])
    end
  '';

in {

  options.fudo.netinfo-email = {
    enable = mkEnableOption "Enable netinfo email (hacky way to keep track of a host's IP";

    smtp-server = mkOption {
      type = types.str;
      default = "mail.fudo.org";
    };

    smtp-port = mkOption {
      type = types.port;
      default = 587;
    };

    env-file = mkOption {
      type = types.str;
      description = "Path to file containing NETINFO_SMTP_USERNAME and NETINFO_SMTP_PASSWD";
    };

    target-email = mkOption {
      type = types.str;
      default = "network-info@fudo.link";
      description = "Email to which to send network info report.";
    };
  };

  config = mkIf cfg.enable {
    systemd = {
      timers.netinfo = {
        enable = true;
        description = "Send network info to ${cfg.target-email}";
        partOf = ["netinfo.service"];
        wantedBy = [ "timers.target" ];
        requires = [ "network-online.target" ];
        timerConfig = {
          OnCalendar = "daily";
        };
      };

      services.netinfo = {
        enable = true;
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal";
          EnvironmentFile = cfg.env-file;
        };
        script = ''
          ${pkgs.ruby}/bin/ruby ${make-script cfg.smtp-server cfg.smtp-port cfg.target-email}
        '';
      };
    };
  };
}
