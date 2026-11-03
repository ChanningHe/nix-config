# Pull-based ZFS backup on top of services.syncoid.
# This host logs into each source with a read-only delegated user
# (`zfs allow <user> send,bookmark <dataset>`), replicates only the source's
# own `<snapshotPrefix>*` snapshots into an encrypted `targetRoot`, and prunes
# them locally with a bucket-based GFS policy. The source holds no credential
# for this host, so a compromised source cannot delete received snapshots;
# at worst a snapshot burst displaces same-day ones.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.syncoidPull;
  zfs = config.boot.zfs.package;

  targetOf = src: ds: "${src.targetRoot}/${baseNameOf ds}";

  jobName = name: ds: "${name}-${baseNameOf ds}";

  # Jobs of one source run serially: while a target is still being seeded the
  # nixpkgs module delegates on (and afterwards revokes from) the shared
  # targetRoot, which would yank permissions from a sibling's running receive.
  commandsOf =
    name: src:
    lib.imap0 (i: ds: {
      name = jobName name ds;
      value = {
        source = "${src.ssh.user}@${src.ssh.hostName}:${ds}";
        target = targetOf src ds;
        sendOptions = "Lc";
        recvOptions = "u";
        extraArgs = [
          "--no-sync-snap"
          "--create-bookmark"
          "--include-snaps=^${lib.escapeRegex src.snapshotPrefix}"
        ]
        ++ lib.optional (src.ssh.port != 22) "--sshport=${toString src.ssh.port}";
        service = {
          after = lib.optional (i > 0) "syncoid-${jobName name (lib.elemAt src.datasets (i - 1))}.service";
          serviceConfig.Type = "oneshot";
          serviceConfig.ExecStartPre = lib.mkBefore [ "+${prepare}/bin/syncoid-prepare ${src.targetRoot}" ];
          unitConfig.OnFailure = lib.optional cfg.notify.enable "syncoid-notify@%n.service";
        };
      };
    }) src.datasets;

  commands = lib.concatLists (lib.mapAttrsToList commandsOf cfg.sources);
  allUnique = xs: lib.length xs == lib.length (lib.unique xs);

  # Refuse to receive into anything that would store plaintext.
  prepare = pkgs.writeShellApplication {
    name = "syncoid-prepare";
    runtimeInputs = [ zfs ];
    text = ''
      root=$1
      if ! zfs list -H -o name "$root" >/dev/null 2>&1; then
        zfs create -p -o canmount=off -o setuid=off -o devices=off "$root"
      fi
      if [[ $(zfs get -H -o value encryption "$root") == off ]]; then
        echo "refusing to receive: $root is not encrypted" >&2
        exit 1
      fi
      if [[ $(zfs get -H -o value keystatus "$root") != available ]]; then
        echo "key not loaded, run: zfs load-key $(zfs get -H -o value encryptionroot "$root")" >&2
        exit 1
      fi
    '';
  };

  prune = pkgs.writeShellApplication {
    name = "syncoid-prune";
    runtimeInputs = [
      zfs
      pkgs.coreutils
      pkgs.gawk
    ];
    text = builtins.readFile ./prune.sh;
  };

  # Keep pruning the remaining sources when one fails; fail the unit at the end.
  pruneCommandOf =
    _name: src:
    "${
      lib.escapeShellArgs (
        [
          "${prune}/bin/syncoid-prune"
          src.snapshotPrefix
          src.retention.daily
          src.retention.weekly
          src.retention.monthly
        ]
        ++ map (targetOf src) src.datasets
      )
    } || rc=1";

  sourceType = lib.types.submodule {
    options = {
      ssh = {
        hostName = lib.mkOption { type = lib.types.str; };
        user = lib.mkOption {
          type = lib.types.str;
          description = "Remote user holding `send,bookmark` delegation on the datasets.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 22;
        };
        hostPublicKey = lib.mkOption {
          type = lib.types.str;
          description = "Source sshd host key (from ssh-keyscan); pinned via programs.ssh.knownHosts.";
        };
      };
      targetRoot = lib.mkOption {
        type = lib.types.strMatching "[^/].*[^/]";
        example = "Anubias/backup/truenas";
        description = "Local parent dataset; must sit under a loaded encryption root.";
      };
      snapshotPrefix = lib.mkOption {
        type = lib.types.strMatching ".+";
        example = "offsite-";
        description = "Only source snapshots with this prefix are replicated and pruned.";
      };
      retention = {
        daily = lib.mkOption {
          type = lib.types.ints.positive;
          default = 4;
        };
        weekly = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 2;
        };
        monthly = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 4;
        };
      };
      datasets = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Source datasets, each replicated non-recursively to <targetRoot>/<basename>.";
      };
    };
  };
