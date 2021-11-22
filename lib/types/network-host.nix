{ lib, ... }:

{ hostname, ... }:
with lib;
{
  options = with types; {
    ipv4-address = mkOption {
      type = nullOr str;
      description = "The V4 IP of a given host, if any.";
      default = null;
    };

    ipv6-address = mkOption {
      type = nullOr str;
      description = "The V6 IP of a given host, if any.";
      default = null;
    };

    mac-address = mkOption {
      type = nullOr types.str;
      description =
        "The MAC address of a given host, if desired for IP reservation.";
      default = null;
    };

    description = mkOption {
      type = nullOr str;
      description = "Description of the host.";
      default = null;
    };
  };
}
