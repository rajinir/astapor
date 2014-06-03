class quickstack::cinder_controller(
  $cinder_multiple_backends    = $quickstack::params::cinder_multiple_backends,
  $cinder_backend_gluster      = $quickstack::params::cinder_backend_gluster,
  $cinder_backend_eqlx         = $quickstack::params::cinder_backend_eqlx,
  $cinder_backend_iscsi        = $quickstack::params::cinder_backend_iscsi,
  $cinder_backend_gluster_name = $quickstack::params::cinder_backend_gluster_name,
  $cinder_backend_eqlx_name    = $quickstack::params::cinder_backend_eqlx_name,
  $cinder_backend_iscsi_name   = $quickstack::params::cinder_backend_iscsi_name,
  $cinder_backend_rbd          = $quickstack::params::cinder_backend_rbd,
  $cinder_backend_rbd_name     = $quickstack::params::cinder_backend_rbd_name,
  $cinder_db_password          = $quickstack::params::cinder_db_password,
  $cinder_gluster_volume       = $quickstack::params::cinder_gluster_volume,
  $cinder_gluster_peers        = $quickstack::params::cinder_gluster_peers,
  $cinder_san_ip               = $quickstack::params::cinder_san_ip,
  $cinder_san_login            = $quickstack::params::cinder_san_login,
  $cinder_san_password         = $quickstack::params::cinder_san_password,
  $cinder_san_thin_provision   = $quickstack::params::cinder_san_thin_provision,
  $cinder_eqlx_group_name      = $quickstack::params::cinder_eqlx_group_name,
  $cinder_eqlx_pool            = $quickstack::params::cinder_eqlx_pool,
  $cinder_eqlx_use_chap        = $quickstack::params::cinder_eqlx_use_chap,
  $cinder_eqlx_chap_login      = $quickstack::params::cinder_eqlx_chap_login,
  $cinder_eqlx_chap_password   = $quickstack::params::cinder_eqlx_chap_password,
  $cinder_user_password        = $quickstack::params::cinder_user_password,
  $cinder_rbd_pool             = $quickstack::params::cinder_rbd_pool,
  $cinder_rbd_ceph_conf        = $quickstack::params::cinder_rbd_ceph_conf,
  $cinder_rbd_flatten_volume_from_snapshot
                               = $quickstack::params::cinder_rbd_flatten_volume_from_snapshot,
  $cinder_rbd_max_clone_depth  = $quickstack::params::cinder_rbd_max_clone_depth,
  $cinder_rbd_user             = $quickstack::params::cinder_rbd_user,
  $cinder_rbd_secret_uuid      = $quickstack::params::cinder_rbd_secret_uuid,
  $controller_priv_host        = $quickstack::params::controller_priv_host,
  $mysql_host                  = $quickstack::params::mysql_host,
  $mysql_ca                    = $quickstack::params::mysql_ca,
  $ssl                         = $quickstack::params::ssl,
  $qpid_host                   = $quickstack::params::qpid_host,
  $qpid_port                   = "5672",
  $qpid_protocol               = "tcp",
  $qpid_username               = $quickstack::params::qpid_username,
  $qpid_password               = $quickstack::params::qpid_password,
  $verbose                     = $quickstack::params::verbose,
) inherits quickstack::params {

  $qpid_password_safe_for_cinder = $qpid_password ? {
    ''      => 'guest',
    false   => 'guest',
    default => $qpid_password,
  }

  cinder_config {
    'DEFAULT/glance_host': value => $controller_priv_host;
    'DEFAULT/notification_driver': value => 'cinder.openstack.common.notifier.rpc_notifier'
  }

  if str2bool_i("$ssl") {
    $sql_connection = "mysql://cinder:${cinder_db_password}@${mysql_host}/cinder?ssl_ca=${mysql_ca}"
  } else {
    $sql_connection = "mysql://cinder:${cinder_db_password}@${mysql_host}/cinder"
  }

  class {'::cinder':
    rpc_backend    => 'cinder.openstack.common.rpc.impl_qpid',
    qpid_hostname  => $qpid_host,
    qpid_protocol  => $qpid_protocol,
    qpid_port      => $qpid_port,
    qpid_username  => $qpid_username,
    qpid_password  => $qpid_password_safe_for_cinder,
    sql_connection => $sql_connection,
    verbose        => $verbose,
    require        => Class['quickstack::db::mysql', 'qpid::server'],
  }

  class {'::cinder::api':
    keystone_password => $cinder_user_password,
    keystone_tenant => "services",
    keystone_user => "cinder",
    keystone_auth_host => $controller_priv_host,
  }

  class {'::cinder::scheduler': }

  if !str2bool_i("$cinder_multiple_backends")
  {

    if str2bool_i("$cinder_backend_gluster") {
      class { '::cinder::volume': }

      if defined('gluster::client') {
        class { 'gluster::client': }
      } else {
        class { 'gluster::mount::base': repo => false }
      }

      if ($::selinux != "false") {
        selboolean{'virt_use_fusefs':
          value => on,
          persistent => true,
        }
      }

      class { '::cinder::volume::glusterfs':
        glusterfs_mount_point_base => '/var/lib/cinder/volumes',
        glusterfs_shares           => suffix($cinder_gluster_peers, ":/${cinder_gluster_volume}")
      }
    }
    elsif str2bool_i("$cinder_backend_eqlx") {

      class { '::cinder::volume': }

      class { '::cinder::volume::eqlx':
        san_ip             => $cinder_san_ip,
        san_login          => $cinder_san_login,
        san_password       => $cinder_san_password,
        san_thin_provision => $cinder_san_thin_provision,
        eqlx_group_name    => $cinder_eqlx_group_name,
        eqlx_pool          => $cinder_eqlx_pool,
        eqlx_use_chap      => $cinder_eqlx_use_chap,
        eqlx_chap_login    => $cinder_eqlx_chap_login,
        eqlx_chap_password => $cinder_eqlx_chap_password,
      }
    }
    elsif str2bool_i("$cinder_backend_rbd") {

      class { '::cinder::volume': }

      cinder::backend::rbd { 'rbd':
        volume_backend_name  => $cinder_backend_rbd_name,
        rbd_pool             => $cinder_rbd_pool,
        rbd_ceph_conf        => $cinder_rbd_ceph_conf,
        rbd_flatten_volume_from_snapshot
                             => $cinder_rbd_flatten_volume_from_snapshot,
        rbd_max_clone_depth  => $cinder_rbd_max_clone_depth,
        rbd_user             => $cinder_rbd_user,
        rbd_secret_uuid      => $cinder_rbd_secret_uuid,
      }
    }
    else {
      #Default to ISCSI
      class { '::cinder::volume': }

      class { '::cinder::volume::iscsi':
        iscsi_ip_address => $controller_priv_host,
      }

      firewall { '010 cinder iscsi':
        proto  => 'tcp',
        dport  => ['3260'],
        action => 'accept',
      }
    }
  }
  else {
    # Define a cinder storage node with multiple backends
    class { 'cinder::volume': }

    # Gluster Backend
    if str2bool_i("$cinder_backend_gluster") {
      $g_backend = ["glusterfs"]

      if defined('gluster::client') {
        class { 'gluster::client': }
      } else {
        class { 'gluster::mount::base': repo => false }
      }

      if ($::selinux != "false") {
        selboolean{'virt_use_fusefs':
          value => on,
          persistent => true,
        }
      }

      cinder::backend::glusterfs{ 'glusterfs':
        volume_backend_name        => $cinder_backend_glusterfs_name,
        glusterfs_mount_point_base => '/var/lib/cinder/volumes',
        glusterfs_shares           => suffix($cinder_gluster_peers, ":/${cinder_gluster_volume}")
      }
    }

    if str2bool_i("$cinder_backend_eqlx") {

      $e_backend =["eqlx"]

      cinder::backend::eqlx { 'eqlx':
        volume_backend_name => $cinder_backend_eqlx_name,
        san_login           => $cinder_san_login,
        san_password        => $cinder_san_password,
        san_thin_provision  => $cinder_san_thin_provision,
        eqlx_group_name     => $cinder_eqlx_group_name,
        eqlx_pool           => $cinder_eqlx_pool,
        eqlx_use_chap       => $cinder_eqlx_use_chap,
        eqlx_chap_login     => $cinder_eqlx_chap_login,
        eqlx_chap_password  => $cinder_eqlx_chap_password,
      }
    }

    if str2bool_i("$cinder_backend_rbd") {

      $r_backend =["rbd"]

      cinder::backend::rbd { 'rbd':
        volume_backend_name => $cinder_backend_rbd_name,
        rbd_pool             => $cinder_rbd_pool,
        rbd_ceph_conf        => $cinder_rbd_ceph_conf,
        rbd_flatten_volume_from_snapshot
                             => $cinder_rbd_flatten_volume_from_snapshot,
        rbd_max_clone_depth  => $cinder_rbd_max_clone_depth,
        rbd_user             => $cinder_rbd_user,
        rbd_secret_uuid      => $cinder_rbd_secret_uuid,
      }
    }

    # ISCSI Backend
    if str2bool_i("$cinder_backend_iscsi")  or ( !str2bool_i("$cinder_backend_glusterfs") and !str2bool_i("$cinder_backend_eqlx") and !str2bool_i("$cinder_backend_rbd")) {

      $i_backend = ["iscsi"]

      cinder::backend::iscsi { 'iscsi':
        iscsi_ip_address => $controller_priv_host,
      }

      firewall { '010 cinder iscsi':
        proto  => 'tcp',
        dport  => ['3260'],
        action => 'accept',
      }
    }

    # Enable the backends
    class { 'cinder::backends':
      enabled_backends => join_arrays_if_exist('g_backend', 'e_backend', 'i_backend', 'r_backend'),
    }
  }
}