in
{
  options.syncoidPull = {
    enable = lib.mkEnableOption "pull-based ZFS backup via syncoid";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 03:00:00";
      description = "systemd OnCalendar for all syncoid jobs.";
    };

    pruneInterval = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 12:00:00";
      description = "systemd OnCalendar for GFS pruning.";
    };

    sshKey = {
      sopsFile = lib.mkOption { type = lib.types.path; };
      sopsKey = lib.mkOption {
        type = lib.types.str;
        default = "syncoid/ssh_private_key";
      };
    };

    notify = {
      enable = lib.mkEnableOption "failure mails via sendmail";
      from = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      recipients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };

    sources = lib.mkOption {
      type = lib.types.attrsOf sourceType;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          allUnique (map (c: c.name) commands)
          && lib.all (c: builtins.match "[A-Za-z0-9_.-]+" c.name != null) commands;
        message = "syncoidPull: job names (<source>-<dataset basename>) must be unique and match [A-Za-z0-9_.-]+.";
      }
      {
        assertion = allUnique (map (c: c.value.target) commands);
        message = "syncoidPull: two jobs receive into the same target dataset.";
      }
      {
        # keylocation=prompt + systemd-ask-password with no timeout hangs boot.
        assertion = config.boot.zfs.requestEncryptionCredentials != true;
        message = "syncoidPull: boot.zfs.requestEncryptionCredentials must not be true; backup keys are loaded manually.";
      }
      {
        assertion = !cfg.notify.enable || (cfg.notify.from != "" && cfg.notify.recipients != [ ]);
        message = "syncoidPull: notify needs from and recipients.";
      }
    ];

    boot.zfs.requestEncryptionCredentials = lib.mkDefault false;

    sops.secrets.${cfg.sshKey.sopsKey} = {
      inherit (cfg.sshKey) sopsFile;
      owner = config.services.syncoid.user;
      mode = "0400";
    };

    programs.ssh.knownHosts = lib.mapAttrs' (
      name: src:
      lib.nameValuePair "syncoid-${name}" {
        hostNames = [
          (if src.ssh.port == 22 then src.ssh.hostName else "[${src.ssh.hostName}]:${toString src.ssh.port}")
        ];
        publicKey = src.ssh.hostPublicKey;
      }
    ) cfg.sources;

    services.syncoid = {
      enable = true;
      inherit (cfg) interval;
      sshKey = config.sops.secrets.${cfg.sshKey.sopsKey}.path;
      commands = lib.listToAttrs commands;
    };

    systemd.services.syncoid-prune = {
      description = "GFS pruning of syncoid-pulled snapshots";
      # Waits for any syncoid job still running (e.g. a long initial seed).
      after = [ "zfs.target" ] ++ map (c: "syncoid-${c.name}.service") commands;
      startAt = cfg.pruneInterval;
      serviceConfig.Type = "oneshot";
      unitConfig.OnFailure = lib.optional cfg.notify.enable "syncoid-notify@%n.service";
      script = ''
        rc=0
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList pruneCommandOf cfg.sources)}
        exit "$rc"
      '';
    };

    systemd.services."syncoid-notify@" = lib.mkIf cfg.notify.enable {
      description = "Mail failure of %i";
      serviceConfig.Type = "oneshot";
      scriptArgs = "%i";
      path = [ config.systemd.package ];
      script = ''
        unit=$1
        {
          printf 'From: %s\n' ${lib.escapeShellArg cfg.notify.from}
          printf 'To: %s\n' ${lib.escapeShellArg (lib.concatStringsSep "," cfg.notify.recipients)}
          printf 'Subject: [syncoid][%s] %s failed\n\n' ${lib.escapeShellArg config.networking.hostName} "$unit"
          journalctl -u "$unit" -n 80 --no-pager
        } | /run/wrappers/bin/sendmail -t
      '';
    };
  };
}
