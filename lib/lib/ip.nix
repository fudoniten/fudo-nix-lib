{ pkgs, ... }:

with pkgs.lib;
let
  pow = x: e: if (e == 0) then 1 else x * (pow x (e - 1));

  generateNBits = n:
    let
      helper = n: c:
        if (c == n) then pow 2 c else (pow 2 c) + (helper n (c + 1));
    in if (n <= 0) then
      throw "Can't generate 0 or fewer bits"
    else
      helper (n - 1) 0;

  rightPadBits = int: bits: bitOr int (generateNBits bits);

  reverseIpv4 = ip: concatStringsSep "." (reverseList (splitString "." ip));

  intToBinaryList = int:
    let
      helper = int: cur:
        let curExp = pow 2 cur;
        in if (curExp > int) then
          [ ]
        else
          [ (if ((bitAnd curExp int) > 0) then 1 else 0) ]
          ++ (helper int (cur + 1));
    in reverseList (helper int 0);

  leftShift = int: n: int * (pow 2 n);

  rightShift = int: n: int / (pow 2 n);

in rec {

  ipv4ToInt = ip:
    let els = map toInt (reverseList (splitString "." ip));
    in foldr (a: b: a + b) 0 (imap0 (i: el: (leftShift el (i * 8))) els);

  intToIpv4 = int:
    concatStringsSep "."
    (map (i: toString (bitAnd (rightShift int (i * 8)) 255)) [ 3 2 1 0 ]);

  maskFromV32Network = network:
    let
      fullMask = ipv4ToInt "255.255.255.255";
      insignificantBits = 32 - (getNetworkMask network);
    in intToIpv4
    (leftShift (rightShift fullMask insignificantBits) insignificantBits);

  networkMinIp = network: intToIpv4 (1 + (ipv4ToInt (getNetworkBase network)));

  networkMaxIp = network:
    intToIpv4 (rightPadBits (ipv4ToInt (getNetworkBase network))
      (32 - (getNetworkMask network)));

  # To avoid broadcast IP...
  networkMaxButOneIp = network:
    intToIpv4 ((rightPadBits (ipv4ToInt (getNetworkBase network))
      (32 - (getNetworkMask network))) - 1);

  ipv4OnNetwork = ip: network:
    let
      ip-int = ipv4ToInt ip;
      net-min = networkMinIp network;
      net-max = networkMaxIp network;
    in (ip-int >= networkMinIp) && (ip-int <= networkMaxIp);

  getNetworkMask = network: toInt (elemAt (splitString "/" network) 1);

  getNetworkBase = network:
    let
      ip = elemAt (splitString "/" network) 0;
      insignificantBits = 32 - (getNetworkMask network);
    in intToIpv4
    (leftShift (rightShift (ipv4ToInt ip) insignificantBits) insignificantBits);
}
