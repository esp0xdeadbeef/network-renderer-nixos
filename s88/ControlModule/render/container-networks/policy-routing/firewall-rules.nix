{ lib }:

{
  forwardingRulesFromRuleset =
    firewallRuleset:
    if builtins.isString firewallRuleset then
      lib.filter (rule: rule != null) (
        lib.imap0 (
          _: line:
          let
            match = builtins.match ''.*iifname "([^"]+)" oifname "([^"]+)".* accept.*'' line;
          in
          if match == null then
            null
          else
            {
              action = "accept";
              fromInterface = builtins.elemAt match 0;
              toInterface = builtins.elemAt match 1;
            }
        ) (lib.splitString "\n" firewallRuleset)
      )
    else
      [ ];
}
