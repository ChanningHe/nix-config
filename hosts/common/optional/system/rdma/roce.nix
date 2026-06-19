# RDMA-over-Converged-Ethernet (RoCE) host tuning.
#
# This is RoCE, NOT InfiniBand: RDMA rides on top of the Ethernet NIC, so we
# deliberately do NOT load IB-only bits (ib_ipoib, opensm, ib_isert) — those
# are pointless without an IB fabric and only add attack surface.
#
# Lossless/PFC/ECN priority-flow-control belongs on the NIC + switch (mlnx_qos,
# DCBX) and, for a passed-through VF, on the hypervisor/switch — it is not a
# kernel sysctl, so it is intentionally out of scope here.
{ pkgs, ... }:
{
  # RDMA verbs stack for RoCE. ib_core / rdma_cm load automatically as deps.
  #   mlx5_ib    - RoCE provider for ConnectX NICs
  #   ib_uverbs  - userspace verbs (/dev/infiniband/uverbsN)
  #   rdma_ucm   - userspace connection manager (/dev/infiniband/rdma_cm)
  #   ib_umad    - management datagrams (needed by ibstat / perftest)
  boot.kernelModules = [
    "mlx5_ib"
    "ib_uverbs"
    "rdma_ucm"
    "ib_umad"
    "rpcrdma"
  ];

  # Userspace tooling:
  #   rdma-core - ibv_devinfo / ibstat / rdma(8)
  #   perftest  - ib_write_bw / ib_read_bw / ib_send_lat throughput+latency
  #   ethtool   - ring/offload/counter inspection
  environment.systemPackages = with pkgs; [
    rdma-core
    #perftest
    ethtool
  ];

  boot.kernel.sysctl = {
    # Large socket buffers: helps RDMA-CM setup and any TCP control path that
    # runs alongside the RDMA data path.
    "net.core.rmem_max" = 268435456; # 256 MiB
    "net.core.wmem_max" = 268435456;
    "net.core.optmem_max" = 16777216;

    # Loose reverse-path filtering. RoCE hosts are commonly multi-homed (one
    # IP per RoCE port); strict rp_filter silently drops asymmetric ARP/CM
    # traffic. Loose (2) keeps anti-spoofing without breaking RoCE.
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;

    # ARP flux avoidance on multi-interface RoCE hosts (Mellanox guidance):
    # only answer ARP for the IP on the receiving interface, and source ARP
    # from the best local address.
    # "net.ipv4.conf.all.arp_ignore" = 1;
    # "net.ipv4.conf.all.arp_announce" = 2;

    # Bigger neighbour (ARP) table so a large RoCE fabric doesn't overflow it.
    "net.ipv4.neigh.default.gc_thresh1" = 4096;
    "net.ipv4.neigh.default.gc_thresh2" = 8192;
    "net.ipv4.neigh.default.gc_thresh3" = 16384;
  };
}
