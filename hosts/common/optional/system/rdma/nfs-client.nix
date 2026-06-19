# NFS-over-RDMA (RoCE) CLIENT tuning.
#
{ ... }:
{
  # Client tooling: mount.nfs, nfsstat, mountstats, nfsiostat.
  #environment.systemPackages = [ pkgs.nfs-utils ];

  # RPC-over-RDMA client transport. Loading it here (not lazily on mount) is
  # what makes the sysctl below land reliably at boot.
  boot.kernelModules = [ "rpcrdma" ];

  boot.kernel.sysctl = {
    # Max concurrent outstanding RDMA RPC requests. Default is 128; 256 is the
    # kernel ceiling (RPCRDMA_MAX_SLOT_TABLE). More in-flight RPCs = higher
    # throughput on parallel / random workloads. Set before any NFS mount.
    "sunrpc.rdma_slot_table_entries" = 256;
  };

  # Recommended client mount options (set where the mount is defined, e.g. a
  # host fileSystems."/mnt/x" entry or autofs — server IP belongs in secrets):
  #
  #   fileSystems."/mnt/share" = {
  #     device  = "10.0.0.1:/export";
  #     fsType  = "nfs";
  #     options = [
  #       "proto=rdma" "port=20049"   # force the RDMA transport
  #       "vers=4.2"                   # v4.1+; RDMA also works with v3
  #       "rsize=1048576" "wsize=1048576"  # 1 MiB I/O, RDMA's sweet spot
  #       "nconnect=8"                 # parallel RDMA connections (<=16)
  #       "hard" "timeo=600" "retrans=2"   # safe defaults for RDMA
  #       "noatime" "_netdev"
  #     ];
  #   };
  #
  # Verify after mounting:
  #   mount | grep rdma          # proto must show 'rdma'
  #   mountstats /mnt/share      # RPC backlog / RTT
  #   nfsiostat 2                # live throughput / latency
}
